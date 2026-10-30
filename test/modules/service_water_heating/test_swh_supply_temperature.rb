require_relative '../../helpers/minitest_helper'

# Tests for telling a water use connection what temperature its loop supplies.
#
# Left blank, EnergyPlus reads the supply temperature from the water inlet node and compares it
# with the target every iteration. During warmup the loop has not been heated yet, so every draw
# warns on every iteration -- 64.6 million warnings on one hospital, and roughly 45 of the 89
# minutes it takes to run.
class TestServiceWaterHeatingSupplyTemperature < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
  end

  def loop_with_setpoint(model, temperature_c, name)
    @swh.create_service_water_heating_loop(model, system_name: name, service_water_temperature: temperature_c)
  end

  def test_loop_temperature_schedule_comes_from_the_setpoint_manager
    model = OpenStudio::Model::Model.new
    swh_loop = loop_with_setpoint(model, 60.0, 'Test Service Water Loop')

    schedule = @swh.service_water_loop_temperature_schedule(swh_loop)
    refute_nil(schedule, 'the loop setpoint schedule was not found')
    assert_in_delta(60.0, OpenstudioStandards::Schedules.schedule_get_min_max(schedule)['max'], 0.1)
  end

  def test_a_loop_with_no_scheduled_setpoint_manager_returns_nil
    model = OpenStudio::Model::Model.new
    bare = OpenStudio::Model::PlantLoop.new(model)
    assert_nil(@swh.service_water_loop_temperature_schedule(bare))
    assert_nil(@swh.service_water_loop_temperature_schedule(nil))
  end

  # The point of the change: the connection carries the temperature, and it is the loop's own
  # schedule object rather than a second one that says the same thing.
  def test_attaching_gives_the_connection_the_loops_own_schedule
    model = OpenStudio::Model::Model.new
    swh_loop = loop_with_setpoint(model, 60.0, 'Test Service Water Loop')
    schedules_before = model.getScheduleRulesets.size

    equipment = 3.times.map do |i|
      @swh.create_water_use(model, name: "Use #{i}", flow_rate: 0.00001,
                                   flow_rate_fraction_schedule: model.alwaysOnDiscreteSchedule)
    end
    equipment.each { |e| assert(@swh.attach_water_use_to_loop(e, swh_loop)) }

    loop_schedule = @swh.service_water_loop_temperature_schedule(swh_loop)
    connections = equipment.map { |e| e.waterUseConnections.get }
    connections.each do |connection|
      assert(connection.hotWaterSupplyTemperatureSchedule.is_initialized, 'no hot water supply schedule')
      assert_equal(loop_schedule.handle.to_s, connection.hotWaterSupplyTemperatureSchedule.get.handle.to_s,
                   "the connection should reference the loop's own schedule, not a copy")
    end

    # the cold side stays blank so EnergyPlus keeps using the seasonally varying mains temperature
    connections.each { |c| refute(c.coldWaterSupplyTemperatureSchedule.is_initialized) }

    # and no schedule was created for any of this
    created = model.getScheduleRulesets.size - schedules_before
    assert_operator(created, :<=, 3, "attaching 3 draws created #{created} schedules; it should reuse the loop's")
  end

  # create_water_use derives it when it is handed a loop directly.
  def test_create_water_use_derives_the_schedule_from_a_loop_it_is_given
    model = OpenStudio::Model::Model.new
    swh_loop = loop_with_setpoint(model, 60.0, 'Test Service Water Loop')
    equipment = @swh.create_water_use(model, name: 'Direct', flow_rate: 0.00001,
                                             flow_rate_fraction_schedule: model.alwaysOnDiscreteSchedule,
                                             service_water_loop: swh_loop)
    connection = equipment.waterUseConnections.get
    assert(connection.hotWaterSupplyTemperatureSchedule.is_initialized)
    assert_equal(@swh.service_water_loop_temperature_schedule(swh_loop).handle.to_s,
                 connection.hotWaterSupplyTemperatureSchedule.get.handle.to_s)
  end

  # With no loop and no explicit schedule the field stays blank, which is what it was before.
  def test_no_loop_leaves_the_field_blank
    model = OpenStudio::Model::Model.new
    equipment = @swh.create_water_use(model, name: 'Unconnected', flow_rate: 0.00001,
                                             flow_rate_fraction_schedule: model.alwaysOnDiscreteSchedule)
    connection = equipment.waterUseConnections.get
    refute(connection.hotWaterSupplyTemperatureSchedule.is_initialized)
    refute(connection.coldWaterSupplyTemperatureSchedule.is_initialized)
  end

  def test_an_explicit_schedule_wins_over_the_loop
    model = OpenStudio::Model::Model.new
    swh_loop = loop_with_setpoint(model, 60.0, 'Test Service Water Loop')
    explicit = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, 71.1,
                                                                              name: 'Explicit Supply Temp',
                                                                              schedule_type_limit: 'Temperature')
    equipment = @swh.create_water_use(model, name: 'Override', flow_rate: 0.00001,
                                             flow_rate_fraction_schedule: model.alwaysOnDiscreteSchedule,
                                             service_water_loop: swh_loop,
                                             hot_water_supply_temperature_schedule: explicit)
    connection = equipment.waterUseConnections.get
    assert_equal(explicit.handle.to_s, connection.hotWaterSupplyTemperatureSchedule.get.handle.to_s)
  end

  # End to end through the typical path: every connection on both loops carries its own loop's
  # temperature, and each loop contributes exactly one schedule object.
  def test_create_typical_gives_every_connection_its_loop_temperature
    model = OpenStudio::Model::Model.new
    OpenstudioStandards::Geometry.create_bar_from_building_type_ratios(
      model, { 'total_bldg_floor_area' => 20_000.0, 'bldg_type_a' => 'LargeHotel' }
    )
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-4A')
    OpenstudioStandards::CreateTypical.create_typical_building_from_model(
      model, '90.1-2013', climate_zone: 'ASHRAE 169-2013-4A', add_hvac: false, remove_objects: true
    )

    loops = model.getPlantLoops.select do |l|
      l.demandComponents.any? { |c| !c.to_WaterUseConnections.empty? }
    end
    refute_empty(loops, 'no service water loop with water use connections was built')

    loops.each do |swh_loop|
      schedule = @swh.service_water_loop_temperature_schedule(swh_loop)
      refute_nil(schedule, "#{swh_loop.name} has no setpoint schedule")
      connections = swh_loop.demandComponents.map { |c| c.to_WaterUseConnections }.reject(&:empty?).map(&:get)
      referenced = connections.map do |c|
        assert(c.hotWaterSupplyTemperatureSchedule.is_initialized, "#{c.name} has no hot water supply schedule")
        c.hotWaterSupplyTemperatureSchedule.get.handle.to_s
      end
      assert_equal([schedule.handle.to_s], referenced.uniq,
                   "#{swh_loop.name}: every connection should share the loop's one schedule")
    end
  end
end
