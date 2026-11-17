require_relative '../../helpers/minitest_helper'

# Space types whose systems run regardless of occupancy. An operation schedule derived from
# an occupancy fraction says when a system may shut down; a patient floor may not, and its
# fraction sits close to any threshold, so the derived schedule flips with changes elsewhere
# on the loop - a cafeteria joining a hospital model's patient floor loop cost that floor
# fourteen hours a day of HVAC and outdoor air. The flag lives in the space type data and
# is stamped on the space type.
class TestThermalZoneCriticalOperation < Minitest::Test
  def setup
    @zone = OpenstudioStandards::ThermalZone
    @space_type = OpenstudioStandards::SpaceType
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
    rows = JSON.parse(File.read("#{@lib}/space_type/data/space_types.json"))
    flagged = rows.select { |row| row['critical_operation'] == true }.map { |row| row['space_type_name'] }
    ['patient room', 'operating room', 'recovery', 'emergency room', 'nurses station', 'datacenter/high ite', 'datacenter/low ite'].each do |name|
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
end
