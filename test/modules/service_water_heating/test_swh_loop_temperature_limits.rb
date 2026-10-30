require_relative '../../helpers/minitest_helper'

# A plant loop's Minimum/Maximum Loop Temperature are sanity bounds EnergyPlus checks and
# warns against, not controls. Two defects came out of that:
#
# The shared loop stated a 125 F Legionella floor, which enforced nothing and guaranteed a
# warning, because the bound is checked against the whole loop and a service water loop's
# return leg is necessarily cooler than its supply. A small hotel model logged 14,226
# "Plant loop falling below lower temperature limit" warnings a year with its heater at a
# 33.7% load factor and zero unmet demand - every energy series was identical with the
# bound removed, so it was purely cosmetic.
#
# And the booster builder set both limits on the shared loop passed in as an argument
# rather than on the booster loop it had just created, leaving the booster loop on the
# OpenStudio defaults and overwriting the shared loop's 140 F maximum with the booster's
# 184 F.
class TestServiceWaterHeatingLoopTemperatureLimits < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
  end

  def test_shared_loop_states_no_legionella_floor
    model = OpenStudio::Model::Model.new
    loop = @swh.create_service_water_heating_loop(model)
    refute_nil(loop, 'no service water loop was created')

    assert_in_delta(0.0, loop.minimumLoopTemperature, 0.001,
                    'the shared loop should not carry a minimum temperature bound it cannot satisfy')
    # the setpoint, not the bound, is where the delivered temperature is stated
    assert_operator(loop.maximumLoopTemperature, :>=, 60.0)
  end

  def test_booster_limits_land_on_the_booster_loop
    model = OpenStudio::Model::Model.new
    shared = @swh.create_service_water_heating_loop(model)
    shared_max_before = shared.maximumLoopTemperature

    @swh.create_booster_water_heating_loop(model, service_water_loop: shared)
    booster = model.getPlantLoopByName('Booster Service Water Loop')
    refute(booster.empty?, 'no booster loop was created')
    booster = booster.get

    assert_operator(booster.maximumLoopTemperature, :>=, 82.2,
                    'the booster loop should carry its own maximum, not the OpenStudio default')
    assert_in_delta(0.0, booster.minimumLoopTemperature, 0.001)
    assert_in_delta(shared_max_before, shared.maximumLoopTemperature, 0.001,
                    'building the booster loop must not rewrite the shared loop maximum')
  end
end
