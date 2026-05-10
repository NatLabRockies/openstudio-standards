require_relative '../test_helper'

class TestTerminalUnits < Minitest::Test
  # Helper method to create a simple model with thermal zones
  def create_model_with_zones(num_zones: 1)
    model = OpenStudio::Model::Model.new

    # Create thermal zones
    zones = []
    num_zones.times do |i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone_#{i+1}")

      # Create a simple space and assign to zone
      space = OpenStudio::Model::Space.new(model)
      space.setName("Space_#{i+1}")
      space.setThermalZone(zone)

      zones << zone
    end

    return model, zones
  end

  def test_vav_terminal_with_electric_reheat
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_System")

    # Create VAV terminal with electric reheat
    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("VAV_Terminal_Zone1_Electric_Reheat")

    # Add to air loop and zone
    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Verify terminal created
    terminals = zone.airLoopHVACTerminals
    assert_equal 1, terminals.size, "Zone should have 1 terminal"

    # Verify it's a VAV reheat terminal
    vav_terminal = terminals.first.to_AirTerminalSingleDuctVAVReheat
    assert vav_terminal.is_initialized, "Terminal should be VAV reheat type"

    # Verify reheat coil is electric
    terminal_obj = vav_terminal.get
    coil = terminal_obj.reheatCoil
    assert coil.to_CoilHeatingElectric.is_initialized, "Reheat coil should be electric"
  end

  def test_vav_terminal_with_hw_reheat
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first

    # Create hot water plant loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName("Hot Water Loop")

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_System_HW")

    # Create VAV terminal with hot water reheat
    reheat_coil = OpenStudio::Model::CoilHeatingWater.new(model)
    hw_loop.addDemandBranchForComponent(reheat_coil)

    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("VAV_Terminal_Zone1_HW_Reheat")
    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Verify hot water connection
    coil = terminal.reheatCoil
    assert coil.to_CoilHeatingWater.is_initialized, "Reheat coil should be hot water"

    hw_coil = coil.to_CoilHeatingWater.get
    plant_loop = hw_coil.plantLoop
    assert plant_loop.is_initialized, "HW reheat coil should be connected to plant loop"
    assert_equal hw_loop, plant_loop.get, "Reheat coil should be on the hot water loop"
  end

  def test_vav_terminal_damper_configuration
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_Damper_Test")

    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("VAV_Terminal_Damper_Test")
    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Configure damper settings
    terminal.setConstantMinimumAirFlowFraction(0.3)
    assert_equal 0.3, terminal.constantMinimumAirFlowFraction.get, "Min flow fraction should be 0.3"

    # Test damper action type
    terminal.setDamperHeatingAction('Normal')
    assert_equal 'Normal', terminal.damperHeatingAction, "Damper action should be Normal"

    # Test zone minimum air flow method
    terminal.setZoneMinimumAirFlowInputMethod('Constant')
    assert_equal 'Constant', terminal.zoneMinimumAirFlowInputMethod, "Min flow method should be Constant"
  end

  def test_multiple_terminals_on_air_loop
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 3)

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_Multi_Zone")

    # Add terminals for first 3 zones
    zones[0..2].each_with_index do |zone, i|
      reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
      terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
      terminal.setName("VAV_Terminal_Zone_#{i+1}")
      air_loop.addBranchForZone(zone, terminal.to_StraightComponent)
    end

    # Verify all terminals created
    assert_equal 3, air_loop.thermalZones.size, "Air loop should serve 3 zones"

    # Verify each zone has a terminal
    zones[0..2].each do |zone|
      terminals = zone.airLoopHVACTerminals
      assert_equal 1, terminals.size, "Each zone should have 1 terminal"
      assert terminals.first.to_AirTerminalSingleDuctVAVReheat.is_initialized, "Terminal should be VAV type"
    end
  end

  def test_terminal_naming_conventions
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first
    zone_name = zone.name.get

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_System_Naming")

    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    reheat_coil.setName("#{zone_name}_Reheat_Coil")

    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("#{zone_name}_VAV_Terminal")
    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Verify naming
    assert terminal.name.is_initialized, "Terminal should have a name"
    assert_match(/VAV_Terminal/, terminal.name.get, "Terminal name should contain 'VAV_Terminal'")

    coil = terminal.reheatCoil.to_CoilHeatingElectric.get
    assert coil.name.is_initialized, "Reheat coil should have a name"
    assert_match(/Reheat_Coil/, coil.name.get, "Reheat coil name should contain 'Reheat_Coil'")
  end

  def test_necb_system_2_typical_configuration
    # System 2: VAV system with PFP boxes and electric reheat (small buildings)
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first

    # Create air loop for System 2
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("NECB_System_2")

    # System 2 uses electric reheat
    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("System_2_VAV_Terminal")

    # Typical System 2 damper configuration
    terminal.setConstantMinimumAirFlowFraction(0.3)
    terminal.setDamperHeatingAction('Normal')

    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Verify System 2 configuration
    assert zone.airLoopHVACTerminals.size == 1, "Zone should have terminal"
    vav_terminal = zone.airLoopHVACTerminals.first.to_AirTerminalSingleDuctVAVReheat.get

    assert_equal 0.3, vav_terminal.constantMinimumAirFlowFraction.get, "System 2 should have 0.3 min flow"
    assert vav_terminal.reheatCoil.to_CoilHeatingElectric.is_initialized, "System 2 uses electric reheat"
  end

  def test_necb_system_5_typical_configuration
    # System 5: Packaged VAV with boiler and HW reheat (larger buildings)
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first

    # Create hot water plant loop for System 5
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName("System_5_HW_Loop")

    # Create air loop for System 5
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("NECB_System_5")

    # System 5 uses hot water reheat
    reheat_coil = OpenStudio::Model::CoilHeatingWater.new(model)
    hw_loop.addDemandBranchForComponent(reheat_coil)

    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("System_5_VAV_Terminal")

    # Typical System 5 damper configuration
    terminal.setConstantMinimumAirFlowFraction(0.3)
    terminal.setDamperHeatingAction('Normal')

    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Verify System 5 configuration
    assert zone.airLoopHVACTerminals.size == 1, "Zone should have terminal"
    vav_terminal = zone.airLoopHVACTerminals.first.to_AirTerminalSingleDuctVAVReheat.get

    assert_equal 0.3, vav_terminal.constantMinimumAirFlowFraction.get, "System 5 should have 0.3 min flow"
    assert vav_terminal.reheatCoil.to_CoilHeatingWater.is_initialized, "System 5 uses HW reheat"

    hw_coil = vav_terminal.reheatCoil.to_CoilHeatingWater.get
    assert hw_coil.plantLoop.is_initialized, "HW coil should be on plant loop"
  end

  def test_different_necb_vintages_terminal_configuration
    # Test that different NECB vintages can create terminals
    vintages = ['NECB2011', 'NECB2015', 'NECB2017']

    vintages.each do |vintage|
      standard = Standard.build(vintage)
      model, zones = create_model_with_zones(num_zones: 1)
      zone = zones.first
      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
      air_loop.setName("#{vintage}_VAV")

      reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
      terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
      terminal.setName("#{vintage}_Terminal")

      air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

      # Verify terminal created for each vintage
      assert zone.airLoopHVACTerminals.size == 1, "#{vintage} should create terminal"
      vav_terminal = zone.airLoopHVACTerminals.first.to_AirTerminalSingleDuctVAVReheat
      assert vav_terminal.is_initialized, "#{vintage} terminal should be VAV type"
    end
  end

  def test_vav_terminal_maximum_flow_configuration
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 1)
    zone = zones.first
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_Max_Flow_Test")

    reheat_coil = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil)
    terminal.setName("VAV_Terminal_Max_Flow")
    air_loop.addBranchForZone(zone, terminal.to_StraightComponent)

    # Configure maximum flow settings
    # Can set maximum air flow rate (in m3/s) or leave autosized
    terminal.setMaximumFlowPerZoneFloorAreaDuringReheat(0.002) # m3/s-m2
    assert_equal 0.002, terminal.maximumFlowPerZoneFloorAreaDuringReheat.get, "Max flow per area should be 0.002"

    # Configure maximum damper position
    terminal.setMaximumFlowFractionDuringReheat(0.5)
    assert_equal 0.5, terminal.maximumFlowFractionDuringReheat.get, "Max flow fraction during reheat should be 0.5"
  end

  def test_vav_terminal_with_mixed_reheat_types
    # Test air loop with both electric and HW reheat terminals
    standard = Standard.build('NECB2011')
    model, zones = create_model_with_zones(num_zones: 2)

    # Create hot water loop
    hw_loop = OpenStudio::Model::PlantLoop.new(model)
    hw_loop.setName("Mixed_System_HW_Loop")

    # Create air loop
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName("VAV_Mixed_Reheat")

    # Zone 1: Electric reheat
    reheat_coil_1 = OpenStudio::Model::CoilHeatingElectric.new(model)
    terminal_1 = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil_1)
    terminal_1.setName("VAV_Electric_Reheat")
    air_loop.addBranchForZone(zones[0], terminal_1.to_StraightComponent)

    # Zone 2: Hot water reheat
    reheat_coil_2 = OpenStudio::Model::CoilHeatingWater.new(model)
    hw_loop.addDemandBranchForComponent(reheat_coil_2)
    terminal_2 = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, reheat_coil_2)
    terminal_2.setName("VAV_HW_Reheat")
    air_loop.addBranchForZone(zones[1], terminal_2.to_StraightComponent)

    # Verify mixed configuration
    assert_equal 2, air_loop.thermalZones.size, "Air loop should serve 2 zones"

    # Verify first terminal has electric reheat
    term_1 = zones[0].airLoopHVACTerminals.first.to_AirTerminalSingleDuctVAVReheat.get
    assert term_1.reheatCoil.to_CoilHeatingElectric.is_initialized, "First terminal should have electric reheat"

    # Verify second terminal has HW reheat
    term_2 = zones[1].airLoopHVACTerminals.first.to_AirTerminalSingleDuctVAVReheat.get
    assert term_2.reheatCoil.to_CoilHeatingWater.is_initialized, "Second terminal should have HW reheat"
  end
end
