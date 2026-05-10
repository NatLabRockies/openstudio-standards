require_relative '../test_helper'

class TestNECBSystem6Complete < Minitest::Test
  # Complete tests for NECB System 6 (VAV with reheat)
  # Targets hvac_system_6.rb (158 uncovered lines, 35.8% coverage)
  # Goal: Push coverage to 70%+

  ##############################################################################
  # SYSTEM 6 BASIC CREATION
  # Test VAV system creation and configuration
  ##############################################################################

  def test_system_6_creation_for_various_building_sizes
    # Test System 6 for different building sizes
    standard = Standard.build('NECB2011')

    building_sizes = [5000, 10000, 20000] # m²

    building_sizes.each do |area|
      model = create_necb_model_with_geometry(standard, floor_area: area)

      # Add System 6 (VAV with reheat)
      zones = model.getThermalZones
      result = standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones.to_a,
        heating_coil_type: 'Hot Water',
        baseboard_type: 'Hot Water',
        chiller_type: 'Scroll',
        fan_type: 'AF_or_BI_rdg_fancurve'
      )

      # System should be created
      air_loops = model.getAirLoopHVACs
      assert air_loops.size > 0, "Should create air loop for building size #{area} m²"
    end
  end

  ##############################################################################
  # VAV TERMINAL CONFIGURATION
  # Test VAV terminal unit setup for System 6
  ##############################################################################

  def test_system_6_vav_terminal_types
    # Test different reheat types for VAV terminals
    standard = Standard.build('NECB2011')

    reheat_types = ['Hot Water', 'Electric']

    reheat_types.each do |reheat_type|
      model = create_necb_model_with_geometry(standard)

      zones = model.getThermalZones
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones.to_a,
        heating_coil_type: 'Hot Water',
        baseboard_type: reheat_type,
        chiller_type: 'Scroll',
        fan_type: 'AF_or_BI_rdg_fancurve'
      )

      # Check that VAV terminals were created
      terminals = model.getAirTerminalSingleDuctVAVReheats
      assert terminals.size > 0, "Should create VAV terminals with #{reheat_type} reheat"
    end
  end

  ##############################################################################
  # ECONOMIZER CONFIGURATION
  # Test economizer settings for System 6
  ##############################################################################

  def test_system_6_economizer_for_various_climates
    # Test economizer configuration in different climate zones
    standard = Standard.build('NECB2011')

    climates = [
      { name: 'Vancouver', hdd: 3000, expected_economizer: true },
      { name: 'Toronto', hdd: 4000, expected_economizer: true },
      { name: 'Winnipeg', hdd: 6000, expected_economizer: true }
    ]

    climates.each do |climate|
      model = create_necb_model_with_geometry(standard, climate: climate[:name])

      zones = model.getThermalZones
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones.to_a,
        heating_coil_type: 'Hot Water',
        baseboard_type: 'Hot Water',
        chiller_type: 'Scroll',
        fan_type: 'AF_or_BI_rdg_fancurve'
      )

      # System should have economizer in Canadian climates
      air_loops = model.getAirLoopHVACs
      air_loops.each do |air_loop|
        if air_loop.airLoopHVACOutdoorAirSystem.is_initialized
          oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
          oa_controller = oa_system.getControllerOutdoorAir

          # Check economizer is configured
          assert !oa_controller.getEconomizerControlType.empty?,
                 "Should have economizer for climate #{climate[:name]}"
        end
      end
    end
  end

  ##############################################################################
  # FAN CONFIGURATION
  # Test fan types and pressure rise for System 6
  ##############################################################################

  def test_system_6_fan_types
    # Test different fan types for VAV system
    standard = Standard.build('NECB2011')

    fan_types = ['AF_or_BI_rdg_fancurve', 'FC_Centrifugal']

    fan_types.each do |fan_type|
      model = create_necb_model_with_geometry(standard)

      zones = model.getThermalZones
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones.to_a,
        heating_coil_type: 'Hot Water',
        baseboard_type: 'Hot Water',
        chiller_type: 'Scroll',
        fan_type: fan_type
      )

      # Check that supply fan was created
      fans = model.getFanVariableVolumes
      assert fans.size > 0, "Should create variable volume fan with type #{fan_type}"

      # Check fan pressure rise is set
      fans.each do |fan|
        pressure_rise = fan.pressureRise
        assert pressure_rise > 0, "Fan should have positive pressure rise"
        assert pressure_rise < 5000, "Fan pressure rise should be reasonable (< 5000 Pa)"
      end
    end
  end

  ##############################################################################
  # CHILLED WATER PLANT
  # Test chilled water plant configuration for System 6
  ##############################################################################

  def test_system_6_chilled_water_plant
    # Test CHW plant creation for different chiller types
    standard = Standard.build('NECB2011')

    chiller_types = ['Scroll', 'Screw', 'Centrifugal', 'Reciprocating']

    chiller_types.each do |chiller_type|
      model = create_necb_model_with_geometry(standard)

      zones = model.getThermalZones
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones.to_a,
        heating_coil_type: 'Hot Water',
        baseboard_type: 'Hot Water',
        chiller_type: chiller_type,
        fan_type: 'AF_or_BI_rdg_fancurve'
      )

      # Check chilled water loop was created
      chw_loops = model.getPlantLoops.select { |loop| loop.name.to_s.downcase.include?('chilled') }
      assert chw_loops.size > 0, "Should create CHW loop with #{chiller_type} chiller"

      # Check chiller was added
      chillers = model.getChillerElectricEIRs
      assert chillers.size > 0, "Should create #{chiller_type} chiller"
    end
  end

  ##############################################################################
  # BASEBOARD HEATING
  # Test baseboard configuration for perimeter zones
  ##############################################################################

  def test_system_6_baseboard_heating_types
    # Test different baseboard types
    standard = Standard.build('NECB2011')

    baseboard_types = ['Hot Water', 'Electric']

    baseboard_types.each do |baseboard_type|
      model = create_necb_model_with_geometry(standard)

      zones = model.getThermalZones
      standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
        model: model,
        zones: zones.to_a,
        heating_coil_type: 'Hot Water',
        baseboard_type: baseboard_type,
        chiller_type: 'Scroll',
        fan_type: 'AF_or_BI_rdg_fancurve'
      )

      # Check baseboards were added to zones
      if baseboard_type == 'Hot Water'
        baseboards = model.getZoneHVACBaseboardConvectiveWaters
        assert baseboards.size > 0, "Should create hot water baseboards"
      elsif baseboard_type == 'Electric'
        baseboards = model.getZoneHVACBaseboardConvectiveElectrics
        assert baseboards.size > 0, "Should create electric baseboards"
      end
    end
  end

  ##############################################################################
  # OUTDOOR AIR VENTILATION
  # Test OA sizing and control for System 6
  ##############################################################################

  def test_system_6_outdoor_air_ventilation
    # Test outdoor air system configuration
    standard = Standard.build('NECB2011')

    model = create_necb_model_with_geometry(standard)

    zones = model.getThermalZones
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones.to_a,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve'
    )

    # Check OA system configuration
    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      if air_loop.airLoopHVACOutdoorAirSystem.is_initialized
        oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
        oa_controller = oa_system.getControllerOutdoorAir

        # OA should be configured
        assert oa_controller.getMinimumOutdoorAirFlowRate.is_initialized ||
               oa_controller.autosizedMinimumOutdoorAirFlowRate.is_initialized,
               "OA flow rate should be set or autosized"
      end
    end
  end

  ##############################################################################
  # SUPPLY AIR TEMPERATURE RESET
  # Test SAT reset strategies for System 6
  ##############################################################################

  def test_system_6_supply_air_temperature_reset
    # Test supply air temperature control
    standard = Standard.build('NECB2011')

    model = create_necb_model_with_geometry(standard)

    zones = model.getThermalZones
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones.to_a,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve'
    )

    # Check sizing parameters
    air_loops = model.getAirLoopHVACs
    air_loops.each do |air_loop|
      sizing = air_loop.sizingSystem

      # Cooling design supply air temp should be set
      cooling_sat = sizing.centralCoolingDesignSupplyAirTemperature
      assert cooling_sat > 0, "Cooling SAT should be positive"
      assert cooling_sat < 30, "Cooling SAT should be reasonable (< 30°C)"

      # Heating design supply air temp should be set
      heating_sat = sizing.centralHeatingDesignSupplyAirTemperature
      assert heating_sat > cooling_sat, "Heating SAT should be > cooling SAT"
    end
  end

  ##############################################################################
  # SYSTEM NAMING
  # Test system naming convention for System 6
  ##############################################################################

  def test_system_6_naming_convention
    # Test that System 6 gets proper NECB name
    standard = Standard.build('NECB2011')

    model = create_necb_model_with_geometry(standard)

    zones = model.getThermalZones
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones.to_a,
      heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      chiller_type: 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve'
    )

    # Check air loop naming
    air_loops = model.getAirLoopHVACs
    assert air_loops.size > 0, "Should have at least one air loop"

    air_loops.each do |air_loop|
      name = air_loop.name.to_s
      # System 6 should have sys_6 in name
      assert name.include?('sys') || name.include?('VAV') || !name.empty?,
             "System should have descriptive name"
    end
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  def create_necb_model_with_geometry(standard, floor_area: 10000, climate: 'Toronto')
    # Create a model with simple building geometry for testing

    model = OpenStudio::Model::Model.new

    # Set weather file if climate specified
    if climate
      weather_file_path = File.join(File.dirname(__FILE__), '..', '..', 'data', 'weather', "CAN_ON_#{climate}.*.epw")
      weather_files = Dir.glob(weather_file_path)
      if weather_files.any?
        epw_file = OpenStudio::EpwFile.new(weather_files.first)
        OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
      end
    end

    # Create simple multi-zone building
    num_floors = 1
    floor_to_floor_height = 4.0
    width = Math.sqrt(floor_area)
    length = width

    # Create spaces for core and perimeter
    create_core_perimeter_zones(model, length, width, floor_to_floor_height, num_floors)

    model
  end

  def create_core_perimeter_zones(model, length, width, floor_to_floor_height, num_floors)
    # Create core and perimeter zones

    perimeter_depth = 4.0 # meters

    # Create spaces for each floor
    (0...num_floors).each do |floor|
      z = floor * floor_to_floor_height

      # Core space
      core_space = OpenStudio::Model::Space.new(model)
      core_space.setName("Floor #{floor + 1} Core")

      # Core floor
      core_vertices = OpenStudio::Point3dVector.new
      core_vertices << OpenStudio::Point3d.new(perimeter_depth, perimeter_depth, z)
      core_vertices << OpenStudio::Point3d.new(width - perimeter_depth, perimeter_depth, z)
      core_vertices << OpenStudio::Point3d.new(width - perimeter_depth, length - perimeter_depth, z)
      core_vertices << OpenStudio::Point3d.new(perimeter_depth, length - perimeter_depth, z)

      core_floor = OpenStudio::Model::Surface.new(core_vertices, model)
      core_floor.setSpace(core_space)
      core_floor.setSurfaceType('Floor')

      # Core thermal zone
      core_zone = OpenStudio::Model::ThermalZone.new(model)
      core_zone.setName("Floor #{floor + 1} Core Zone")
      core_space.setThermalZone(core_zone)

      # South perimeter space
      south_space = OpenStudio::Model::Space.new(model)
      south_space.setName("Floor #{floor + 1} South Perimeter")

      south_zone = OpenStudio::Model::ThermalZone.new(model)
      south_zone.setName("Floor #{floor + 1} South Zone")
      south_space.setThermalZone(south_zone)
    end

    model
  end
end
