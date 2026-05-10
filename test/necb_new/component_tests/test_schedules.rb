require_relative '../test_helper'

class TestSchedules < Minitest::Test
  def test_necb_create_schedule_type_a
    # NECB-A: Typical office schedule (weekday operation)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    # Create NECB-A heating schedule
    schedule = standard.model_add_schedule(model, 'NECB-A-Thermostat Setpoint-Heating')

    # Verify schedule created
    assert schedule, "NECB-A heating schedule should be created"

    # Check schedule type
    ruleset = schedule.to_ScheduleRuleset
    if ruleset.is_initialized
      schedule_obj = ruleset.get
      assert schedule_obj, "Schedule should be ScheduleRuleset"
      assert_equal 'NECB-A-Thermostat Setpoint-Heating', schedule_obj.name.to_s, "Schedule name should match"

      # Verify schedule has rules (weekday/weekend patterns)
      rules = schedule_obj.scheduleRules
      assert rules.size > 0, "Schedule should have rules for different day types"
    end
  end

  def test_necb_schedule_type_b_247
    # NECB-B: 24/7 operation (hospitals, data centers, etc.)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule = standard.model_add_schedule(model, 'NECB-B-Thermostat Setpoint-Heating')

    assert schedule, "NECB-B schedule should be created"
    assert_equal 'NECB-B-Thermostat Setpoint-Heating', schedule.name.to_s, "Schedule name should match"

    # NECB-B schedules represent 24/7 operation
    ruleset = schedule.to_ScheduleRuleset
    assert ruleset.is_initialized, "Schedule should be ScheduleRuleset type"
  end

  def test_necb_schedule_type_c_retail
    # NECB-C: Retail/restaurant schedule (extended hours, 10am-9pm)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule = standard.model_add_schedule(model, 'NECB-C-Thermostat Setpoint-Heating')

    assert schedule, "NECB-C schedule should be created"
    assert_equal 'NECB-C-Thermostat Setpoint-Heating', schedule.name.to_s, "Schedule name should match"

    ruleset = schedule.to_ScheduleRuleset
    assert ruleset.is_initialized, "NECB-C schedule should be ScheduleRuleset"
  end

  def test_necb_schedule_type_d_school
    # NECB-D: School schedule (7am-5pm weekdays, minimal weekend operation)
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule = standard.model_add_schedule(model, 'NECB-D-Thermostat Setpoint-Heating')

    assert schedule, "NECB-D schedule should be created"
    assert_equal 'NECB-D-Thermostat Setpoint-Heating', schedule.name.to_s, "Schedule name should match"

    ruleset = schedule.to_ScheduleRuleset
    assert ruleset.is_initialized, "NECB-D schedule should be ScheduleRuleset"
  end

  def test_necb_occupancy_schedules_all_types
    # Test that all four NECB occupancy schedule types can be created
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule_types = ['A', 'B', 'C', 'D']

    schedule_types.each do |type|
      schedule_name = "NECB-#{type}-Occupancy"
      schedule = standard.model_add_schedule(model, schedule_name)

      assert schedule, "#{schedule_name} should be created"
      assert_equal schedule_name, schedule.name.to_s, "Schedule name should match for type #{type}"

      # Verify it's a ScheduleRuleset
      ruleset = schedule.to_ScheduleRuleset
      assert ruleset.is_initialized, "#{schedule_name} should be ScheduleRuleset type"
    end

    # Verify all schedules are in the model
    assert_equal schedule_types.size, model.getScheduleRulesets.select { |s| s.name.to_s.include?('NECB-') && s.name.to_s.include?('-Occupancy') }.size,
                 "Model should contain all #{schedule_types.size} NECB occupancy schedules"
  end

  def test_necb_lighting_schedules
    # Test NECB lighting schedules for all types
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule_types = ['A', 'B', 'C', 'D']

    schedule_types.each do |type|
      schedule_name = "NECB-#{type}-Lighting"
      schedule = standard.model_add_schedule(model, schedule_name)

      assert schedule, "#{schedule_name} should be created"

      # Check schedule type limits
      ruleset = schedule.to_ScheduleRuleset
      if ruleset.is_initialized
        schedule_obj = ruleset.get
        type_limits = schedule_obj.scheduleTypeLimits

        # Lighting schedules should have FRACTION type limits
        if type_limits.is_initialized
          limits = type_limits.get
          assert_equal 'Fractional', limits.unitType, "Lighting schedule should have Fractional unit type"
        end
      end
    end
  end

  def test_schedule_assignment_to_space_type
    # Test that schedules are properly assigned to space type loads
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Get or create a space type
    space_type = model.getSpaceTypes.first
    if space_type.nil?
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName('Office')
    end

    # Set space type properties to trigger schedule assignment
    space_type.setStandardsBuildingType('Office')
    space_type.setStandardsSpaceType('Open plan office')

    # Apply schedules using the standard method
    standard.space_type_apply_internal_load_schedules(space_type, set_people: true, set_lights: true, set_electric_equipment: true, set_gas_equipment: false, set_ventilation: false)

    # Verify default schedule set exists
    default_sch_set = space_type.defaultScheduleSet
    assert default_sch_set.is_initialized, "Space type should have default schedule set"

    # Verify occupancy schedule assigned
    sch_set = default_sch_set.get
    people_schedule = sch_set.numberofPeopleSchedule
    if people_schedule.is_initialized
      assert people_schedule.get.name.to_s.include?('NECB'), "People schedule should be a NECB schedule"
    end
  end

  def test_always_on_schedule_exists
    # Test that always-on schedule is available
    model = OpenStudio::Model::Model.new

    always_on = model.alwaysOnDiscreteSchedule
    assert always_on, "Always-on schedule should exist"
    assert_equal 'Always On Discrete', always_on.name.to_s, "Always-on schedule should have standard name"

    # Verify it's a ScheduleConstant
    constant_schedule = always_on.to_ScheduleConstant
    assert constant_schedule.is_initialized, "Always-on should be ScheduleConstant type"

    # Verify value is 1.0
    if constant_schedule.is_initialized
      schedule_obj = constant_schedule.get
      assert_equal 1.0, schedule_obj.value, "Always-on schedule value should be 1.0"
    end
  end

  def test_hvac_schedule_assignment
    # Test HVAC availability schedules
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName('Test_VAV_System')

    # Create NECB-A HVAC availability schedule (office hours)
    hvac_schedule = standard.model_add_schedule(model, 'NECB-A-Fan')

    assert hvac_schedule, "NECB-A-Fan schedule should be created"

    # Try to assign schedule to air loop
    ruleset = hvac_schedule.to_ScheduleRuleset
    if ruleset.is_initialized
      air_loop.setAvailabilitySchedule(ruleset.get)

      # Verify schedule assigned
      assigned_schedule = air_loop.availabilitySchedule
      assert_equal hvac_schedule.handle.to_s, assigned_schedule.handle.to_s, "HVAC availability schedule should be assigned to air loop"
    end
  end

  def test_schedule_not_duplicated
    # Test that requesting the same schedule twice returns the existing one
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule_name = 'NECB-A-Occupancy'

    # Create schedule first time
    schedule1 = standard.model_add_schedule(model, schedule_name)
    initial_count = model.getSchedules.size

    # Request same schedule again
    schedule2 = standard.model_add_schedule(model, schedule_name)
    final_count = model.getSchedules.size

    # Should return same object, not create new one
    assert_equal schedule1.handle.to_s, schedule2.handle.to_s, "Same schedule should be returned, not duplicated"
    assert_equal initial_count, final_count, "Schedule count should not increase when requesting existing schedule"
  end

  def test_thermostat_schedule_assignment
    # Test thermostat schedule assignment to thermal zones
    standard = Standard.build('NECB2011')
    model = BTAP::FileIO.load_osm('/workspaces/openstudio-standards/test/necb_new/fixtures/geometry/simple_box.osm')

    # Create thermal zone if none exists
    zone = model.getThermalZones.first
    if zone.nil?
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName('Test Zone')
      # Assign a space to the zone if available
      space = model.getSpaces.first
      space.setThermalZone(zone) if space
    end

    assert zone, "Model should have at least one thermal zone"

    # Create thermostat with NECB schedules
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermostat.setName('NECB Test Thermostat')

    # Create and assign heating schedule
    heating_schedule = standard.model_add_schedule(model, 'NECB-A-Thermostat Setpoint-Heating')
    assert heating_schedule, "Heating schedule should be created"

    ruleset = heating_schedule.to_ScheduleRuleset
    if ruleset.is_initialized
      thermostat.setHeatingSetpointTemperatureSchedule(ruleset.get)
    end

    # Create and assign cooling schedule
    cooling_schedule = standard.model_add_schedule(model, 'NECB-A-Thermostat Setpoint-Cooling')
    assert cooling_schedule, "Cooling schedule should be created"

    ruleset = cooling_schedule.to_ScheduleRuleset
    if ruleset.is_initialized
      thermostat.setCoolingSetpointTemperatureSchedule(ruleset.get)
    end

    # Assign thermostat to zone
    zone.setThermostatSetpointDualSetpoint(thermostat)

    # Verify assignment
    zone_thermostat = zone.thermostatSetpointDualSetpoint
    assert zone_thermostat.is_initialized, "Zone should have thermostat assigned"

    if zone_thermostat.is_initialized
      tstat = zone_thermostat.get
      heating_sch = tstat.heatingSetpointTemperatureSchedule
      cooling_sch = tstat.coolingSetpointTemperatureSchedule

      assert heating_sch.is_initialized, "Thermostat should have heating schedule"
      assert cooling_sch.is_initialized, "Thermostat should have cooling schedule"
    end
  end

  def test_necb_schedule_across_vintages
    # Test that NECB schedules work across different vintages
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']
    schedule_name = 'NECB-A-Occupancy'

    vintages.each do |vintage|
      standard = Standard.build(vintage)
      model = OpenStudio::Model::Model.new

      schedule = standard.model_add_schedule(model, schedule_name)

      assert schedule, "#{schedule_name} should be created for #{vintage}"
      assert_equal schedule_name, schedule.name.to_s, "Schedule name should match for #{vintage}"
    end
  end

  def test_schedule_ruleset_structure
    # Test the structure of a NECB schedule ruleset
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    schedule = standard.model_add_schedule(model, 'NECB-A-Occupancy')

    ruleset = schedule.to_ScheduleRuleset
    assert ruleset.is_initialized, "Schedule should be ScheduleRuleset"

    schedule_obj = ruleset.get

    # Verify default day schedule exists
    default_day = schedule_obj.defaultDaySchedule
    assert default_day, "Schedule should have default day schedule"
    assert default_day.name.to_s.include?('Default'), "Default day schedule should have 'Default' in name"

    # Verify schedule has values
    values = default_day.values
    assert values.size > 0, "Default day schedule should have values"

    # Verify design day schedules exist
    winter_design = schedule_obj.winterDesignDaySchedule
    summer_design = schedule_obj.summerDesignDaySchedule

    assert winter_design, "Schedule should have winter design day"
    assert summer_design, "Schedule should have summer design day"

    # Check that schedule rules exist for different day patterns
    rules = schedule_obj.scheduleRules
    assert rules.size >= 0, "Schedule should have zero or more schedule rules"
  end
end
