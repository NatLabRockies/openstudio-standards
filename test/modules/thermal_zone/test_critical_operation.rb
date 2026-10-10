require_relative '../../helpers/minitest_helper'

# Space types whose systems run regardless of occupancy. An operation schedule derived from
# an occupancy fraction says when a system may shut down; a patient floor may not, and its
# fraction sits close to any threshold, so the derived schedule flips with changes elsewhere
# on the loop - a cafeteria joining a hospital model's patient floor loop cost that floor
# fourteen hours a day of HVAC and outdoor air. The flag lives in the space type data, is
# stamped on the space type, and can be set or cleared by a thermostat_overrides entry.
class TestThermalZoneCriticalOperation < Minitest::Test
  def setup
    @zone = OpenstudioStandards::ThermalZone
    @space_type = OpenstudioStandards::SpaceType
    @create = OpenstudioStandards::CreateTypical
    @lib = File.expand_path('../../../lib/openstudio-standards', __dir__)
  end

  # a zoned space with a typical space type, people on a daytime schedule
  def zoned_space_type(model, standards_name, occupancy_schedule)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(standards_name)
    space_type.setStandardsSpaceType(standards_name)
    space_type.additionalProperties.setFeature('standards_space_type', standards_name)
    people_definition = OpenStudio::Model::PeopleDefinition.new(model)
    people_definition.setPeopleperSpaceFloorArea(0.05)
    people = OpenStudio::Model::People.new(people_definition)
    people.setSpaceType(space_type)
    people.setNumberofPeopleSchedule(occupancy_schedule)
    polygon = OpenStudio::Point3dVector.new
    [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| polygon << OpenStudio::Point3d.new(x, y, 0) }
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    space.setSpaceType(space_type)
    zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(zone)
    [space_type, zone]
  end

  def daytime_schedule(model)
    OpenstudioStandards::Schedules.create_simple_schedule(model, 'name' => 'daytime',
                                                                 'default_time_value_pairs' => { 8.0 => 0.0, 17.0 => 1.0, 24.0 => 0.0 })
  end

  def test_data_flags_the_critical_space_types_and_their_variants
    rows = JSON.parse(File.read("#{@lib}/space_type/data/all_level_space_types.json"))
    flagged = rows.select { |row| row['critical_operation'] == true }.map { |row| row['space_type_name'] }
    %w[patient\ room operating\ room recovery emergency\ room nurses\ station datacenter/high\ ite datacenter/low\ ite].each do |name|
      assert_includes(flagged, name)
    end
    rows.each do |row|
      base = row['space_type_name'].split(' - ').first
      assert_equal(flagged.include?(base), row['critical_operation'] == true, "#{row['space_type_name']} should inherit its base name's flag")
    end
    refute_includes(flagged, 'office')
    refute_includes(flagged, 'dining')
  end

  def test_space_type_reads_the_flag_from_data_then_from_its_property
    model = OpenStudio::Model::Model.new
    patient, = zoned_space_type(model, 'patient room', daytime_schedule(model))
    office, = zoned_space_type(model, 'office', daytime_schedule(model))
    assert(@space_type.space_type_critical_operation?(patient))
    refute(@space_type.space_type_critical_operation?(office))

    # set_standards_space_type_additional_properties stamps the data value
    @space_type.set_standards_space_type_additional_properties(model, space_type_field: 'AdditionalProperties')
    assert(patient.additionalProperties.getFeatureAsBoolean('critical_operation').get)
    refute(office.additionalProperties.getFeatureAsBoolean('critical_operation').get)

    # the property wins over the data once stamped
    patient.additionalProperties.setFeature('critical_operation', false)
    refute(@space_type.space_type_critical_operation?(patient))
  end

  def test_zones_serving_a_critical_space_type_get_an_always_on_operation_schedule
    model = OpenStudio::Model::Model.new
    model.getYearDescription.setCalendarYear(2018)
    _, patient_zone = zoned_space_type(model, 'patient room', daytime_schedule(model))
    _, office_zone = zoned_space_type(model, 'office', daytime_schedule(model))

    office_only = @zone.thermal_zones_get_occupancy_schedule([office_zone], sch_name: 'office loop', occupied_percentage_threshold: 0.15)
    assert_includes(office_only.defaultDaySchedule.values, 0.0, 'an office loop follows occupancy')

    with_patient = @zone.thermal_zones_get_occupancy_schedule([office_zone, patient_zone], sch_name: 'mixed loop', occupied_percentage_threshold: 0.15)
    assert_equal([1.0], with_patient.defaultDaySchedule.values, 'a loop serving a patient room runs continuously')
    assert_equal('mixed loop', with_patient.name.to_s)
    assert(with_patient.scheduleTypeLimits.is_initialized, 'the always-on schedule carries type limits')

    single = @zone.thermal_zone_get_occupancy_schedule(patient_zone, occupied_percentage_threshold: 0.15)
    assert_equal([1.0], single.defaultDaySchedule.values)

    # only the thresholded form is an operation schedule; the fractional profile is a load
    fractional = @zone.thermal_zones_get_occupancy_schedule([patient_zone], sch_name: 'patient fraction')
    assert_includes(fractional.defaultDaySchedule.values, 0.0)
  end

  def test_continuous_operation_override_sets_and_clears_the_flag
    model = OpenStudio::Model::Model.new
    model.getYearDescription.setCalendarYear(2018)
    dining, dining_zone = zoned_space_type(model, 'dining', daytime_schedule(model))
    patient, patient_zone = zoned_space_type(model, 'patient room', daytime_schedule(model))
    @space_type.set_standards_space_type_additional_properties(model, space_type_field: 'AdditionalProperties')

    overrides = @create.parse_overrides_argument(
      [{ 'space_type' => 'dining', 'thermostat' => { 'continuous_operation' => true } },
       { 'space_type' => 'patient room', 'thermostat' => { 'continuous_operation' => false, 'cooling_setpoint_c' => 23.0 } }],
      'thermostat_overrides'
    )
    assert_equal(2, @create.model_apply_operation_overrides(model, overrides))
    assert(@space_type.space_type_critical_operation?(dining), 'the override should hold dining continuous')
    refute(@space_type.space_type_critical_operation?(patient), 'the override should release the patient room')

    dining_loop = @zone.thermal_zones_get_occupancy_schedule([dining_zone], sch_name: 'dining loop', occupied_percentage_threshold: 0.15)
    assert_equal([1.0], dining_loop.defaultDaySchedule.values)
    patient_loop = @zone.thermal_zones_get_occupancy_schedule([patient_zone], sch_name: 'patient loop', occupied_percentage_threshold: 0.15)
    assert_includes(patient_loop.defaultDaySchedule.values, 0.0)

    # the setpoint side of the same entry still applies, and an operation-only entry
    # leaves the setpoints alone
    setpoints = @zone.space_type_thermostat_setpoints_with_overrides(patient, 'patient room', overrides)
    assert_in_delta(23.0, setpoints[:cooling_setpoint_c], 0.01)
    stock = @zone.space_type_thermostat_setpoints('dining')
    dining_setpoints = @zone.space_type_thermostat_setpoints_with_overrides(dining, 'dining', overrides)
    assert_in_delta(stock[:cooling_setpoint_c], dining_setpoints[:cooling_setpoint_c], 0.01)

    # an operation-only entry for a space type with no setpoint data is not a setpoint
    # override, so it must not be reported as one that sets no setpoints
    sink = OpenStudio::StringStreamLogSink.new
    sink.setLogLevel(OpenStudio::Warn)
    invented = OpenStudio::Model::SpaceType.new(model)
    invented.setName('not a space type')
    only = @create.parse_overrides_argument([{ 'space_type' => 'not a space type', 'thermostat' => { 'continuous_operation' => true } }], 'thermostat_overrides')
    assert_nil(@zone.space_type_thermostat_setpoints_with_overrides(invented, 'not a space type', only))
    assert_empty(sink.logMessages.map(&:logMessage).select { |m| m.include?('sets no setpoints') })
  end

  def test_spec_accepts_a_continuous_operation_entry
    spec = {
      template: '90.1-2013',
      climate_zone: 'ASHRAE 169-2013-4A',
      primary_building_type: 'Hospital',
      space_type_ratios: [{ space_type: 'patient room', ratio: 0.6 }, { space_type: 'dining', ratio: 0.4 }],
      thermostat_overrides: [
        { space_type: 'dining', thermostat: { continuous_operation: true } },
        { space_type: 'patient room', thermostat: { continuous_operation: false, cooling_setpoint_c: 23.0 } }
      ]
    }
    assert_empty(@create.validate_custom_building_spec(spec))

    not_boolean = spec.merge(thermostat_overrides: [{ space_type: 'dining', thermostat: { continuous_operation: 'yes' } }])
    refute_empty(@create.validate_custom_building_spec(not_boolean))
  end
end
