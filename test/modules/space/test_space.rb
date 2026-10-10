require_relative '../../helpers/minitest_helper'

class TestSpace < Minitest::Test
  def setup
    @space = OpenstudioStandards::Space
    @sch = OpenstudioStandards::Schedules
  end

  def test_space_plenum?
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.new(model)
    space.setName('some space')
    space.setPartofTotalFloorArea(false)
    assert_equal(true, @space.space_plenum?(space))

    space.setPartofTotalFloorArea(true)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('Plenum')
    space.setSpaceType(space_type)
    assert_equal(true, @space.space_plenum?(space))
  end

  def test_space_residential?
    model = OpenStudio::Model::Model.new
    # from plenum
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space1 = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get

    # from space type
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('MidriseApartment Apartment')
    space1.setSpaceType(space_type)
    assert_equal(true, @space.space_residential?(space1))

    apt_ofc = OpenStudio::Model::SpaceType.new(model)
    apt_ofc.setName('MidriseApartment Office')
    ofc = OpenStudio::Model::Space.new(model)
    ofc.setSpaceType(apt_ofc)
    assert_equal(false, @space.space_residential?(ofc))

    # plenum from below space
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 3.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space2 = OpenStudio::Model::Space.fromFloorPrint(polygon, 1.0, model).get
    space2.setPartofTotalFloorArea(false)
    space1.matchSurfaces(space2)
    assert_equal(true, @space.space_residential?(space2))
  end

  def test_space_heated?
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space1 = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space1.setThermalZone(thermal_zone)
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermal_zone.setThermostatSetpointDualSetpoint(thermostat)
    htg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 20.0,
                                                         name: 'Heating Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    clg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 24.0,
                                                         name: 'Cooling Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
    thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
    assert_equal(true, @space.space_heated?(space1))

    # test unconditioned (<41F)
    htg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 4.0,
                                                         name: 'Unconditioned Heating Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
    assert_equal(false, @space.space_heated?(space1))
  end

  def test_space_cooled?
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space1 = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    thermal_zone = OpenStudio::Model::ThermalZone.new(model)
    space1.setThermalZone(thermal_zone)
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermal_zone.setThermostatSetpointDualSetpoint(thermostat)
    htg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 20.0,
                                                         name: 'Heating Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    clg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 24.0,
                                                         name: 'Cooling Setpoint Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
    thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
    assert_equal(true, @space.space_cooled?(space1))

    # test unconditioned (>91F)
    clg_stpt_sch = @sch.create_constant_schedule_ruleset(model, 35.0,
                                                         name: 'Unconditioned Cooling Schedule',
                                                         schedule_type_limit: 'Temperature')
    thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
    assert_equal(false, @space.space_cooled?(space1))
  end

  def test_space_get_design_internal_load
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space1 = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    assert_equal(0.0, @space.space_get_design_internal_load(space1))

    # create space type and set standards info
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('PrimarySchool')
    space_type.setStandardsSpaceType('Classroom')
    space1.setSpaceType(space_type)

    # add loads
    std = Standard.build('90.1-2013')
    std.model_add_loads(model)
    assert_in_delta(708.67, @space.space_get_design_internal_load(space1), 0.1)
  end

  def test_space_hours_of_operation
    model = OpenStudio::Model::Model.new
    model.getYearDescription.setCalendarYear(2018)
    space = OpenStudio::Model::Space.new(model)
    wkdy_start_time = OpenStudio::Time.new(0,8,0,0)
    wkdy_end_time = OpenStudio::Time.new(0,20,0,0)
    wknd_start_time = OpenStudio::Time.new(0,10,0,0)
    wknd_end_time = OpenStudio::Time.new(0,14,0,0)
    hours_of_operation_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
    wknd_rule = OpenStudio::Model::ScheduleRule.new(hours_of_operation_schedule)
    wknd_rule.setApplyWeekends(true)
    @sch.schedule_ruleset_set_hours_of_operation(hours_of_operation_schedule,
                                                 wkdy_start_time: wkdy_start_time,
                                                 wkdy_end_time: wkdy_end_time,
                                                 sat_start_time: wknd_start_time,
                                                 sat_end_time: wknd_end_time,
                                                 sun_start_time: wknd_start_time,
                                                 sun_end_time: wknd_end_time)
    default_schedule_set = OpenStudio::Model::DefaultScheduleSet.new(model)
    default_schedule_set.setHoursofOperationSchedule(hours_of_operation_schedule)
    space.setDefaultScheduleSet(default_schedule_set)
    hoo_hash = @space.space_hours_of_operation(space)
    # puts hoo_hash
    assert_equal(8, hoo_hash[-1][:hoo_start])
    assert_equal(20, hoo_hash[-1][:hoo_end])
    assert_equal(20-8, hoo_hash[-1][:hoo_hours])
    assert_equal(261, hoo_hash[-1][:days_used].size)
    assert_equal(10, hoo_hash[0][:hoo_start])
    assert_equal(14, hoo_hash[0][:hoo_end])
    assert_equal(14-10, hoo_hash[0][:hoo_hours])
    assert_equal(104, hoo_hash[0][:days_used].size)
  end

  def test_spaces_get_occupancy_schedule
    OpenStudio::Logger.instance.standardOutLogger.setLogLevel(OpenStudio::Error)
    model = OpenStudio::Model::Model.new
    model.getYearDescription.setCalendarYear(2018)

    space1 = OpenStudio::Model::Space.new(model)

    # people at space type
    sch1_opts = {
      'name' => 'People Schedule 1',
      'default_time_value_pairs' => { 8.0 => 0, 16.0 => 1.0, 24.0 => 0}
    }
    ppl_sch1 = @sch.create_simple_schedule(model, sch1_opts)
    default_schedule_set = OpenStudio::Model::DefaultScheduleSet.new(model)
    default_schedule_set.setNumberofPeopleSchedule(ppl_sch1)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setDefaultScheduleSet(default_schedule_set)
    ppl_def1 = OpenStudio::Model::PeopleDefinition.new(model)
    ppl_def1.setNumberofPeople(10)
    ppl1 = OpenStudio::Model::People.new(ppl_def1)
    ppl1.setSpaceType(space_type)
    space1.setSpaceType(space_type)

    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 5.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space2 = OpenStudio::Model::Space.fromFloorPrint(polygon, 1.0, model).get

    # people at space
    sch2_opts = {
      'name' => 'People Schedule 2',
      'default_day' => ['default', [6.0, 0.2], [12.0, 0.4], [18.0, 0.8], [22.0, 0.2]],
      'rules' => [['weekends', '1/1-12/31', 'Sat/Sun',  [24.0, 0]]]
    }
    ppl_sch2 = @sch.create_complex_schedule(model, sch2_opts)
    ppl_def2 = OpenStudio::Model::PeopleDefinition.new(model)
    ppl_def2.setPeopleperSpaceFloorArea(1.0)
    ppl2 = OpenStudio::Model::People.new(ppl_def2)
    ppl2.setNumberofPeopleSchedule(ppl_sch2)
    ppl2.setSpace(space2)

    # people at space
    sch3_opts = {
      'name' => 'People Schedule 3',
      'default_day' => ['default', [24.0, 0]],
      'rules' => [['summer', '6/1-8/31', 'Mon/Tue/Wed/Thu/Fri',  [10.0, 0], [16.0, 1.0], [20.0, 0.3], [24.0, 0]]]
    }
    ppl_sch3 = @sch.create_complex_schedule(model, sch3_opts)
    # puts OpenStudio::Model.getRecursiveChildren(ppl_sch3)
    ppl_def3 = OpenStudio::Model::PeopleDefinition.new(model)
    ppl_def3.setNumberofPeople(5.0)
    ppl3 = OpenStudio::Model::People.new(ppl_def3)
    ppl3.setNumberofPeopleSchedule(ppl_sch3)
    ppl3.setSpace(space2)

    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 10.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space3 = OpenStudio::Model::Space.fromFloorPrint(polygon, 1.0, model).get

    # space with no people
    zero_schedule = @space.spaces_get_occupancy_schedule([space3], sch_name: 'test empty occupancy frac')
    zero_min_max = @sch.schedule_get_min_max(zero_schedule)
    assert_equal(0.0, zero_min_max['min'])
    assert_equal(0.0, zero_min_max['max'])

    # fractional values
    occ_sch_fracs = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy frac', occupied_percentage_threshold: nil, threshold_calc_method: nil)
    # puts "Fractional Values: #{occ_sch_fracs.scheduleRules.size} Schedule Rules"

    spring_wkdy = occ_sch_fracs.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first
    spring_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wkdy)
    assert_equal(6, spring_wkdy_hrly_vals.index(0.25))
    assert_equal(8, spring_wkdy_hrly_vals.index(0.5))
    assert_equal(17, spring_wkdy_hrly_vals.rindex(0.5))
    assert_equal(12, spring_wkdy_hrly_vals.index(0.75))
    assert_equal(15, spring_wkdy_hrly_vals.rindex(0.75))
    assert_equal(21, spring_wkdy_hrly_vals.rindex(0.125))

    spring_wknd = occ_sch_fracs.getDaySchedules(OpenStudio::Date.new('2018-Apr-14'),OpenStudio::Date.new('2018-Apr-14')).first
    spring_wknd_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wknd)
    assert_equal(8, spring_wknd_hrly_vals.index(0.25))
    assert_equal(15, spring_wknd_hrly_vals.rindex(0.25))

    summer_wkdy = occ_sch_fracs.getDaySchedules(OpenStudio::Date.new('2018-Jul-23'),OpenStudio::Date.new('2018-Jul-23')).first
    summer_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(summer_wkdy)
    assert_equal(6, summer_wkdy_hrly_vals.index(0.25))
    assert_equal(8, summer_wkdy_hrly_vals.index(0.5))
    assert_equal(11, summer_wkdy_hrly_vals.rindex(0.625))
    assert_equal(12, summer_wkdy_hrly_vals.index(0.875))
    assert_equal(15, summer_wkdy_hrly_vals.rindex(0.875))
    assert_equal(17, summer_wkdy_hrly_vals.rindex(0.5375))
    assert_equal(19, summer_wkdy_hrly_vals.rindex(0.1625))

    assert_in_delta(@sch.schedule_ruleset_get_equivalent_full_load_hours(occ_sch_fracs), 2290.15, 0.01)

    # A fraction within the tolerance below its threshold counts as occupied: the hourly
    # fractions here are exactly 0.25 and 0.5, so a threshold of 0.253 sits on the edge.
    # An exact comparison would turn the 0.25 hours off; the default tolerance keeps them.
    on_edge = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy edge', occupied_percentage_threshold: 0.253, threshold_calc_method: nil)
    edge_vals = @sch.schedule_day_get_hourly_values(on_edge.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first)
    assert_equal(6, edge_vals.index(1.0), 'the 0.25 hours should count as occupied against 0.253')
    exact = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy exact', occupied_percentage_threshold: 0.253, threshold_calc_method: nil, threshold_tolerance: 0.0)
    exact_vals = @sch.schedule_day_get_hourly_values(exact.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first)
    assert_equal(8, exact_vals.index(1.0), 'with no tolerance the 0.25 hours are unoccupied')
    beyond = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy beyond', occupied_percentage_threshold: 0.26, threshold_calc_method: nil)
    beyond_vals = @sch.schedule_day_get_hourly_values(beyond.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first)
    assert_equal(8, beyond_vals.index(1.0), 'a fraction more than the tolerance below the threshold is unoccupied')

    # not normalized
    occ_sch_values = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy threshold', occupied_percentage_threshold: 0.3, threshold_calc_method: nil)
    # puts "Un-normalized: #{occ_sch_values.scheduleRules.size} Schedule Rules"

    spring_wkdy = occ_sch_values.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first
    spring_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wkdy)
    assert_equal(8, spring_wkdy_hrly_vals.index(1.0))
    assert_equal(17, spring_wkdy_hrly_vals.rindex(1.0))

    spring_wknd = occ_sch_values.getDaySchedules(OpenStudio::Date.new('2018-Apr-14'),OpenStudio::Date.new('2018-Apr-14')).first
    spring_wknd_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wknd)
    assert_nil(spring_wknd_hrly_vals.index(1.0))

    summer_wkdy = occ_sch_values.getDaySchedules(OpenStudio::Date.new('2018-Jul-23'),OpenStudio::Date.new('2018-Jul-23')).first
    summer_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(summer_wkdy)
    assert_equal(8, summer_wkdy_hrly_vals.index(1.0))
    assert_equal(17, summer_wkdy_hrly_vals.rindex(1.0))

    assert_equal(2610, @sch.schedule_ruleset_get_equivalent_full_load_hours(occ_sch_values))

    # normalized daily
    occ_sch_daily = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy daily', occupied_percentage_threshold: 0.3, threshold_calc_method: 'normalized_daily_range')
    # puts "Normalized Daily: #{occ_sch_daily.scheduleRules.size} Schedule Rules"

    spring_wkdy = occ_sch_daily.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first
    spring_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wkdy)
    assert_equal(6, spring_wkdy_hrly_vals.index(1.0))
    assert_equal(17, spring_wkdy_hrly_vals.rindex(1.0))

    spring_wknd = occ_sch_daily.getDaySchedules(OpenStudio::Date.new('2018-Apr-14'),OpenStudio::Date.new('2018-Apr-14')).first
    spring_wknd_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wknd)
    assert_equal(8, spring_wknd_hrly_vals.index(1.0))
    assert_equal(15, spring_wknd_hrly_vals.rindex(1.0))

    summer_wkdy = occ_sch_daily.getDaySchedules(OpenStudio::Date.new('2018-Jul-23'),OpenStudio::Date.new('2018-Jul-23')).first
    summer_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(summer_wkdy)
    assert_equal(8, summer_wkdy_hrly_vals.index(1.0))
    assert_equal(17, summer_wkdy_hrly_vals.rindex(1.0))

    assert_equal(3832, @sch.schedule_ruleset_get_equivalent_full_load_hours(occ_sch_daily))

    # normalized annually
    occ_sch_annual = @space.spaces_get_occupancy_schedule([space1,space2], sch_name: 'test occupancy annual', occupied_percentage_threshold: 0.3, threshold_calc_method: 'normalized_annual_range')
    # puts "Normalized Annually: #{occ_sch_annual.scheduleRules.size} Schedule Rules"

    spring_wkdy = occ_sch_annual.getDaySchedules(OpenStudio::Date.new('2018-Apr-10'),OpenStudio::Date.new('2018-Apr-10')).first
    spring_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wkdy)
    assert_equal(8, spring_wkdy_hrly_vals.index(1.0))
    assert_equal(17, spring_wkdy_hrly_vals.rindex(1.0))

    spring_wknd = occ_sch_annual.getDaySchedules(OpenStudio::Date.new('2018-Apr-14'),OpenStudio::Date.new('2018-Apr-14')).first
    spring_wknd_hrly_vals = @sch.schedule_day_get_hourly_values(spring_wknd)
    assert_nil(spring_wknd_hrly_vals.index(1.0))

    summer_wkdy = occ_sch_annual.getDaySchedules(OpenStudio::Date.new('2018-Jul-23'),OpenStudio::Date.new('2018-Jul-23')).first
    summer_wkdy_hrly_vals = @sch.schedule_day_get_hourly_values(summer_wkdy)
    assert_equal(8, summer_wkdy_hrly_vals.index(1.0))
    assert_equal(17, summer_wkdy_hrly_vals.rindex(1.0))

    assert_equal(2610, @sch.schedule_ruleset_get_equivalent_full_load_hours(occ_sch_annual))

    # test for equivalency with 90.1 PRM method
    model.getYearDescription.setCalendarYear(2006)
    sch4_opts = {
      'name' => 'OfficeMedium BLDG_OCC_SCH',
      'default_day' => ['Default', [6.0, 0],[18.0, 0.05], [24.0, 0.0]],
      'rules' => [
        ['Saturday', '1/1-12/31', 'Sat', [6, 0],[8, 0.1],[12,0.3], [17,0.1],[19,0.05],[24,0]],
        ['Weekdays', '1/1-12/31', 'Mon/Tue/Wed/Thu/Fri', [6,0],[7,0.1],[8,0.2],[12,0.95],[13,0.5],[17,0.95],[18,0.3],[22,0.1],[24,0.05]]
      ]
    }

    ppl_sch4 = @sch.create_complex_schedule(model, sch4_opts)
    space4 = OpenStudio::Model::Space.new(model)
    # need a spacetype to compare to PRM
    st = OpenStudio::Model::SpaceType.new(model)
    space4.setSpaceType(st)
    ppl_def4 = OpenStudio::Model::PeopleDefinition.new(model)
    ppl_def4.setNumberofPeople(21.15)
    ppl4 = OpenStudio::Model::People.new(ppl_def4)
    ppl4.setNumberofPeopleSchedule(ppl_sch4)
    ppl4.setSpace(space4)
    occ_sch = @space.spaces_get_occupancy_schedule([space4], sch_name: 'test occupancy frac', occupied_percentage_threshold: 0.1, threshold_calc_method: nil)

    std = Standard.build('90.1-PRM-2019')
    zone = OpenStudio::Model::ThermalZone.new(model)
    zone.setName('Perimeter_bot_ZN_1 ZN')
    space4.setThermalZone(zone)

    prm_eflh = std.thermal_zone_get_annual_operating_hours(model, zone, nil)

    oss_eflh = @sch.schedule_get_hourly_values(occ_sch)

    assert((prm_eflh.sum - oss_eflh.sum).abs.round(2) <= 0.001)

  end
end
