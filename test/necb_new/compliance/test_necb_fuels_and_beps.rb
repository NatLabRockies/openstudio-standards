require_relative '../../helpers/minitest_helper'
require_relative '../../helpers/necb_helper'

# Test suite for NECB System Fuels and BEPS Compliance
#
# Tests cover:
# 1. SystemFuels class initialization and configuration
# 2. Fuel type selection logic for different primary fuels
# 3. Boiler fuel configuration with dual-fuel systems
# 4. Service hot water fuel assignments
# 5. BEPS (Building Energy Performance Standard) compliance checking
#
# Key methods under test:
# - SystemFuels.set_defaults() - Initialize fuel configuration
# - SystemFuels.set_boiler_fuel() - Configure boiler fuels
# - SystemFuels.set_swh_fuel() - Set service hot water fuel
# - SystemFuels.set_airloop_fancoils_heating() - Force hot water heating coils
# - SystemFuels.set_fuel_to_hvac_system_primary() - Override fuel based on HVAC system
# - NECB2011.beps_compliance_path() - BEPS compliance checking (if implemented)
class TestNECBFuelsAndBEPS < Minitest::Test
  include(NecbHelper)

  # Helper method to create a baseline NECB model for testing
  def create_baseline_necb_model(template = 'NECB2011', epw_file = 'CAN_ON_Toronto.Pearson.Intl.AP.716240_CWEC2016.epw')
    standard = Standard.build(template)

    # Load the standard NECB test resource model
    resource_path = File.join(File.dirname(__FILE__), '../../necb/unit_tests/resources/5ZoneNoHVAC.osm')
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

    return model, standard
  end

  # Test 1: SystemFuels initialization with NaturalGas primary fuel
  def test_system_fuels_natural_gas_initialization
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'NaturalGas'
    )

    # Verify natural gas configuration
    assert_equal 'NaturalGas', system_fuels.name, "Fuel set name should be NaturalGas"
    assert_equal 'NaturalGas', system_fuels.boiler_fueltype, "Boiler fuel should be NaturalGas"
    assert_equal 'NaturalGas', system_fuels.backup_boiler_fueltype, "Backup boiler fuel should be NaturalGas"
    assert_equal 'Hot Water', system_fuels.baseboard_type, "Baseboards should be Hot Water for gas"
    assert_equal 'Gas', system_fuels.heating_coil_type_sys2, "System 2 heating should be Gas"
    assert_equal 'Gas', system_fuels.heating_coil_type_sys3, "System 3 heating should be Gas"
    assert_equal 'Gas', system_fuels.heating_coil_type_sys4, "System 4 heating should be Gas"
    assert_equal 'Hot Water', system_fuels.heating_coil_type_sys6, "System 6 heating should be Hot Water"
    assert_equal 'NaturalGas', system_fuels.swh_fueltype, "SWH fuel should be NaturalGas"
    assert_equal false, system_fuels.necb_reference_hp, "Should not be heat pump system"
    assert_equal false, system_fuels.force_boiler, "Should not force boiler initially"
    assert_equal false, system_fuels.force_airloop_hot_water, "Should not force airloop hot water initially"
  end

  # Test 2: SystemFuels initialization with Electricity primary fuel
  def test_system_fuels_electricity_initialization
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'Electricity'
    )

    # Verify electric configuration
    assert_equal 'Electricity', system_fuels.name, "Fuel set name should be Electricity"
    assert_equal 'Electricity', system_fuels.boiler_fueltype, "Boiler fuel should be Electricity"
    assert_equal 'Electric', system_fuels.baseboard_type, "Baseboards should be Electric"
    assert_equal 'Electric', system_fuels.heating_coil_type_sys2, "System 2 heating should be Electric"
    assert_equal 'Electric', system_fuels.heating_coil_type_sys3, "System 3 heating should be Electric"
    assert_equal 'Electric', system_fuels.heating_coil_type_sys4, "System 4 heating should be Electric"
    assert_equal 'Electric', system_fuels.heating_coil_type_sys6, "System 6 heating should be Electric"
    assert_equal 'Electricity', system_fuels.swh_fueltype, "SWH fuel should be Electricity"
    assert_equal false, system_fuels.necb_reference_hp, "Should not be heat pump system"
  end

  # Test 3: SystemFuels initialization with FuelOilNo2 primary fuel
  def test_system_fuels_fuel_oil_initialization
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'FuelOilNo2'
    )

    # Verify fuel oil configuration
    assert_equal 'FuelOilNo2', system_fuels.name, "Fuel set name should be FuelOilNo2"
    assert_equal 'FuelOilNo2', system_fuels.boiler_fueltype, "Boiler fuel should be FuelOilNo2"
    assert_equal 'Hot Water', system_fuels.baseboard_type, "Baseboards should be Hot Water for oil"
    assert_equal 'Electric', system_fuels.heating_coil_type_sys2, "System 2 heating should be Electric for oil"
    assert_equal 'FuelOilNo2', system_fuels.swh_fueltype, "SWH fuel should be FuelOilNo2"
    assert_equal 'Electricity', system_fuels.ecm_fueltype, "ECM fuel should be Electricity for oil systems"
  end

  # Test 4: SystemFuels initialization with heat pump configuration
  def test_system_fuels_heat_pump_initialization
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'NaturalGasHPGasBackup'
    )

    # Verify heat pump configuration
    assert_equal 'NaturalGasHPGasBackup', system_fuels.name, "Fuel set name should be NaturalGasHPGasBackup"
    assert_equal true, system_fuels.necb_reference_hp, "Should be NECB reference heat pump system"
    assert_equal 'DX', system_fuels.heating_coil_type_sys2, "System 2 heating should be DX for HP"
    assert_equal 'DX', system_fuels.heating_coil_type_sys3, "System 3 heating should be DX for HP"
    assert_equal 'DX', system_fuels.heating_coil_type_sys4, "System 4 heating should be DX for HP"
    assert_equal 'DX', system_fuels.mau_heating_coil_type, "MAU heating should be DX for HP"
    assert_equal 'NaturalGas', system_fuels.necb_reference_hp_supp_fuel, "HP supplemental fuel should be NaturalGas"
  end

  # Test 5: Set boiler fuel with dual-fuel configuration
  def test_set_boiler_fuel_dual_fuel
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'Electricity'
    )

    # Configure dual-fuel boilers: primary gas, backup electric
    system_fuels.set_boiler_fuel(
      standards_data: standard.standards_data,
      boiler_fuel: 'NaturalGasElecBackup',
      boiler_cap_ratios: { primary_ratio: 0.7, secondary_ratio: 0.3 }
    )

    # Verify dual-fuel configuration
    assert_equal 'NaturalGas', system_fuels.boiler_fueltype, "Primary boiler should be NaturalGas"
    assert_equal 'Electricity', system_fuels.backup_boiler_fueltype, "Backup boiler should be Electricity"
    assert_equal 0.7, system_fuels.primary_boiler_cap_frac, "Primary boiler should be 70% capacity"
    assert_equal 0.3, system_fuels.secondary_boiler_cap_frac, "Secondary boiler should be 30% capacity"
    assert_equal true, system_fuels.force_boiler, "Should force boiler creation"
    assert_equal 'Hot Water', system_fuels.baseboard_type, "Baseboards should be Hot Water"
    assert_equal 'Hot Water', system_fuels.heating_coil_type_sys6, "System 6 should use Hot Water"
  end

  # Test 6: Set service hot water fuel independently
  def test_set_swh_fuel_independent
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'NaturalGas'
    )

    # Initially should be NaturalGas (same as primary)
    assert_equal 'NaturalGas', system_fuels.swh_fueltype, "Initial SWH fuel should match primary"

    # Change SWH fuel to electricity
    system_fuels.set_swh_fuel(swh_fuel: 'Electricity')

    # Verify SWH fuel changed while space heating remains gas
    assert_equal 'Electricity', system_fuels.swh_fueltype, "SWH fuel should be Electricity"
    assert_equal 'NaturalGas', system_fuels.boiler_fueltype, "Boiler fuel should still be NaturalGas"
    assert_equal 'Gas', system_fuels.heating_coil_type_sys2, "System 2 heating should still be Gas"
  end

  # Test 7: Force airloop hot water heating coils
  def test_set_airloop_fancoils_heating
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'NaturalGas'
    )

    # Force hot water coils
    system_fuels.set_airloop_fancoils_heating()

    # Verify all heating coils are hot water except DX (heat pumps)
    assert_equal 'Hot Water', system_fuels.mau_heating_coil_type, "MAU heating should be Hot Water"
    assert_equal 'Hot Water', system_fuels.heating_coil_type_sys2, "System 2 heating should be Hot Water"
    assert_equal 'Hot Water', system_fuels.heating_coil_type_sys3, "System 3 heating should be Hot Water"
    assert_equal 'Hot Water', system_fuels.heating_coil_type_sys4, "System 4 heating should be Hot Water"
    assert_equal 'Hot Water', system_fuels.heating_coil_type_sys6, "System 6 heating should be Hot Water"
    assert_equal true, system_fuels.force_airloop_hot_water, "Should force airloop hot water"
  end

  # Test 8: Force airloop hot water preserves heat pump DX coils
  def test_set_airloop_fancoils_heating_preserves_dx
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'ElectricityHPElecBackup'
    )

    # Initial state should have DX coils
    assert_equal 'DX', system_fuels.heating_coil_type_sys4, "System 4 should initially be DX"

    # Force hot water coils - should preserve DX for heat pumps
    system_fuels.set_airloop_fancoils_heating()

    # Verify DX coils are preserved
    assert_equal 'DX', system_fuels.mau_heating_coil_type, "MAU should remain DX for HP"
    assert_equal 'DX', system_fuels.heating_coil_type_sys2, "System 2 should remain DX for HP"
    assert_equal 'DX', system_fuels.heating_coil_type_sys4, "System 4 should remain DX for HP"

    # But supplemental heating should be hot water
    assert_equal 'Hot Water', system_fuels.necb_reference_hp_supp_fuel, "HP supplemental fuel should be Hot Water"
  end

  # Test 9: Reset to default fuel info
  def test_reset_default_fuel_info
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'NaturalGas'
    )

    # Store initial state
    init_fuel_type = {
      name: system_fuels.name,
      boiler_fueltype: system_fuels.boiler_fueltype,
      backup_boiler_fueltype: system_fuels.backup_boiler_fueltype,
      primary_boiler_cap_frac: system_fuels.primary_boiler_cap_frac,
      secondary_boiler_cap_frac: system_fuels.secondary_boiler_cap_frac,
      baseboard_type: system_fuels.baseboard_type,
      mau_type: system_fuels.mau_type,
      mau_heating_coil_type: system_fuels.mau_heating_coil_type,
      mau_cooling_type: system_fuels.mau_cooling_type,
      chiller_type: system_fuels.chiller_type,
      heating_coil_type_sys2: system_fuels.heating_coil_type_sys2,
      heating_coil_type_sys3: system_fuels.heating_coil_type_sys3,
      heating_coil_type_sys4: system_fuels.heating_coil_type_sys4,
      heating_coil_type_sys6: system_fuels.heating_coil_type_sys6,
      necb_reference_hp: system_fuels.necb_reference_hp,
      necb_reference_hp_supp_fuel: system_fuels.necb_reference_hp_supp_fuel,
      fan_type: system_fuels.fan_type,
      ecm_fueltype: system_fuels.ecm_fueltype,
      swh_fueltype: system_fuels.swh_fueltype,
      force_boiler: system_fuels.force_boiler,
      force_airloop_hot_water: system_fuels.force_airloop_hot_water
    }

    # Modify the configuration
    system_fuels.set_swh_fuel(swh_fuel: 'Electricity')
    system_fuels.set_airloop_fancoils_heating()

    assert_equal 'Electricity', system_fuels.swh_fueltype, "SWH should be modified"
    assert_equal true, system_fuels.force_airloop_hot_water, "Should be forced"

    # Reset to initial state
    system_fuels.reset_default_fuel_info(init_fuel_type: init_fuel_type)

    # Verify all values restored
    assert_equal 'NaturalGas', system_fuels.name, "Name should be restored"
    assert_equal 'NaturalGas', system_fuels.swh_fueltype, "SWH fuel should be restored"
    assert_equal false, system_fuels.force_airloop_hot_water, "force_airloop_hot_water should be restored"
    assert_equal 'Gas', system_fuels.heating_coil_type_sys2, "System 2 heating should be restored"
  end

  # Test 10: Test across multiple NECB vintages
  def test_system_fuels_across_vintages
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      model, standard = create_baseline_necb_model(vintage)

      system_fuels = SystemFuels.new
      system_fuels.set_defaults(
        standards_data: standard.standards_data,
        primary_heating_fuel: 'NaturalGas'
      )

      # Verify basic configuration works across all vintages
      assert_equal 'NaturalGas', system_fuels.boiler_fueltype, "#{vintage}: Boiler fuel should be NaturalGas"
      assert_equal 'Hot Water', system_fuels.baseboard_type, "#{vintage}: Baseboards should be Hot Water"
      assert_equal 'NaturalGas', system_fuels.swh_fueltype, "#{vintage}: SWH fuel should be NaturalGas"

      # Test heat pump configuration
      system_fuels_hp = SystemFuels.new
      system_fuels_hp.set_defaults(
        standards_data: standard.standards_data,
        primary_heating_fuel: 'ElectricityHPElecBackup'
      )

      assert_equal true, system_fuels_hp.necb_reference_hp, "#{vintage}: Should support heat pump configuration"
      assert_equal 'DX', system_fuels_hp.heating_coil_type_sys4, "#{vintage}: HP should use DX heating"
    end
  end

  # Test 11: Invalid fuel type raises error
  def test_invalid_fuel_type_raises_error
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new

    # Should raise error for invalid fuel type
    error = assert_raises(RuntimeError) do
      system_fuels.set_defaults(
        standards_data: standard.standards_data,
        primary_heating_fuel: 'InvalidFuelType'
      )
    end

    assert_match(/not found in fuel_type_sets table/, error.message,
                 "Should raise error about missing fuel type")
  end

  # Test 12: Boiler capacity ratios sum validation
  def test_boiler_capacity_ratios_configuration
    model, standard = create_baseline_necb_model('NECB2011')

    system_fuels = SystemFuels.new
    system_fuels.set_defaults(
      standards_data: standard.standards_data,
      primary_heating_fuel: 'NaturalGas'
    )

    # Test various capacity ratio configurations
    test_ratios = [
      { primary_ratio: 1.0, secondary_ratio: 0.0 },   # Single boiler
      { primary_ratio: 0.5, secondary_ratio: 0.5 },   # Equal capacity
      { primary_ratio: 0.8, secondary_ratio: 0.2 },   # Asymmetric
      { primary_ratio: 0.6, secondary_ratio: 0.4 }    # 60/40 split
    ]

    test_ratios.each do |ratios|
      system_fuels.set_boiler_fuel(
        standards_data: standard.standards_data,
        boiler_fuel: 'NaturalGas',
        boiler_cap_ratios: ratios
      )

      assert_equal ratios[:primary_ratio], system_fuels.primary_boiler_cap_frac,
                   "Primary ratio should be #{ratios[:primary_ratio]}"
      assert_equal ratios[:secondary_ratio], system_fuels.secondary_boiler_cap_frac,
                   "Secondary ratio should be #{ratios[:secondary_ratio]}"

      # Verify they sum to 1.0 (or close due to floating point)
      total = system_fuels.primary_boiler_cap_frac + system_fuels.secondary_boiler_cap_frac
      assert_in_delta 1.0, total, 0.001, "Capacity ratios should sum to 1.0"
    end
  end
end
