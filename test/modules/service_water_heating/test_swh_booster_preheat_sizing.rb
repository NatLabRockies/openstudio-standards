require_relative '../../helpers/minitest_helper'

# The shared water heater has to be sized for the booster's draws as well as its own.
#
# create_booster_water_heating_loop puts the booster's heat exchanger on the SHARED loop's
# demand side, so the shared heater preheats every gallon the booster delivers from mains to
# 140 F and the booster adds only the last 40 F. Sizing the shared heater on
# shared_water_use_equipment alone left that preheat unaccounted for. Measured on a
# full service restaurant whose 180 F kitchen draw is 1.5x its 120 F draw: the shared heater
# came out 2.5x too small, both heaters sat at part load ratio 1.0 for all 8,760 hours, and
# neither loop reached setpoint at any timestep -- the shared loop ran at a 31 C mean against
# its 60 C setpoint. That starved the booster too, which had been sized for a 140 F feed it
# never received.
class TestServiceWaterHeatingBoosterPreheatSizing < Minitest::Test
  # how far above the fixture target create_typical runs the booster loop, matching the
  # water heater's deadband so the tank's cycling minimum still delivers the target
  BOOSTER_SETPOINT_OFFSET_K = 2.0

  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
    @std = Standard.build('90.1-2010')
    FileUtils.mkdir_p "#{__dir__}/output"
  end

  # A model whose kitchen produces both a booster (180 F) draw and ordinary shared draws.
  def secondary_school_model
    model = Standard.build('DOE Ref 1980-2004')
                    .safe_load_model("#{__dir__}/../../doe_prototype/models/SecondarySchool_6A_1980-2004.osm")
    model.getPlantLoops.each { |loop| loop.remove unless loop.name.to_s == 'Hot Water Loop' }
    model
  end

  def water_heater_on(loop)
    loop.supplyComponents.map { |c| c.to_WaterHeaterMixed }.reject(&:empty?).map(&:get).first
  end

  # Sum the draws on a loop the way the sizing formula does: nameplate peak flow scaled by
  # the peak value its flow fraction schedule actually reaches.
  def diversified_gph_on(loop)
    loop.demandComponents.map { |c| c.to_WaterUseConnections }.reject(&:empty?).map(&:get).sum do |connection|
      connection.waterUseEquipment.sum do |equip|
        schedule = equip.flowRateFractionSchedule
        next 0.0 if schedule.empty?

        peak = OpenstudioStandards::Schedules.schedule_get_min_max(schedule.get)['max']
        OpenStudio.convert(peak * equip.waterUseEquipmentDefinition.peakFlowRate, 'm^3/s', 'gal/hr').get
      end
    end
  end

  # The regression itself: the shared heater covers the booster's preheat.
  def test_shared_heater_is_sized_for_the_booster_preheat
    model = secondary_school_model
    @swh.create_typical_service_water_heating(model)

    shared_loop = model.getPlantLoopByName('Shared Service Water Loop')
    booster_loop = model.getPlantLoopByName('Booster Service Water Loop')
    refute(shared_loop.empty?, 'no shared service water loop was built')
    refute(booster_loop.empty?, 'no booster service water loop was built')
    shared_loop = shared_loop.get
    booster_loop = booster_loop.get

    shared_gph = diversified_gph_on(shared_loop)
    booster_gph = diversified_gph_on(booster_loop)
    assert_operator(booster_gph, :>, 0.0, 'the booster loop carries no draws, so this proves nothing')

    # Every gallon on both loops takes the mains-to-140 F rise on the shared heater.
    # 8.4 lb/gal * 1 Btu/lb-F * (140 - 40) F / 0.8 efficiency, matching the sizing formula.
    expected_btu_per_hr = (shared_gph + booster_gph) * 8.4 * 1.0 * (140.0 - 40.0) / 0.8
    actual_w = water_heater_on(shared_loop).heaterMaximumCapacity.get
    actual_btu_per_hr = OpenStudio.convert(actual_w, 'W', 'Btu/hr').get

    assert_in_epsilon(expected_btu_per_hr, actual_btu_per_hr, 0.02,
                      'the shared heater is not sized for the shared plus booster draws')

    # and the shortfall it replaces: sizing on the shared draws alone is materially smaller,
    # so this test would have caught the bug rather than passing either way
    shared_only_btu_per_hr = shared_gph * 8.4 * 1.0 * (140.0 - 40.0) / 0.8
    assert_operator(actual_btu_per_hr, :>, shared_only_btu_per_hr * 1.05,
                    'shared-only and shared-plus-booster sizing are indistinguishable on this model')
  end

  # The booster is sized over the lift it actually performs: from the 140 F the shared loop
  # preheats to, up to its own setpoint, which sits a deadband above the 180 F its fixtures
  # target so the tank's cycling minimum still delivers 180 F.
  def test_booster_heater_sized_over_the_lift_it_performs
    model = secondary_school_model
    @swh.create_typical_service_water_heating(model)

    booster_loop = model.getPlantLoopByName('Booster Service Water Loop').get
    booster_gph = diversified_gph_on(booster_loop)
    setpoint_f = OpenStudio.convert(180.0, 'F', 'C').get + BOOSTER_SETPOINT_OFFSET_K
    setpoint_f = OpenStudio.convert(setpoint_f, 'C', 'F').get

    expected_btu_per_hr = booster_gph * 8.4 * 1.0 * (setpoint_f - 140.0) / 1.0
    actual_btu_per_hr = OpenStudio.convert(water_heater_on(booster_loop).heaterMaximumCapacity.get, 'W', 'Btu/hr').get

    assert_in_epsilon(expected_btu_per_hr, actual_btu_per_hr, 0.02,
                      'the booster heater is not sized over its 140 F to setpoint lift')
  end

  # The offset itself: the loop runs above what the fixtures ask for, and the tank's
  # Maximum Temperature Limit is raised with it -- left at the old setpoint it would clamp
  # the tank and the offset would do nothing.
  def test_booster_loop_runs_a_deadband_above_the_fixture_target
    model = secondary_school_model
    @swh.create_typical_service_water_heating(model)

    booster_loop = model.getPlantLoopByName('Booster Service Water Loop').get
    tank = water_heater_on(booster_loop)
    fixture_target_c = OpenStudio.convert(180.0, 'F', 'C').get
    expected_setpoint_c = fixture_target_c + BOOSTER_SETPOINT_OFFSET_K

    setpoint = tank.setpointTemperatureSchedule
    refute(setpoint.empty?, 'the booster tank has no setpoint schedule')
    actual_c = OpenstudioStandards::Schedules.schedule_get_min_max(setpoint.get)['max']
    assert_in_delta(expected_setpoint_c, actual_c, 0.1,
                    'the booster tank setpoint is not a deadband above the fixture target')

    assert_operator(tank.deadbandTemperatureDifference, :<=, BOOSTER_SETPOINT_OFFSET_K + 0.01,
                    'the offset no longer covers the deadband, so the cycling minimum falls short again')
    assert_operator(tank.maximumTemperatureLimit.get, :>=, expected_setpoint_c - 0.01,
                    'the tank maximum temperature limit clamps below its own setpoint')

    # the fixtures still ask for 180 F -- the offset is on the loop, not on the requirement
    targets = booster_loop.demandComponents.map { |c| c.to_WaterUseConnections }.reject(&:empty?).map(&:get)
                          .flat_map(&:waterUseEquipment)
                          .map { |e| e.waterUseEquipmentDefinition.targetTemperatureSchedule }
                          .reject(&:empty?).map { |s| OpenstudioStandards::Schedules.schedule_get_min_max(s.get)['max'] }
    refute_empty(targets, 'no booster fixture target temperatures found')
    targets.each do |target_c|
      assert_in_delta(fixture_target_c, target_c, 0.1, 'a booster fixture target moved; only the loop should have')
    end
  end

  # Opting out restores the previous behavior, for a caller who wants the loop at the
  # fixture temperature.
  def test_zero_offset_runs_the_loop_at_the_fixture_temperature
    model = OpenStudio::Model::Model.new
    shared = @swh.create_service_water_heating_loop(model, system_name: 'Shared Service Water Loop')
    booster = @swh.create_booster_water_heating_loop(model, service_water_loop: shared, setpoint_offset: 0.0)
    refute_nil(booster)

    tank = water_heater_on(booster)
    actual_c = OpenstudioStandards::Schedules.schedule_get_min_max(tank.setpointTemperatureSchedule.get)['max']
    assert_in_delta(82.2, actual_c, 0.1, 'setpoint_offset: 0.0 should leave the loop at the fixture temperature')
  end

  # A building with no booster draws must size exactly as before.
  def test_no_booster_leaves_shared_sizing_untouched
    model = @std.safe_load_model("#{__dir__}/../../os_stds_methods/models/QuickServiceRestaurant_2A_2010.osm")
    model.getPlantLoops.each(&:remove)
    @swh.create_typical_service_water_heating(model)

    assert(model.getPlantLoopByName('Booster Service Water Loop').empty?,
           'this model was chosen because it has no booster loop')
    loop = model.getPlantLoops.find { |l| l.demandComponents.any? { |c| !c.to_WaterUseConnections.empty? } }
    refute_nil(loop)

    expected_btu_per_hr = diversified_gph_on(loop) * 8.4 * 1.0 * (140.0 - 40.0) / 0.8
    actual_btu_per_hr = OpenStudio.convert(water_heater_on(loop).heaterMaximumCapacity.get, 'W', 'Btu/hr').get
    assert_in_epsilon(expected_btu_per_hr, actual_btu_per_hr, 0.02)
  end
end
