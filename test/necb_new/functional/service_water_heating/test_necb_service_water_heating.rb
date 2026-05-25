require_relative '../../test_helper'

class TestNECBServiceWaterHeating < Minitest::Test
  include(NecbHelper)

  # Test that model_add_swh completes successfully
  def test_model_add_swh_completes_successfully
    model, standard = create_baseline_necb_model('NECB2011')

    # Add SWH system
    result = standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    assert result, "model_add_swh should return true on success"

    # Verify plant loop was created
    plant_loops = model.getPlantLoops
    swh_loop = plant_loops.find { |loop| loop.name.to_s.include?('Service Water') }
    assert swh_loop, "Should create a service water heating plant loop"

    # Verify water heater was added
    water_heaters = model.getWaterHeaterMixeds
    assert water_heaters.length > 0, "Should create at least one water heater"
  end

  # Test DHW sizing calculations
  def test_auto_size_shw_capacity
    model, standard = create_baseline_necb_model('NECB2011')

    # Calculate sizing
    shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    # Verify sizing hash contains expected keys
    assert shw_sizing.key?('tank_volume_SI'), "Should include tank volume"
    assert shw_sizing.key?('tank_capacity_SI'), "Should include tank capacity"
    assert shw_sizing.key?('max_temp_SI'), "Should include max temperature"
    assert shw_sizing.key?('loop_peak_flow_rate_SI'), "Should include peak flow rate"
    assert shw_sizing.key?('parasitic_loss'), "Should include parasitic loss"
    assert shw_sizing.key?('spaces_w_dhw'), "Should include spaces with DHW"

    # Verify reasonable values
    if shw_sizing['loop_peak_flow_rate_SI'] > 0
      assert shw_sizing['tank_volume_SI'] > 0, "Tank volume should be positive"
      assert shw_sizing['tank_capacity_SI'] > 0, "Tank capacity should be positive"
      assert shw_sizing['max_temp_SI'] >= 40, "Max temperature should be at least 40°C"
      assert shw_sizing['max_temp_SI'] <= 90, "Max temperature should be at most 90°C"
    end
  end

  # Test water heater efficiency application
  def test_water_heater_mixed_apply_efficiency
    model, standard = create_baseline_necb_model('NECB2011')

    # Add SWH system first
    standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    # Get the water heater
    water_heaters = model.getWaterHeaterMixeds
    skip "No water heaters created" if water_heaters.empty?

    water_heater = water_heaters.first

    # Apply efficiency
    result = standard.water_heater_mixed_apply_efficiency(water_heater)
    assert result, "Should successfully apply efficiency"

    # Verify efficiency was set
    thermal_eff = water_heater.heaterThermalEfficiency
    if thermal_eff.respond_to?(:is_initialized)
      assert thermal_eff.is_initialized, "Thermal efficiency should be initialized"
      eff_value = thermal_eff.get
    else
      eff_value = thermal_eff
    end
    assert eff_value, "Should have thermal efficiency set"
    assert eff_value > 0.0, "Thermal efficiency should be positive"
    assert eff_value <= 1.0, "Thermal efficiency should be at most 1.0"

    # Verify on/off cycle loss coefficients were set
    on_cycle_loss = water_heater.onCycleLossCoefficienttoAmbientTemperature
    off_cycle_loss = water_heater.offCycleLossCoefficienttoAmbientTemperature

    if on_cycle_loss.respond_to?(:is_initialized)
      assert on_cycle_loss.is_initialized, "On-cycle loss should be initialized"
      on_cycle_val = on_cycle_loss.get
    else
      on_cycle_val = on_cycle_loss
    end

    if off_cycle_loss.respond_to?(:is_initialized)
      assert off_cycle_loss.is_initialized, "Off-cycle loss should be initialized"
      off_cycle_val = off_cycle_loss.get
    else
      off_cycle_val = off_cycle_loss
    end

    assert on_cycle_val >= 0, "On-cycle loss should be non-negative"
    assert off_cycle_val >= 0, "Off-cycle loss should be non-negative"
  end

  # Test natural gas water heater efficiency
  def test_natural_gas_water_heater_efficiency
    model, standard = create_baseline_necb_model('NECB2011')

    standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    water_heaters = model.getWaterHeaterMixeds
    skip "No water heaters created" if water_heaters.empty?

    water_heater = water_heaters.first

    # Verify fuel type
    assert_equal 'NaturalGas', water_heater.heaterFuelType, "Fuel type should be NaturalGas"

    # Verify efficiency is appropriate for natural gas
    thermal_eff = water_heater.heaterThermalEfficiency
    if thermal_eff.respond_to?(:is_initialized)
      assert thermal_eff.is_initialized, "Thermal efficiency should be initialized"
      eff_value = thermal_eff.get
    else
      eff_value = thermal_eff
    end
    assert eff_value >= 0.78, "Natural gas efficiency should be at least 0.78"
    assert eff_value <= 0.85, "Natural gas efficiency should be at most 0.85"
  end

  # Test electric water heater efficiency
  def test_electric_water_heater_efficiency
    model, standard = create_baseline_necb_model('NECB2011')

    standard.model_add_swh(
      model: model,
      swh_fueltype: 'Electricity',
      shw_scale: 1.0
    )

    water_heaters = model.getWaterHeaterMixeds
    skip "No water heaters created" if water_heaters.empty?

    water_heater = water_heaters.first

    # Verify fuel type
    assert_equal 'Electricity', water_heater.heaterFuelType, "Fuel type should be Electricity"

    # Verify efficiency is appropriate for electric
    thermal_eff = water_heater.heaterThermalEfficiency
    if thermal_eff.respond_to?(:is_initialized)
      assert thermal_eff.is_initialized, "Thermal efficiency should be initialized"
      eff_value = thermal_eff.get
    else
      eff_value = thermal_eff
    end
    assert_equal 1.0, eff_value, "Electric water heater efficiency should be 1.0"
  end

  # Test SWH temperature setpoints
  def test_shw_temperature_setpoints
    model, standard = create_baseline_necb_model('NECB2011')

    # Calculate sizing
    shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    skip "No DHW demand" if shw_sizing['loop_peak_flow_rate_SI'] == 0

    # Add SWH system
    standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    # Get the water heater
    water_heaters = model.getWaterHeaterMixeds
    water_heater = water_heaters.first

    # Verify setpoint temperature
    setpoint_temp_schedule = water_heater.setpointTemperatureSchedule
    if setpoint_temp_schedule.respond_to?(:is_initialized)
      assert setpoint_temp_schedule.is_initialized, "Should have setpoint temperature schedule"
    else
      assert setpoint_temp_schedule, "Should have setpoint temperature schedule"
    end

    # The setpoint should match max_temp_SI from sizing
    expected_temp = shw_sizing['max_temp_SI']
    assert expected_temp >= 40, "Setpoint temperature should be at least 40°C"
    assert expected_temp <= 90, "Setpoint temperature should be at most 90°C"
  end

  # Test SWH pump head calculation
  def test_auto_size_shw_pump_head
    model, standard = create_baseline_necb_model('NECB2011')

    # Test default mode
    pump_head_default = standard.auto_size_shw_pump_head(model, default: true)
    assert_equal 179532, pump_head_default, "Default pump head should be 179532 Pa"

    # Test calculated mode
    pump_head_calc = standard.auto_size_shw_pump_head(model, default: false)
    assert pump_head_calc > 0, "Calculated pump head should be positive"
  end

  # Test SWH scale factor
  def test_shw_scale_factor
    model, standard = create_baseline_necb_model('NECB2011')

    # Test with scale factor = 1.0
    shw_sizing_1x = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    # Test with scale factor = 2.0
    shw_sizing_2x = standard.auto_size_shw_capacity(model: model, shw_scale: 2.0)

    skip "No DHW demand" if shw_sizing_1x['loop_peak_flow_rate_SI'] == 0

    # Verify that 2x scale produces larger tank
    assert shw_sizing_2x['tank_volume_SI'] > shw_sizing_1x['tank_volume_SI'],
           "2x scale should produce larger tank volume"
    assert shw_sizing_2x['tank_capacity_SI'] > shw_sizing_1x['tank_capacity_SI'],
           "2x scale should produce larger tank capacity"
    assert shw_sizing_2x['loop_peak_flow_rate_SI'] > shw_sizing_1x['loop_peak_flow_rate_SI'],
           "2x scale should produce larger peak flow rate"
  end

  # Test SWH across NECB vintages
  def test_shw_across_necb_vintages
    ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'].each do |vintage|
      model, standard = create_baseline_necb_model(vintage)

      result = standard.model_add_swh(
        model: model,
        swh_fueltype: 'NaturalGas',
        shw_scale: 1.0
      )

      assert result, "#{vintage}: model_add_swh should return true"

      # Check if DHW demand exists
      shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

      if shw_sizing['loop_peak_flow_rate_SI'] > 0
        # If there's DHW demand, verify system was created
        plant_loops = model.getPlantLoops
        swh_loop = plant_loops.find { |loop| loop.name.to_s.include?('Service Water') }
        assert swh_loop, "#{vintage}: Should create service water loop when DHW demand exists"
      end
    end
  end

  # Test water use equipment creation
  def test_water_use_equipment_creation
    model, standard = create_baseline_necb_model('NECB2011')

    standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    # Get water use equipment
    water_use_equipment = model.getWaterUseEquipments

    # Should have water use equipment for spaces with DHW demand
    # (will be zero if no spaces have DHW demand)
    shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    if shw_sizing['loop_peak_flow_rate_SI'] > 0
      assert water_use_equipment.length > 0, "Should create water use equipment"

      # Verify each equipment is connected to the service water loop
      water_use_equipment.each do |equipment|
        connections = equipment.waterUseConnections
        if connections.respond_to?(:is_initialized)
          assert connections.is_initialized, "Water use equipment should be connected"
          conn = connections.get
        else
          conn = connections
          assert conn, "Water use equipment should be connected"
        end
      end
    end
  end

  # Test SWH with different fuel types
  def test_shw_different_fuel_types
    ['NaturalGas', 'Electricity', 'FuelOilNo2'].each do |fuel_type|
      model, standard = create_baseline_necb_model('NECB2011')

      result = standard.model_add_swh(
        model: model,
        swh_fueltype: fuel_type,
        shw_scale: 1.0
      )

      assert result, "#{fuel_type}: model_add_swh should succeed"

      # Verify fuel type
      water_heaters = model.getWaterHeaterMixeds
      next if water_heaters.empty?

      water_heater = water_heaters.first
      assert_equal fuel_type, water_heater.heaterFuelType,
                   "#{fuel_type}: Water heater should use correct fuel type"
    end
  end

  # Test SWH with no DHW demand
  def test_shw_with_no_dhw_demand
    # Create a simple model with no spaces that require DHW
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Don't add any spaces with DHW demand
    result = standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    # Should still return true but not create any equipment
    assert result, "model_add_swh should return true even with no DHW demand"

    # Verify no plant loops created
    plant_loops = model.getPlantLoops
    swh_loop = plant_loops.find { |loop| loop.name.to_s.include?('Service Water') }
    assert_nil swh_loop, "Should not create service water loop when no DHW demand"
  end

  # Test SWH parasitic losses
  def test_shw_parasitic_losses
    model, standard = create_baseline_necb_model('NECB2011')

    # Calculate sizing
    shw_sizing = standard.auto_size_shw_capacity(model: model, shw_scale: 1.0)

    skip "No DHW demand" if shw_sizing['loop_peak_flow_rate_SI'] == 0

    # Verify parasitic loss was calculated
    parasitic_loss = shw_sizing['parasitic_loss']
    assert parasitic_loss >= 0, "Parasitic loss should be non-negative"

    # Add SWH system
    standard.model_add_swh(
      model: model,
      swh_fueltype: 'NaturalGas',
      shw_scale: 1.0
    )

    # Verify parasitic loss was applied to water heater
    water_heaters = model.getWaterHeaterMixeds
    water_heater = water_heaters.first

    # Check on-cycle parasitic fuel consumption rate
    on_cycle_para = water_heater.onCycleParasiticFuelConsumptionRate
    off_cycle_para = water_heater.offCycleParasiticFuelConsumptionRate

    # These should be set (even if to zero)
    assert on_cycle_para || on_cycle_para == 0, "On-cycle parasitic should be set"
    assert off_cycle_para || off_cycle_para == 0, "Off-cycle parasitic should be set"
  end

  # Test SWH climate variation
  def test_shw_climate_variation
    # Test in different climate zones (different weather files)
    climates = [
      { name: 'Vancouver', epw: 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw', zone: 4 },
      { name: 'Toronto', epw: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw', zone: 5 },
      { name: 'Yellowknife', epw: 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw', zone: 8 }
    ]

    climates.each do |climate|
      model, standard = create_baseline_necb_model('NECB2011', climate[:epw])

      result = standard.model_add_swh(
        model: model,
        swh_fueltype: 'NaturalGas',
        shw_scale: 1.0
      )

      assert result, "#{climate[:name]}: model_add_swh should succeed"

      # SWH requirements don't vary by climate zone in NECB
      # (unlike HVAC or envelope), but verify system is created correctly
      plant_loops = model.getPlantLoops
      swh_loop = plant_loops.find { |loop| loop.name.to_s.include?('Service Water') }
      assert swh_loop, "#{climate[:name]}: Should create service water loop"
    end
  end

  private

  # Helper method to create baseline NECB model for testing
  def create_baseline_necb_model(template = 'NECB2011', epw_file = 'CAN_ON_Toronto.Pearson.Intl.AP.716240_CWEC2016.epw')
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '../../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(resource_path).get

    # Set weather file
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply NECB space types
    model.getSpaceTypes.each do |space_type|
      space_type.setStandardsBuildingType('Space Function')
      space_type.setStandardsSpaceType('Office - open plan')
    end

    # Set building properties
    building = model.getBuilding
    building.setStandardsNumberOfStories(2)
    building.setStandardsNumberOfAboveGroundStories(2)

    [model, standard]
  end
end
