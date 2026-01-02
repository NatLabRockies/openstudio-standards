require_relative '../../helpers/minitest_helper'

class TestHVACConversions < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def test_seer_to_cop_no_fan
    assert_in_delta(3.46, @hvac.seer_to_cop_no_fan(12.0), 0.01)
  end

  def test_cop_no_fan_to_seer
    assert_in_delta(9.84, @hvac.cop_no_fan_to_seer(3.0), 0.01)
  end

  def test_seer_to_cop
    assert_in_delta(3.13, @hvac.seer_to_cop(12.0), 0.01)
  end

  def test_cop_to_seer
    assert_in_delta(11.34, @hvac.cop_to_seer(3.0), 0.01)
  end

  def test_cop_heating_to_cop_heating_no_fan
    assert_in_delta(3.19, @hvac.cop_heating_to_cop_heating_no_fan(3.0, 5000.0), 0.01)
  end

  def test_hspf_to_cop_no_fan
    assert_in_delta(4.023, @hvac.hspf_to_cop_no_fan(9.0), 0.001)
  end

  def test_hspf_to_cop
    assert_in_delta(3.5496, @hvac.hspf_to_cop(9.0), 0.001)
  end

  def test_eer_to_cop_no_fan
    assert_in_delta(3.467, @hvac.eer_to_cop_no_fan(10.0), 0.001)
    assert_in_delta(3.388, @hvac.eer_to_cop_no_fan(10.0, 3000.0), 0.01)
  end

  def test_cop_no_fan_to_eer
    assert_in_delta(8.60, @hvac.cop_no_fan_to_eer(3.0), 0.01)
    assert_in_delta(8.855, @hvac.cop_no_fan_to_eer(3.0, 3000.0), 0.01)
  end

  def test_ieer_to_cop_no_fan
    assert_in_delta(3.930, @hvac.ieer_to_cop_no_fan(5.0), 0.001)
  end

  def test_eer_to_cop
    assert_in_delta(2.93, @hvac.eer_to_cop(10.0), 0.01)
  end

  def test_cop_to_eer
    assert_in_delta(10.24, @hvac.cop_to_eer(3.0), 0.01)
  end

  def test_cop_to_kw_per_ton
    assert_in_delta(0.7034, @hvac.cop_to_kw_per_ton(5.0), 0.01)
  end

  def test_kw_per_ton_to_cop
    assert_in_delta(3.517, @hvac.kw_per_ton_to_cop(1.0), 0.01)
  end

  def test_afue_to_thermal_eff
    assert_in_delta(0.8, @hvac.afue_to_thermal_eff(0.8), 0.01)
  end

  def test_thermal_eff_to_afue
    assert_in_delta(0.8, @hvac.thermal_eff_to_afue(0.8), 0.01)
  end

  def test_combustion_eff_to_thermal_eff
    assert_in_delta(0.793, @hvac.combustion_eff_to_thermal_eff(0.8), 0.001)
  end

  def test_thermal_eff_to_comb_eff
    assert_in_delta(0.807, @hvac.thermal_eff_to_comb_eff(0.8), 0.001)
  end
end
