require_relative '../../helpers/minitest_helper'

class TestCreateCustom < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    @examples_dir = File.expand_path('../../../lib/openstudio-standards/create_typical/data/examples', __dir__)
    FileUtils.mkdir "#{__dir__}/output" unless Dir.exist? "#{__dir__}/output"
  end

  def test_create_custom_building_from_spec_example
    spec = JSON.parse(File.read("#{@examples_dir}/custom_mixed_use_building.json"), symbolize_names: true)
    spec[:typical_options][:sizing_run_directory] = "#{__dir__}/output/#{__method__}"

    model = OpenStudio::Model::Model.new
    result = @create.create_custom_building_from_spec(model, spec)
    assert(result)

    # four space types from the ratio entries
    assert_equal(4, model.getSpaceTypes.size)

    # custom name label applied without touching standards keys
    assert_equal('Mixed Use Campus Hub', model.getBuilding.name.to_s)
    custom_type = model.getBuilding.additionalProperties.getFeatureAsString('custom_building_type')
    assert(custom_type.is_initialized)
    assert_equal('Mixed Use Campus Hub', custom_type.get)

    # primary_building_type override wins over the area-max winner (Warehouse at 0.5)
    assert_equal('MediumOffice', model.getBuilding.standardsBuildingType.get)

    # no HVAC per typical_options
    assert_equal(0, model.getAirLoopHVACs.size)

    # load override: wildcard LPD applies to all space types
    expected_lpd_si = OpenStudio.convert(0.85, 'W/ft^2', 'W/m^2').get
    model.getSpaceTypes.each do |space_type|
      next if space_type.lights.empty?

      assert_in_delta(expected_lpd_si, space_type.lights.first.lightsDefinition.wattsperSpaceFloorArea.get, 0.0001,
                      "#{space_type.name} LPD should follow the wildcard load override")
    end

    # schedule override: conference occupancy reaches the overridden base
    conference = model.getSpaceTypes.find do |st|
      st.additionalProperties.getFeatureAsString('standards_space_type').is_initialized &&
        st.additionalProperties.getFeatureAsString('standards_space_type').get == 'conference/meeting/multipurpose'
    end
    refute_nil(conference)
    occ_sch = conference.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    day_schedules = [occ_sch.defaultDaySchedule] + occ_sch.scheduleRules.map(&:daySchedule)
    values = day_schedules.flat_map { |day_sch| OpenstudioStandards::Schedules.schedule_day_get_hourly_values(day_sch) }
    assert_in_delta(0.03, values.min, 0.01, 'conference occupancy should reach its overridden base')

    model.save("#{__dir__}/output/test_create_custom_building_from_spec.osm", true)
  end

  def test_create_custom_building_from_spec_json_string
    spec_json = <<~JSON
      {
        "name": "JSON String Test Building",
        "template": "90.1-2013",
        "climate_zone": "ASHRAE 169-2013-4A",
        "space_type_ratios": [
          { "building_type": "MediumOffice", "space_type": "OpenOffice", "ratio": 0.8 },
          { "building_type": "MediumOffice", "space_type": "Conference", "ratio": 0.2 }
        ],
        "form": { "total_bldg_floor_area": 10000.0 },
        "typical_options": {
          "add_hvac": false,
          "add_swh": false,
          "add_exterior_lights": false,
          "add_daylighting_controls": false,
          "add_refrigeration": false
        }
      }
    JSON

    model = OpenStudio::Model::Model.new
    result = @create.create_custom_building_from_spec(model, spec_json)
    assert(result)
    assert_equal(2, model.getSpaceTypes.size)
    assert_equal('JSON String Test Building', model.getBuilding.name.to_s)
    # space types received loads and schedules
    model.getSpaceTypes.each do |space_type|
      assert_operator(space_type.lights.size, :>, 0, "#{space_type.name} should have a Lights load")
      assert(space_type.defaultScheduleSet.is_initialized)
    end
  end

  def test_create_custom_building_from_spec_typical_space_types
    spec = JSON.parse(File.read("#{@examples_dir}/custom_typical_space_types_building.json"), symbolize_names: true)
    spec[:typical_options][:sizing_run_directory] = "#{__dir__}/output/#{__method__}"
    # user ventilation override on top of the template-based standards rates
    spec[:load_overrides] << { space_type: 'lounge/breakroom', ventilation: { cfm_per_area: 0.25 } }

    # keep_standard_design_level: target a peak occupancy at half the standard conference density
    standard = Standard.build('90.1-2013')
    conference_props = standard.model_find_object(standard.standards_data['space_types'],
                                                  'template' => '90.1-2013', 'building_type' => 'Office', 'space_type' => 'Conference')
    refute_nil(conference_props)
    conference_standard_occ = conference_props['occupancy_per_area'].to_f
    conference_target_occ = (conference_standard_occ * 0.5).round(2)
    spec[:load_overrides] << { space_type: 'conference/meeting/multipurpose',
                               people: { people_per_1000_ft2: conference_target_occ, keep_standard_design_level: true } }

    model = OpenStudio::Model::Model.new
    result = @create.create_custom_building_from_spec(model, spec)
    assert(result)

    # six space types from the ratio entries, typed by the level-1 typical name.
    # No standards building type is set on the space types themselves; the SDK getter
    # reports the Building-level value (the primary building type) by inheritance.
    assert_equal(6, model.getSpaceTypes.size)
    model.getSpaceTypes.each do |space_type|
      assert(space_type.standardsSpaceType.is_initialized)
      assert_equal('MediumOffice', space_type.standardsBuildingType.get,
                   "#{space_type.name} should inherit the building-level standards building type")
    end

    office = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'office' }
    refute_nil(office)

    # typical lighting: definitions carry the lighting technology properties
    assert_operator(office.lights.size, :>, 0, 'office should have typical lights')
    lights_def = office.lights.first.lightsDefinition
    assert(lights_def.additionalProperties.getFeatureAsString('lighting_technology').is_initialized,
           'lights should come from the typical lighting data')

    # typical equipment: office electric equipment created (median fallback when the
    # space type carries no standards building type)
    assert_operator(office.electricEquipment.size, :>, 0, 'office should have typical electric equipment')

    # ventilation defaults to the template rates from the standards space types data,
    # resolved through the level-1 standards space type mapping
    dsoa = office.designSpecificationOutdoorAir
    assert(dsoa.is_initialized, 'office should have a design specification outdoor air object')
    assert_in_delta(OpenStudio.convert(5.0, 'ft^3/min', 'm^3/s').get, dsoa.get.outdoorAirFlowperPerson, 0.0001)
    vent_source = dsoa.get.additionalProperties.getFeatureAsString('ventilation_source')
    assert(vent_source.is_initialized)
    assert_equal('90.1-2013 Office | OpenOffice', vent_source.get, 'office ventilation should come from the template standards data')

    # user load override wins over the template-based ventilation rates
    lounge = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'lounge/breakroom' }
    refute_nil(lounge)
    lounge_dsoa = lounge.designSpecificationOutdoorAir.get
    assert_in_delta(OpenStudio.convert(0.25, 'ft^3/min*ft^2', 'm^3/s*m^2').get, lounge_dsoa.outdoorAirFlowperFloorArea, 0.0001,
                    'lounge ventilation should follow the user load override')

    # parametric schedules resolved from the level-1 schedule set
    assert(office.defaultScheduleSet.is_initialized)
    assert(office.defaultScheduleSet.get.lightingSchedule.is_initialized, 'office should have a lighting schedule')

    # occupancy defaults to the template densities from the standards space types data
    assert_operator(office.people.size, :>, 0, 'office should have typical occupancy')
    occ_source = office.people.first.peopleDefinition.additionalProperties.getFeatureAsString('occupancy_source')
    assert(occ_source.is_initialized)
    assert_equal('90.1-2013 Office | OpenOffice', occ_source.get, 'office occupancy should come from the template standards data')

    # direct people load override sets the design occupancy level on the classroom space type
    classroom = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'classroom/lecture/training' }
    refute_nil(classroom)
    assert_operator(classroom.people.size, :>, 0, 'classroom should have a People load')
    expected_density_si = OpenStudio.convert(40.0 / 1000.0, 'people/ft^2', 'people/m^2').get
    assert_in_delta(expected_density_si, classroom.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001)

    # keep_standard_design_level: conference keeps the standard density and the occupancy
    # schedule peak is adjusted so peak occupancy matches the override target
    conference = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'conference/meeting/multipurpose' }
    refute_nil(conference)
    expected_standard_si = OpenStudio.convert(conference_standard_occ / 1000.0, 'people/ft^2', 'people/m^2').get
    assert_in_delta(expected_standard_si, conference.people.first.peopleDefinition.peopleperSpaceFloorArea.get, 0.0001,
                    'conference should keep the standard design occupancy level')
    expected_peak = conference_target_occ / conference_standard_occ
    occ_sch = conference.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    day_schedules = [occ_sch.defaultDaySchedule] + occ_sch.scheduleRules.map(&:daySchedule)
    values = day_schedules.flat_map { |day_sch| OpenstudioStandards::Schedules.schedule_day_get_hourly_values(day_sch) }
    assert_in_delta(expected_peak, values.max, 0.01, 'conference occupancy schedule peak should hit the override target')

    # primary building type drives the building-level standards building type
    assert_equal('MediumOffice', model.getBuilding.standardsBuildingType.get)

    model.save("#{__dir__}/output/test_create_custom_building_from_spec_typical.osm", true)
  end

  def test_create_custom_building_from_spec_invalid_leaves_model_untouched
    spec = {
      template: '90.1-2013',
      climate_zone: 'ASHRAE 169-2013-4A',
      space_type_ratios: [
        { building_type: 'MediumOffice', space_type: 'OpenOffice', ratio: 0.5 },
        { building_type: 'MediumOffice', space_type: 'Conference', ratio: 0.3 }
      ]
    }

    model = OpenStudio::Model::Model.new
    result = @create.create_custom_building_from_spec(model, spec)
    assert_equal(false, result, 'ratios summing to 0.8 should fail validation')
    assert_equal(0, model.getSpaces.size)
    assert_equal(0, model.getSpaceTypes.size)

    # unparsable JSON string also fails without touching the model
    assert_equal(false, @create.create_custom_building_from_spec(model, '{"template": '))
    assert_equal(0, model.getSpaces.size)
  end
end
