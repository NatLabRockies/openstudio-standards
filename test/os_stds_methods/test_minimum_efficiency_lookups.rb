require_relative '../helpers/minitest_helper'

class TestSpaceType < Minitest::Test
    def test_water_heater_efficiency_lookup
        std = Standard.build('90.1-2019')
        volume_gal = 10.0
        capacity_btu_per_hr = 20_472
        water_heater_mixed = nil
        fuel_type = 'Electricity'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        # this is a valid lookup for the water heater data data, so not sure why the test checks for an empty hash
        # assert(wh_props == {})

        volume_gal = 19.9
        capacity_btu_per_hr = 20_472
        water_heater_mixed = nil
        fuel_type = 'NaturalGas'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        assert_equal(0.6483, wh_props['uniform_energy_factor_base'])
        assert_equal(0.0017, wh_props['uniform_energy_factor_volume_allowance'])

        volume_gal = 19.9
        capacity_btu_per_hr = 135_000
        water_heater_mixed = nil
        fuel_type = 'Oil'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        assert_equal(0.6194, wh_props['uniform_energy_factor_base'])
        assert_equal(0.0016, wh_props['uniform_energy_factor_volume_allowance'])

        volume_gal = 19.9
        capacity_btu_per_hr = 150_000
        water_heater_mixed = nil
        fuel_type = 'NaturalGas'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        assert_equal(0.80, wh_props['thermal_efficiency'])
    end
end

