require_relative '../../../helpers/minitest_helper'

class TestHVACHeatExchangerAirToAir < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_create_hx_air_to_air_sensible_and_latent
    model = OpenStudio::Model::Model.new

    hx = @hvac.create_heat_exchanger_air_to_air_sensible_and_latent(model,
                                                                    name: "ERV HX",
                                                                    type: 'Rotary',
                                                                    economizer_lockout: false,
                                                                    supply_air_outlet_temperature_control: false,
                                                                    frost_control_type: 'ExhaustOnly')
    assert(hx.is_a?(OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent), 'Expected hx to be a HeatExchangerAirToAirSensibleAndLatent object')
    assert_equal('ERV HX', hx.name.to_s, "Expected hx name to be 'ERV HX'")
    assert_equal('Rotary', hx.heatExchangerType.to_s, "'Expected hx type to be 'Rotary'")
    assert_equal(false, hx.economizerLockout, 'Expected hx economizer lockout to be false')
    assert_equal(false, hx.supplyAirOutletTemperatureControl, 'Expected hx supply air outlet temperature control to be false')
    assert_equal('ExhaustOnly', hx.frostControlType.to_s, "Expected hx frost control type to be 'ExhaustOnly'")
  end
end
