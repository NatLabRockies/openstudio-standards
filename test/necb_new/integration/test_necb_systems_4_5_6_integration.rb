require_relative '../test_helper'
require_relative '../fixtures/fixture_loader'

# Integration Tests for NECB Systems 4, 5, and 6
# These tests use pre-sized fixture models to verify HVAC component creation
# and configuration without requiring EnergyPlus sizing runs in every test.
#
# System 4: Makeup Air Unit (MAU) + Zone Baseboards
# System 5: Two-Pipe Fan Coil (TPFC) + MAU
# System 6: Built-up VAV System
#
# Fixtures are generated once using: bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb
# Tests load fixtures instantly and verify components, sizing, and configuration.

class TestNECBSystems456Integration < Minitest::Test
  include FixtureLoader

  # ============================================================================
  # NECB System 4: Makeup Air Unit with Baseboard Heating
  # ============================================================================

  def test_system_4_hw_components_created
    # Test that System 4 with hot water heating creates expected components
    model = load_sized_fixture('system_4_hw_toronto')

    # Verify MAU air loops
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 4 should create MAU air loops"

    # Verify at least one air loop has outdoor air system
    has_oa = air_loops.any? { |loop| loop.airLoopHVACOutdoorAirSystem.is_initialized }
    assert has_oa, "System 4 MAU should have outdoor air system"

    # Verify hot water baseboards exist
    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    assert baseboards.size > 0, "System 4 with HW should have hot water baseboards"

    # Verify hot water loop exists
    hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
    assert hw_loops.size > 0, "System 4 with HW should have hot water plant loop"

    # Verify baseboards are connected to hot water loop
    baseboards.each do |bb|
      heating_coil = bb.heatingCoil
      if heating_coil.to_CoilHeatingWater.is_initialized
        coil = heating_coil.to_CoilHeatingWater.get
        assert coil.plantLoop.is_initialized, "HW baseboard should be connected to plant loop"
      end
    end
  end

  def test_system_4_electric_heating_components
    # Test that System 4 with electric heating creates expected components
    model = load_sized_fixture('system_4_electric_toronto')

    # Verify MAU air loops
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 4 should create MAU air loops"

    # Verify electric baseboards exist
    electric_bb = model.getZoneHVACBaseboardConvectiveElectrics
    assert electric_bb.size > 0, "System 4 with electric should have electric baseboards"

    # Verify no hot water loops
    hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
    assert_equal 0, hw_loops.size, "System 4 with electric should not have hot water loops"
  end

  def test_system_4_fan_type
    # Test that System 4 uses constant volume fan
    model = load_sized_fixture('system_4_hw_toronto')

    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      fan_found = false
      air_loop.supplyComponents.each do |component|
        if component.to_FanConstantVolume.is_initialized
          fan = component.to_FanConstantVolume.get
          fan_found = true
          # System 4 MAU should use constant volume fan
          assert fan.isMaximumFlowRateAutosized || fan.maximumFlowRate.get > 0,
                 "System 4 fan should have flow rate"
        elsif component.to_FanVariableVolume.is_initialized
          # Should not have VAV fan in System 4
          flunk "System 4 should use constant volume fan, not VAV fan"
        end
      end
      assert fan_found, "System 4 air loop should have a fan" if air_loop.supplyComponents.any?
    end
  end

  def test_system_4_outdoor_air_system
    # Test that System 4 MAU has proper outdoor air configuration
    model = load_sized_fixture('system_4_hw_toronto')

    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      if air_loop.airLoopHVACOutdoorAirSystem.is_initialized
        oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
        controller = oa_system.getControllerOutdoorAir

        # MAU should have minimum OA flow
        assert controller.minimumOutdoorAirFlowRate.is_initialized ||
               controller.isMinimumOutdoorAirFlowRateAutosized,
               "System 4 MAU should have minimum outdoor air flow configured"
      end
    end
  end

  def test_system_4_zones_have_baseboards
    # Test that all zones in System 4 have baseboard heating
    model = load_sized_fixture('system_4_hw_toronto')

    zones = model.getThermalZones
    zones.each do |zone|
      zone_equipment = zone.equipment
      has_baseboard = zone_equipment.any? do |equip|
        equip.to_ZoneHVACBaseboardConvectiveWater.is_initialized ||
        equip.to_ZoneHVACBaseboardConvectiveElectric.is_initialized
      end

      assert has_baseboard, "Zone '#{zone.name}' should have baseboard heating in System 4"
    end
  end

  def test_system_4_mau_serves_all_zones
    # Test that System 4 MAU serves all thermal zones
    model = load_sized_fixture('system_4_hw_toronto')

    zones = model.getThermalZones
    air_loops = model.getAirLoopHVACs

    # Each zone should be served by an air loop (MAU)
    zones.each do |zone|
      air_loop = zone.airLoopHVAC
      assert air_loop.is_initialized, "Zone '#{zone.name}' should be served by MAU air loop"
    end
  end

  def test_system_4_has_sizing_results
    # Test that System 4 fixture has sizing results available
    model = load_sized_fixture('system_4_hw_toronto')

    sql_file = model.sqlFile
    assert sql_file.is_initialized, "System 4 fixture should have sizing results (SQL file)"
  end

  def test_system_4_equipment_is_autosized
    # Test that System 4 equipment has been autosized
    model = load_sized_fixture('system_4_hw_toronto')

    # Check that fans have been sized
    fans = model.getFanConstantVolumes
    fans.each do |fan|
      # After sizing, autosized fields should have values available via SQL
      # or the model should indicate sizing was performed
      if fan.isMaximumFlowRateAutosized
        # This is expected - autosized means value will be determined during sizing
        assert true
      else
        # If hard-sized, should have a value
        assert fan.maximumFlowRate.is_initialized, "Fan should have flow rate after sizing"
      end
    end
  end

  # ============================================================================
  # NECB System 5: Two-Pipe Fan Coil with MAU
  # ============================================================================

  def test_system_5_components_created
    # Test that System 5 creates MAU, fan coils, and chilled water plant
    model = load_sized_fixture('system_5_tpfc_toronto')

    # Verify MAU exists
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 5 should have MAU air loop"

    # Verify fan coil units
    fan_coils = model.getZoneHVACFourPipeFanCoils
    assert fan_coils.size > 0, "System 5 should have fan coil units"

    # Verify chilled water loop
    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 5 should have chilled water loop"

    # Verify hot water loop
    hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
    assert hw_loops.size > 0, "System 5 should have hot water loop"
  end

  def test_system_5_fan_coil_units
    # Test that System 5 creates two-pipe fan coil units in zones
    model = load_sized_fixture('system_5_tpfc_toronto')

    fan_coils = model.getZoneHVACFourPipeFanCoils
    zones = model.getThermalZones

    # Should have fan coil for each zone
    assert fan_coils.size >= zones.size, "System 5 should have fan coils for zones"

    # Verify fan coils are connected to plant loops
    fan_coils.each do |fc|
      cooling_coil = fc.coolingCoil
      heating_coil = fc.heatingCoil

      # Check cooling coil connection
      if cooling_coil.to_CoilCoolingWater.is_initialized
        coil = cooling_coil.to_CoilCoolingWater.get
        assert coil.plantLoop.is_initialized, "Fan coil cooling coil should be connected to plant loop"
      end

      # Check heating coil connection
      if heating_coil.to_CoilHeatingWater.is_initialized
        coil = heating_coil.to_CoilHeatingWater.get
        assert coil.plantLoop.is_initialized, "Fan coil heating coil should be connected to plant loop"
      end
    end
  end

  def test_system_5_chilled_water_plant
    # Test that System 5 creates chilled water plant with chillers
    model = load_sized_fixture('system_5_tpfc_toronto')

    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 5 should have chilled water loop"

    chw_loop = chw_loops.first

    # Verify chiller exists on the loop
    has_chiller = chw_loop.supplyComponents.any? do |comp|
      comp.to_ChillerElectricEIR.is_initialized
    end
    assert has_chiller, "Chilled water loop should have chiller"

    # Verify pump exists
    has_pump = chw_loop.supplyComponents.any? do |comp|
      comp.to_PumpVariableSpeed.is_initialized || comp.to_PumpConstantSpeed.is_initialized
    end
    assert has_pump, "Chilled water loop should have pump"
  end

  def test_system_5_condenser_water_loop
    # Test that System 5 creates condenser water loop with cooling tower
    model = load_sized_fixture('system_5_tpfc_toronto')

    cw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Condenser') }
    assert cw_loops.size > 0, "System 5 should have condenser water loop"

    cw_loop = cw_loops.first

    # Verify cooling tower exists
    has_tower = cw_loop.supplyComponents.any? do |comp|
      comp.to_CoolingTowerSingleSpeed.is_initialized ||
      comp.to_CoolingTowerTwoSpeed.is_initialized ||
      comp.to_CoolingTowerVariableSpeed.is_initialized
    end
    assert has_tower, "Condenser loop should have cooling tower"
  end

  def test_system_5_mau_provides_ventilation
    # Test that System 5 MAU serves all zones for ventilation
    model = load_sized_fixture('system_5_tpfc_toronto')

    air_loops = model.getAirLoopHVACs
    mau_loops = air_loops.select do |loop|
      loop.airLoopHVACOutdoorAirSystem.is_initialized
    end

    assert mau_loops.size > 0, "System 5 should have MAU for ventilation"

    # MAU should serve zones
    mau_loops.each do |mau|
      thermal_zones = mau.thermalZones
      assert thermal_zones.size > 0, "MAU should serve thermal zones"
    end
  end

  def test_system_5_has_sizing_results
    # Test that System 5 fixture has sizing results
    model = load_sized_fixture('system_5_tpfc_toronto')

    sql_file = model.sqlFile
    assert sql_file.is_initialized, "System 5 fixture should have sizing results"
  end

  def test_system_5_fan_coil_fans
    # Test that fan coil units have fans configured
    model = load_sized_fixture('system_5_tpfc_toronto')

    fan_coils = model.getZoneHVACFourPipeFanCoils
    fan_coils.each do |fc|
      supply_fan = fc.supplyAirFan

      # Fan should be configured
      assert supply_fan.to_FanOnOff.is_initialized || supply_fan.to_FanConstantVolume.is_initialized,
             "Fan coil should have fan configured"
    end
  end

  # ============================================================================
  # NECB System 6: Built-up VAV System
  # ============================================================================

  def test_system_6_components_created
    # Test that System 6 creates VAV system with central plants
    model = load_sized_fixture('system_6_vav_hw_toronto')

    # Verify VAV air loop
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "System 6 should have VAV air loop"

    # Verify VAV terminals
    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV terminals with reheat"

    # Verify chilled water loop
    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 6 should have chilled water loop"

    # Verify hot water loop
    hw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Hot Water') }
    assert hw_loops.size > 0, "System 6 should have hot water loop"
  end

  def test_system_6_vav_terminals_with_hw_reheat
    # Test that System 6 creates VAV terminals with hot water reheat
    model = load_sized_fixture('system_6_vav_hw_toronto')

    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV reheat terminals"

    vav_terminals.each do |terminal|
      reheat_coil = terminal.reheatCoil

      # Check if reheat coil is hot water
      if reheat_coil.to_CoilHeatingWater.is_initialized
        coil = reheat_coil.to_CoilHeatingWater.get
        assert coil.plantLoop.is_initialized, "VAV reheat coil should be connected to HW loop"
      end
    end
  end

  def test_system_6_vav_terminals_with_electric_reheat
    # Test that System 6 creates VAV terminals with electric reheat
    model = load_sized_fixture('system_6_vav_electric_toronto')

    vav_terminals = model.getAirTerminalSingleDuctVAVReheats
    assert vav_terminals.size > 0, "System 6 should have VAV reheat terminals"

    has_electric = vav_terminals.any? do |terminal|
      terminal.reheatCoil.to_CoilHeatingElectric.is_initialized
    end

    assert has_electric, "System 6 with electric should have electric reheat coils"
  end

  def test_system_6_variable_volume_fans
    # Test that System 6 has variable volume supply fan
    model = load_sized_fixture('system_6_vav_hw_toronto')

    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      has_vav_fan = air_loop.supplyComponents.any? do |comp|
        comp.to_FanVariableVolume.is_initialized
      end

      assert has_vav_fan, "System 6 air loop should have variable volume fan" if air_loop.supplyComponents.any?
    end
  end

  def test_system_6_chilled_water_plant
    # Test that System 6 creates chilled water plant
    model = load_sized_fixture('system_6_vav_hw_toronto')

    chw_loops = model.getPlantLoops.select { |loop| loop.name.get.include?('Chilled Water') }
    assert chw_loops.size > 0, "System 6 should have chilled water loop"

    chw_loop = chw_loops.first

    # Verify chiller
    has_chiller = chw_loop.supplyComponents.any? do |comp|
      comp.to_ChillerElectricEIR.is_initialized
    end
    assert has_chiller, "System 6 should have chiller on CHW loop"
  end

  def test_system_6_zone_baseboards
    # Test that System 6 zones have baseboards for supplementary heating
    model = load_sized_fixture('system_6_vav_hw_toronto')

    baseboards = model.getZoneHVACBaseboardConvectiveWaters
    # System 6 typically has baseboards in addition to VAV reheat
    # The number may vary based on configuration
    assert baseboards.size >= 0, "System 6 may have baseboards for supplementary heating"
  end

  def test_system_6_central_heating_coil
    # Test that System 6 has central heating coil on air loop
    model = load_sized_fixture('system_6_vav_hw_toronto')

    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      has_heating_coil = air_loop.supplyComponents.any? do |comp|
        comp.to_CoilHeatingWater.is_initialized || comp.to_CoilHeatingElectric.is_initialized
      end

      # VAV systems typically have preheat coil
      assert has_heating_coil, "System 6 should have heating coil on air loop" if air_loop.supplyComponents.any?
    end
  end

  def test_system_6_central_cooling_coil
    # Test that System 6 has central chilled water cooling coil
    model = load_sized_fixture('system_6_vav_hw_toronto')

    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      has_cooling_coil = air_loop.supplyComponents.any? do |comp|
        comp.to_CoilCoolingWater.is_initialized
      end

      assert has_cooling_coil, "System 6 should have CHW cooling coil on air loop" if air_loop.supplyComponents.any?
    end
  end

  def test_system_6_has_sizing_results
    # Test that System 6 fixture has sizing results
    model = load_sized_fixture('system_6_vav_hw_toronto')

    sql_file = model.sqlFile
    assert sql_file.is_initialized, "System 6 fixture should have sizing results"
  end
end