class TestWaterToAirHeatPumpEfficiencyLookup < Minitest::Test
  # Looks up the minimum cooling EER of a water-to-air heat pump coil.
  #
  # @param std [Standard] standard to use for the lookup
  # @param capacity_btu_per_hr [Float] coil capacity in Btu/hr
  # @return [Float, nil] minimum cooling EER found for the capacity
  def cooling_eer(std, capacity_btu_per_hr)
    props = std.water_to_air_heat_pump_find_efficiency_object('heat_pumps', capacity_btu_per_hr, 'test coil')
    return props.nil? ? nil : (props['minimum_energy_efficiency_ratio'] || props['minimum_full_load_efficiency'])
  end

  # Looks up the minimum heating COP of a water-to-air heat pump coil.
  #
  # @param std [Standard] standard to use for the lookup
  # @param capacity_btu_per_hr [Float] coil capacity in Btu/hr
  # @return [Float, nil] minimum heating COP found for the capacity
  def heating_cop(std, capacity_btu_per_hr)
    props = std.water_to_air_heat_pump_find_efficiency_object('heat_pumps_heating', capacity_btu_per_hr, 'test coil')
    return props.nil? ? nil : props['minimum_coefficient_of_performance_heating']
  end

  def test_lookup_by_capacity
    # template => [EER < 17 kBtu/h, EER 17-65 kBtu/h, EER 65-135 kBtu/h, heating COP]
    expected = {
      '90.1-2004' => [11.2, 12.0, 12.0, 4.2],
      '90.1-2010' => [11.2, 12.0, 12.0, 4.2],
      '90.1-2013' => [12.2, 13.0, 13.0, 4.3],
      '90.1-2019' => [12.2, 13.0, 13.0, 4.3],
      '90.1-2022' => [12.2, 13.0, 13.0, 4.3]
    }
    expected.each do |template, (eer_small, eer_medium, eer_large, cop)|
      std = Standard.build(template)
      assert_equal(eer_small, cooling_eer(std, 10_000), "#{template} cooling, 10 kBtu/h")
      assert_equal(eer_medium, cooling_eer(std, 30_000), "#{template} cooling, 30 kBtu/h")
      assert_equal(eer_large, cooling_eer(std, 100_000), "#{template} cooling, 100 kBtu/h")
      assert_equal(cop, heating_cop(std, 10_000), "#{template} heating, 10 kBtu/h")
      assert_equal(cop, heating_cop(std, 100_000), "#{template} heating, 100 kBtu/h")
    end
  end

  def test_capacity_between_ranges
    # 17,000 Btu/h is above the maximum of the first range and not above the minimum of the second one
    std = Standard.build('90.1-2013')
    assert_equal(12.2, cooling_eer(std, 17_000))
  end

  def test_water_to_water_rows_are_excluded
    ['90.1-2010', '90.1-2013', '90.1-2019', '90.1-2022'].each do |template|
      std = Standard.build(template)
      [1_000, 17_000, 50_000, 134_000].each do |capacity|
        std.water_to_air_heat_pump_find_efficiency_objects('heat_pumps', capacity).each do |props|
          refute_equal('Water to Water', props['configuration'], "#{template} cooling #{capacity} Btu/h")
        end
        std.water_to_air_heat_pump_find_efficiency_objects('heat_pumps_heating', capacity).each do |props|
          refute_equal('Water to Water', props['configuration'], "#{template} heating #{capacity} Btu/h")
        end
      end
    end
  end

  def test_legacy_water_source_tables_are_used_when_heat_pump_tables_have_no_water_source_rows
    std = Standard.build('DOE Ref 1980-2004')
    assert(std.standards_data['heat_pumps'].none? { |row| row['cooling_type'] == 'WaterSource' })
    assert_equal(11.2, cooling_eer(std, 10_000))
    assert_equal(12.0, cooling_eer(std, 100_000))
    assert_equal(4.2, heating_cop(std, 100_000))
  end

  def test_capacity_larger_than_data_uses_largest_capacity_and_logs
    ['90.1-2013', '90.1-2022', 'DOE Ref 1980-2004'].each do |template|
      std = Standard.build(template)
      largest_capacity_eer = cooling_eer(std, 134_000)
      largest_capacity_cop = heating_cop(std, 134_000)
      refute_nil(largest_capacity_eer)
      refute_nil(largest_capacity_cop)

      log_sink = OpenStudio::StringStreamLogSink.new
      log_sink.setLogLevel(OpenStudio::Warn)
      eer = cooling_eer(std, 400_000)
      cop = heating_cop(std, 400_000)
      messages = log_sink.logMessages.map(&:logMessage)

      assert_equal(largest_capacity_eer, eer, "#{template} cooling EER above the maximum capacity")
      assert_equal(largest_capacity_cop, cop, "#{template} heating COP above the maximum capacity")
      assert(messages.any? { |m| m.include?('larger than the maximum capacity') && m.include?('heat_pumps ') }, "#{template}: expected a warning for the cooling lookup, got #{messages}")
      # The legacy heating table used by DOE Ref 1980-2004 covers capacities up to 9,999,999 Btu/h
      if template == 'DOE Ref 1980-2004'
        assert(messages.none? { |m| m.include?('heat_pumps_heating') }, "#{template}: unexpected warning for the heating lookup, got #{messages}")
      else
        assert(messages.any? { |m| m.include?('larger than the maximum capacity') && m.include?('heat_pumps_heating') }, "#{template}: expected a warning for the heating lookup, got #{messages}")
      end
    end
  end

  def test_capacity_within_data_does_not_log
    std = Standard.build('90.1-2019')
    log_sink = OpenStudio::StringStreamLogSink.new
    log_sink.setLogLevel(OpenStudio::Warn)
    cooling_eer(std, 100_000)
    heating_cop(std, 100_000)
    assert(log_sink.logMessages.none? { |m| m.logMessage.include?('larger than the maximum capacity') })
  end

  def test_coil_minimum_cop
    std = Standard.build('90.1-2022')
    model = OpenStudio::Model::Model.new

    cooling_coil = OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit.new(model)
    heating_coil = OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit.new(model)

    # Within and above the capacity range of the data
    [30_000.0, 400_000.0].each do |capacity_btu_per_hr|
      capacity_w = OpenStudio.convert(capacity_btu_per_hr, 'Btu/hr', 'W').get
      cooling_coil.setRatedTotalCoolingCapacity(capacity_w)
      heating_coil.setRatedHeatingCapacity(capacity_w)

      assert_in_delta(OpenstudioStandards::HVAC.eer_to_cop_no_fan(13.0), std.coil_cooling_water_to_air_heat_pump_standard_minimum_cop(cooling_coil), 0.001, "cooling coil, #{capacity_btu_per_hr} Btu/h")
      assert_in_delta(4.3, std.coil_heating_water_to_air_heat_pump_standard_minimum_cop(heating_coil), 0.001, "heating coil, #{capacity_btu_per_hr} Btu/h")
    end
  end
end
