require_relative '../../helpers/minitest_helper'

class TestThermalZoneThermostatSchedules < Minitest::Test
  def setup
    @zone = OpenstudioStandards::ThermalZone
    @sch = OpenstudioStandards::Schedules
  end

  def test_thermal_zones_set_thermostat_schedules_primary_school
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/ASHRAEPrimarySchool.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: false))

    # test assigning thermostat schedules
    assert(@zone.thermal_zones_set_thermostat_schedules(model.getThermalZones))
    test_zone = model.getThermalZoneByName('TZ-Mult_Class_1_Pod_1_ZN_1_FLR_1').get
    thermostat = test_zone.thermostatSetpointDualSetpoint.get

  end

  def test_thermal_zones_set_thermostat_schedules_ese
    # load a model and set up weather file
    template = 'DEER 2011'
    climate_zone = 'CEC T24-CEC3'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../../data/geometry/DEER_ESe.osm")
    assert(OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone))
    assert(std.prototype_space_type_map(model, reset_standards_space_type: false, set_additional_properties: false))

    # test assigning thermostat schedules
    assert(@zone.thermal_zones_set_thermostat_schedules(model.getThermalZones))
    test_zone = model.getThermalZoneByName('E1 West Perim Spc (G.W1) ZN').get
    thermostat = test_zone.thermostatSetpointDualSetpoint.get

    # the zone gets a thermostat of its own carrying both setpoint schedules
    assert_equal("#{test_zone.name} Thermostat", thermostat.name.to_s)
    assert(thermostat.heatingSetpointTemperatureSchedule.is_initialized)
    assert(thermostat.coolingSetpointTemperatureSchedule.is_initialized)
  end

  # A space type found under many building types takes the setpoints of the one it is most
  # commonly found in: corridors and offices from an office, libraries from a school.
  def test_space_type_thermostat_setpoints_uses_common_building_type
    office = @zone.space_type_thermostat_setpoints('office')
    assert_equal('Office', office[:source_building_type])
    assert_equal('Office', @zone.space_type_thermostat_setpoints('corridor')[:source_building_type])
    assert_equal('SecondarySchool', @zone.space_type_thermostat_setpoints('library')[:source_building_type])

    # a qualified variant with no entry of its own inherits its base type
    assert_equal(office[:heating_setpoint_c],
                 @zone.space_type_thermostat_setpoints('office - enclosed')[:heating_setpoint_c])
    assert_nil(@zone.space_type_thermostat_setpoints('not a space type'))

    # the curated warehouse storage types are heated but not cooled
    cooled_c = OpenStudio.convert(91.0, 'F', 'C').get
    bulk = @zone.space_type_thermostat_setpoints('storage - warehouse - medium to bulky palletized items')
    assert(bulk[:cooling_setpoint_c] > cooled_c, 'bulk warehouse storage should not be cooled')
  end

  # A model whose space type means something other than what the stock data describes says
  # so through thermostat_overrides -- warehouse storage held as an unheated bulk store
  # rather than as the conditioned storage room 'storage' otherwise resolves to.
  def test_space_type_thermostat_setpoints_with_overrides
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('storage')

    stock = @zone.space_type_thermostat_setpoints_with_overrides(space_type, 'storage', nil)
    cooled_c = OpenStudio.convert(91.0, 'F', 'C').get
    assert(stock[:cooling_setpoint_c] < cooled_c, 'storage defaults to a conditioned space type')

    overrides = [{ space_type: 'storage',
                   thermostat: { heating_setpoint_c: 7.2, cooling_setpoint_c: 50.0 } }]
    overridden = @zone.space_type_thermostat_setpoints_with_overrides(space_type, 'storage', overrides)
    assert_in_delta(7.2, overridden[:heating_setpoint_c], 0.01)
    assert(overridden[:cooling_setpoint_c] > cooled_c, 'the override should leave storage uncooled')
    # fields are overridden individually, so an unstated setback keeps the stock value
    assert_in_delta(stock[:cooling_setback_delta_c], overridden[:cooling_setback_delta_c], 0.01)

    # a space type with no setpoint data of its own needs both setpoints from the override
    invented = @zone.space_type_thermostat_setpoints_with_overrides(
      space_type, 'not a space type',
      [{ space_type: 'not a space type', thermostat: { heating_setpoint_c: 18.0, cooling_setpoint_c: 27.0 } }]
    )
    assert_in_delta(18.0, invented[:heating_setpoint_c], 0.01)
    assert_equal(0.0, invented[:heating_setback_delta_c], 'an unstated setback defaults to none')
    assert_nil(@zone.space_type_thermostat_setpoints_with_overrides(
                 space_type, 'not a space type',
                 [{ space_type: 'not a space type', thermostat: { heating_setpoint_c: 18.0 } }]
               ), 'a partial override of an unknown space type cannot build a thermostat')

    # a single field can be overridden without restating the rest
    partial = @zone.space_type_thermostat_setpoints_with_overrides(
      space_type, 'storage', [{ space_type: '*', thermostat: { cooling_setpoint_c: 26.0 } }]
    )
    assert_in_delta(26.0, partial[:cooling_setpoint_c], 0.01)
    assert_in_delta(stock[:heating_setpoint_c], partial[:heating_setpoint_c], 0.01)

    # an entry keyed to another space type does not apply
    other = @zone.space_type_thermostat_setpoints_with_overrides(
      space_type, 'storage', [{ space_type: 'office', thermostat: { cooling_setpoint_c: 50.0 } }]
    )
    assert_in_delta(stock[:cooling_setpoint_c], other[:cooling_setpoint_c], 0.01)

    # entries arriving with string keys, as a spec assembled from JSON or built by a
    # measure carries, have to work the same as symbol-keyed ones
    string_keyed = OpenstudioStandards::CreateTypical.parse_overrides_argument(
      [{ 'space_type' => 'storage', 'thermostat' => { 'cooling_setpoint_c' => 50.0 } }], 'thermostat_overrides'
    )
    from_strings = @zone.space_type_thermostat_setpoints_with_overrides(space_type, 'storage', string_keyed)
    assert_in_delta(50.0, from_strings[:cooling_setpoint_c], 0.01)
  end

  # One thermostat serves a whole zone, so a zone holding several space types has to be
  # conditioned for the tightest of them.
  # A record whose heating and cooling setpoints meet is a knife edge: the zone flips its
  # terminal between heating and cooling demand every HVAC iteration. Three prototype
  # schedule pairs genuinely carry one (Laboratory, the Outpatient OR when occupied, the
  # SmallHotel occupied guest room), and on a validation hospital model the extracted pair
  # cost an 80x slower sizing run and every SimHVAC max-iteration event on the loop serving
  # those zones. The generator now refuses to emit such a row.
  def test_no_thermostat_setpoint_row_is_knife_edge
    data_path = File.expand_path('../../../lib/openstudio-standards/thermal_zone/data/thermostat_setpoints.json', __dir__)
    rows = JSON.parse(File.read(data_path))['space_types']
    floor = OpenstudioStandards::ThermalZone::MINIMUM_DEADBAND_K

    degenerate = rows.select { |row| row['cooling_setpoint_c'].to_f - row['heating_setpoint_c'].to_f < floor }
                     .map { |row| "#{row['space_type_name']} (htg #{row['heating_setpoint_c']} / clg #{row['cooling_setpoint_c']})" }
    assert_empty(degenerate, "setpoint rows with less than #{floor} K between heating and cooling: #{degenerate}")
  end

  # The three curated replacements hold the setpoints ComStock ran before this data
  # existed: hospital labs on the Hospital Bldg schedules, operating rooms on Hospital
  # Critical, guest rooms on the LargeHotel pair.
  def test_curated_rows_carry_the_prior_comstock_setpoints
    {
      'laboratory' => { htg: 21.1, clg: 22.2, htg_sb: 2.8, clg_sb: 2.8 },
      'operating room' => { htg: 21.1, clg: 22.2, htg_sb: 0.0, clg_sb: 0.0 },
      'guest room' => { htg: 21.0, clg: 24.0, htg_sb: 0.0, clg_sb: 0.0 }
    }.each do |name, expected|
      record = @zone.space_type_thermostat_setpoints(name)
      refute_nil(record, "no setpoint record for #{name}")
      assert_in_delta(expected[:htg], record[:heating_setpoint_c], 0.01, "#{name} heating setpoint")
      assert_in_delta(expected[:clg], record[:cooling_setpoint_c], 0.01, "#{name} cooling setpoint")
      assert_in_delta(expected[:htg_sb], record[:heating_setback_delta_c], 0.01, "#{name} heating setback")
      assert_in_delta(expected[:clg_sb], record[:cooling_setback_delta_c], 0.01, "#{name} cooling setback")
      assert_match(/curated/, record[:source], "#{name} source should record the curation")
    end
  end

  # 'playing area' had no record and no prototype row, so a gym floor named that way was
  # built with no thermostat and ran a validation unconditioned, its people, lights
  # and outdoor air still counted. The curated gym record serves every variant.
  def test_playing_area_resolves_to_the_gym_setpoints
    ['playing area', 'playing area - secondary school', 'playing area - primary school'].each do |name|
      record = @zone.space_type_thermostat_setpoints(name)
      refute_nil(record, "no setpoint record for #{name}")
      assert_in_delta(21.0, record[:heating_setpoint_c], 0.01)
      assert_in_delta(24.0, record[:cooling_setpoint_c], 0.01)
      assert_in_delta(5.0, record[:heating_setback_delta_c], 0.01)
      assert_in_delta(3.0, record[:cooling_setback_delta_c], 0.01)
    end
  end

  # A space type that carries people but resolves to no setpoint record is built
  # unconditioned, silently, since the thermostat pass only logs at info level per zone.
  # Every occupied all-level space type has to resolve, by its own name or its level-1
  # name, unless it is listed here. The list is the set of known gaps, not an acceptance
  # of them: shrink it by adding records, and a new gap fails this test.
  def test_every_occupied_space_type_resolves_to_a_setpoint_record
    lib = File.expand_path('../../../lib/openstudio-standards', __dir__)
    all_level = JSON.parse(File.read("#{lib}/space_type/data/all_level_space_types.json"))
    occupancy = JSON.parse(File.read("#{lib}/occupancy/data/typical_space_type_occupancy.json"))
    occupied = all_level.select do |row|
      (occupancy[row['ventilation_space_type_name']] || []).any? { |r| r['occupancy_per_area'].to_f > 0.0 }
    end
    unresolved = occupied.map { |row| row['space_type_name'] }.reject { |name| @zone.space_type_thermostat_setpoints(name) }

    known_gaps = [
      # nothing in the prototype lookup describes these; none is built by a ComStock spec
      'atrium', 'banking', 'emergency vehicle garage', 'living quarters', 'loading dock',
      'manufacturing', 'medical supply', 'multifamily', 'nursery', 'office/enclosed',
      'pharmacy', 'post office', 'recreation/common living', 'sleeping quarters',
      'sports arena', 'transportation', 'worship'
    ]
    new_gaps = unresolved.reject { |name| known_gaps.include?(name.split(' - ').first) }
    assert_empty(new_gaps, "occupied space types with no thermostat setpoint record: #{new_gaps}")
    closed = known_gaps.reject { |name| unresolved.any? { |u| u.split(' - ').first == name } }
    assert_empty(closed, "known gaps now resolve and can leave the list: #{closed}")
  end

  # The gap is named once, at warning level, with the space types that carry loads.
  def test_unconditioned_loaded_space_types_are_named
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('nowhere')
    space_type.setStandardsSpaceType('not a space type')
    space_type.additionalProperties.setFeature('standards_space_type', 'not a space type')
    people_definition = OpenStudio::Model::PeopleDefinition.new(model)
    people_definition.setPeopleperSpaceFloorArea(0.05)
    OpenStudio::Model::People.new(people_definition).setSpaceType(space_type)
    polygon = OpenStudio::Point3dVector.new
    [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| polygon << OpenStudio::Point3d.new(x, y, 0) }
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    space.setSpaceType(space_type)
    zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(zone)

    sink = OpenStudio::StringStreamLogSink.new
    sink.setLogLevel(OpenStudio::Warn)
    assert(@zone.thermal_zones_set_thermostat_schedules([zone]))
    assert(zone.thermostatSetpointDualSetpoint.empty?, 'a space type with no data should get no thermostat')
    messages = sink.logMessages.map(&:logMessage)
    assert(messages.any? { |m| m.include?('built unconditioned') && m.include?('nowhere') },
           "expected a warning naming the unconditioned space type, got: #{messages}")
  end

  # The data can no longer carry a knife edge, but max-heating/min-cooling across a mixed
  # zone can manufacture one from two healthy records, and a runtime thermostat_override
  # can state one directly. The combiner is the floor under both; heating yields, and the
  # heating setback temperature stays where it was.
  def test_most_restrictive_enforces_minimum_deadband
    manufactured = @zone.most_restrictive_thermostat_setpoints([
      { heating_setpoint_c: 22.2, heating_setback_delta_c: 2.8, cooling_setpoint_c: 25.0, cooling_setback_delta_c: 0.0 },
      { heating_setpoint_c: 20.0, heating_setback_delta_c: 0.0, cooling_setpoint_c: 22.2, cooling_setback_delta_c: 0.0 }
    ])
    assert_in_delta(21.2, manufactured[:heating_setpoint_c], 0.01, 'heating should yield to leave the deadband')
    assert_in_delta(22.2, manufactured[:cooling_setpoint_c], 0.01)
    # the combined setback temperature is 20.0 C, the more restrictive of 19.4 and 20.0;
    # lowering the occupied setpoint shrinks the delta so that temperature stays put
    assert_in_delta(21.2 - 20.0, manufactured[:heating_setback_delta_c], 0.01)

    single = @zone.most_restrictive_thermostat_setpoints([
      { heating_setpoint_c: 22.22, heating_setback_delta_c: 0.0, cooling_setpoint_c: 22.22, cooling_setback_delta_c: 0.0 }
    ])
    assert_in_delta(21.22, single[:heating_setpoint_c], 0.01, 'a knife-edge record from an override is widened too')
    assert_in_delta(0.0, single[:heating_setback_delta_c], 0.01, 'the setback delta cannot go negative')
  end

  def test_most_restrictive_thermostat_setpoints
    records = [
      { heating_setpoint_c: 20.0, heating_setback_delta_c: 5.0, cooling_setpoint_c: 24.0, cooling_setback_delta_c: 4.0 },
      { heating_setpoint_c: 21.0, heating_setback_delta_c: 0.0, cooling_setpoint_c: 25.0, cooling_setback_delta_c: 0.0 }
    ]
    combined = @zone.most_restrictive_thermostat_setpoints(records)
    assert_in_delta(21.0, combined[:heating_setpoint_c], 0.01)
    assert_in_delta(24.0, combined[:cooling_setpoint_c], 0.01)
    # the second record holds 21.0 C around the clock, so there is no setback left to take
    assert_in_delta(0.0, combined[:heating_setback_delta_c], 0.01)
    assert_in_delta(1.0, combined[:cooling_setback_delta_c], 0.01)

    assert_nil(@zone.most_restrictive_thermostat_setpoints([]))
    assert_equal(records[0], @zone.most_restrictive_thermostat_setpoints([records[0]]))
  end

  def test_widest_operating_hours
    hours = [
      { wkdy_start: 8.0, wkdy_end: 18.0, wknd_start: 10.0, wknd_end: 14.0 },
      { wkdy_start: 6.0, wkdy_end: 17.0, wknd_start: 9.0, wknd_end: 16.0 }
    ]
    combined = @zone.widest_operating_hours(hours)
    assert_in_delta(6.0, combined[:wkdy_start], 0.01)
    assert_in_delta(18.0, combined[:wkdy_end], 0.01)
    assert_in_delta(9.0, combined[:wknd_start], 0.01)
    assert_in_delta(16.0, combined[:wknd_end], 0.01)
    assert_nil(@zone.widest_operating_hours([]))
  end

  # A zone holding two space types gets one thermostat built for the tighter of them.
  def test_thermal_zones_set_thermostat_schedules_mixed_zone
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)

    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    thermal_zone.setName('Mixed Zone')
    ['office', 'apartment'].each do |name|
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName(name)
      space_type.setStandardsSpaceType(name)
      space_type.additionalProperties.setFeature('standards_space_type', name)
      space.setSpaceType(space_type)
      space.setThermalZone(thermal_zone)
    end

    assert(@zone.thermal_zones_set_thermostat_schedules([thermal_zone]))
    thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
    assert_equal('Mixed Zone Thermostat', thermostat.name.to_s)

    # apartment heats to 21.7 C and office cools to 23.1 C, so the zone takes the higher
    # heating setpoint from the apartment and the lower cooling setpoint from the office
    heating = @sch.schedule_get_min_max(thermostat.heatingSetpointTemperatureSchedule.get)
    cooling = @sch.schedule_get_min_max(thermostat.coolingSetpointTemperatureSchedule.get)
    assert_in_delta(21.7, heating['max'], 0.01)
    assert_in_delta(23.1, cooling['min'], 0.01)
  end

  def test_thermal_zone_set_unconditioned_thermostat
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(thermal_zone)
    @zone.thermal_zone_set_unconditioned_thermostat(thermal_zone)
    assert(thermal_zone.thermostatSetpointDualSetpoint.is_initialized)
    assert_equal(false, @zone.thermal_zone_heated?(thermal_zone))
    assert_equal(false, @zone.thermal_zone_cooled?(thermal_zone))
  end
end
