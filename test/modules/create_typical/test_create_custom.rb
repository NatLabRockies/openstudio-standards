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
