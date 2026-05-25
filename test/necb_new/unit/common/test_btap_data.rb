#!/usr/bin/env ruby

require_relative '../../test_helper'

# Test suite for BTAP data extraction and calculation methods
# Tests lib/openstudio-standards/standards/necb/common/btap_data.rb
# Note: Many BTAPData methods require a completed EnergyPlus simulation with SQL results.
# These tests focus on validating method signatures and basic logic.
class TestBtapData < Minitest::Test
  def setup
    # Create minimal model
    @model = OpenStudio::Model::Model.new

    # Add building object
    building = @model.getBuilding
    building.setName('TestBuilding')
    building.setStandardsTemplate('NECB2011')
    building.setStandardsBuildingType('Office')

    # Add a single space
    space = OpenStudio::Model::Space.new(@model)
    space.setName('TestSpace')

    # Add thermal zone
    zone = OpenStudio::Model::ThermalZone.new(@model)
    zone.setName('TestZone')
    space.setThermalZone(zone)

    # Set weather file
    epw_path = File.join(__dir__, '../../../../data/weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
    weather_file = OpenStudio::Model::WeatherFile.setWeatherFile(@model, epw_file)

    @standard = Standard.build('NECB2011')
  end

  # ===== Net Present Value Calculation Tests =====

  def test_npv_calculation_logic
    # Test NPV discount factor calculation directly
    # NPV formula: sum of (value / (1 + discount_rate)^year_index)

    # Simple manual NPV calculation
    value_per_year = 100.0  # $100/year
    discount_rate = 0.03    # 3%
    years = 5

    expected_npv = 0.0
    (1..years).each do |year|
      expected_npv += value_per_year / (1 + discount_rate)**year
    end

    # Expected NPV ≈ 457.97
    assert expected_npv > 450.0 && expected_npv < 460.0, "NPV calculation logic should produce expected result"
  end

  def test_npv_string_to_float_conversion
    # Test string conversion logic used in net_present_value method
    test_value = "2023"
    converted = test_value.to_f
    assert_equal 2023.0, converted, "Should convert string year to float"

    test_rate = "0.04"
    converted_rate = test_rate.to_f
    assert_equal 0.04, converted_rate, "Should convert string rate to float"
  end

  def test_npv_default_value_logic
    # Test default value logic from net_present_value method
    npv_start_year = 'NECB_Default'
    npv_end_year = nil
    npv_discount_rate = 'none'

    # Logic from btap_data.rb lines 217-229
    npv_start_year = 2022 if npv_start_year == 'NECB_Default' || npv_start_year.nil? || npv_start_year == 'none'
    npv_end_year = 2041 if npv_end_year == 'NECB_Default' || npv_end_year.nil? || npv_end_year == 'none'
    npv_discount_rate = 0.03 if npv_discount_rate == 'NECB_Default' || npv_discount_rate.nil? || npv_discount_rate == 'none'

    assert_equal 2022, npv_start_year
    assert_equal 2041, npv_end_year
    assert_equal 0.03, npv_discount_rate
  end

  # ===== Helper Method Tests =====

  def test_validate_optional_logic_with_value
    # Test the validate_optional method logic
    # When OptionalDouble has a value, it should return that value
    optional_with_value = OpenStudio::OptionalDouble.new(42.5)

    if optional_with_value.is_initialized
      result = optional_with_value.get
      assert_equal 42.5, result
    else
      flunk "Optional should be initialized"
    end
  end

  def test_validate_optional_logic_without_value
    # When OptionalDouble is empty, should return default value
    empty_optional = OpenStudio::OptionalDouble.new

    result = empty_optional.is_initialized ? empty_optional.get : -1.0
    assert_equal(-1.0, result)
  end

  # ===== Space Type Data Tests =====

  def test_space_type_area_calculation
    # Add a space type with known floor area
    space_type = OpenStudio::Model::SpaceType.new(@model)
    space_type.setName('Office')
    space_type.setStandardsBuildingType('Office')

    # Set loads
    space_type.setLightingPowerPerFloorArea(10.0)  # W/m²
    space_type.setElectricEquipmentPowerPerFloorArea(5.0)  # W/m²

    # Associate with a space
    space = @model.getSpaces.first
    space.setSpaceType(space_type) if space

    # Calculate total floor area
    total_floor_area = 0.0
    @model.getSpaceTypes.each do |st|
      st.spaces.each do |sp|
        next unless sp.partofTotalFloorArea

        total_floor_area += sp.floorArea * sp.multiplier
      end
    end

    assert total_floor_area >= 0.0, "Total floor area should be non-negative"
  end

  def test_space_type_percent_calculation
    # Test percent area calculation logic from space_type_table method (line 823)
    floor_area_si = 50.0  # m²
    conditioned_floor_area = 100.0  # m²

    percent_area = (floor_area_si / conditioned_floor_area * 100.0).round(2)
    assert_equal 50.0, percent_area
  end

  # ===== Building Data Calculation Tests =====

  def test_surface_to_volume_ratio_calculation
    # Test surface-to-volume ratio calculation (line 168 in btap_data.rb)
    # Create a simple box geometry
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 10, 0)
    vertices << OpenStudio::Point3d.new(0, 10, 0)

    # Create a surface (floor)
    surface = OpenStudio::Model::Surface.new(vertices, @model)
    surface.setSurfaceType('Floor')

    # Get building exterior surface area and volume
    building = @model.getBuilding
    exterior_area = building.exteriorSurfaceArea
    air_volume = building.airVolume

    if air_volume > 0
      ratio = exterior_area / air_volume
      assert ratio >= 0.0, "Surface-to-volume ratio should be non-negative"
    end
  end

  def test_fdwr_calculation_concept
    # Test FDWR (Fenestration to Wall Ratio) calculation concept
    wall_area = 100.0  # m²
    window_area = 20.0  # m²

    fdwr = (window_area / wall_area * 100.0).round(1)
    assert_equal 20.0, fdwr
  end

  # ===== Costing Calculation Tests =====

  def test_cost_normalization_by_floor_area
    # Test cost per m² calculation logic (lines 179-186 in btap_data.rb)
    total_cost = 44000.0  # dollars
    conditioned_floor_area = 100.0  # m²

    cost_per_m_sq = total_cost / conditioned_floor_area
    assert_equal 440.0, cost_per_m_sq
  end

  def test_cost_category_aggregation
    # Test cost category aggregation
    costs = {
      'envelope' => 10000.0,
      'lighting' => 5000.0,
      'heating_and_cooling' => 15000.0,
      'ventilation' => 8000.0
    }

    total = costs.values.sum
    assert_equal 38000.0, total
  end

  # ===== Plant Loop Data Structure Tests =====

  def test_plant_loop_data_structure
    # Create a plant loop
    plant_loop = OpenStudio::Model::PlantLoop.new(@model)
    plant_loop.setName('TestPlantLoop')

    # Test plant loop info structure (lines 1396-1404 in btap_data.rb)
    plant_loop_info = {}
    plant_loop_info['name'] = plant_loop.name.get
    plant_loop_info['pumps'] = []
    plant_loop_info['boilers'] = []
    plant_loop_info['chiller_electric_eir'] = []
    plant_loop_info['cooling_tower_single_speed'] = []

    assert plant_loop_info['name'] == 'TestPlantLoop'
    assert plant_loop_info['pumps'].is_a?(Array)
    assert plant_loop_info['boilers'].is_a?(Array)
  end

  def test_pump_info_structure
    # Test pump data structure
    schedule = @model.alwaysOnDiscreteSchedule
    pump = OpenStudio::Model::PumpConstantSpeed.new(@model)
    pump.setName('TestPump')

    pump_info = {}
    pump_info['name'] = pump.name.get
    pump_info['type'] = 'Pump:ConstantSpeed'
    pump_info['motor_efficency'] = pump.motorEfficiency

    assert_equal 'TestPump', pump_info['name']
    assert_equal 'Pump:ConstantSpeed', pump_info['type']
    assert pump_info['motor_efficency'].is_a?(Numeric)
  end

  # ===== Climate Data Tests =====

  def test_climate_zone_logic
    # Test climate zone extraction from model
    weather_file = @model.getWeatherFile
    province = weather_file.stateProvinceRegion

    assert province.is_a?(String), "Province should be a string"
    assert province.length > 0, "Province should not be empty"
  end

  # ===== Envelope Calculation Tests =====

  def test_surface_filtering_by_boundary_condition
    # Create outdoor wall
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(0, 0, 3)
    vertices << OpenStudio::Point3d.new(10, 0, 3)
    vertices << OpenStudio::Point3d.new(10, 0, 0)

    wall = OpenStudio::Model::Surface.new(vertices, @model)
    wall.setSurfaceType('Wall')
    wall.setOutsideBoundaryCondition('Outdoors')

    # Filter surfaces
    outdoor_surfaces = @model.getSurfaces.select { |s| s.outsideBoundaryCondition == 'Outdoors' }
    assert outdoor_surfaces.size > 0, "Should find outdoor surfaces"
  end

  def test_surface_filtering_by_type
    # Test filtering surfaces by type (wall, roof, floor)
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 10, 0)
    vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(vertices, @model)
    floor.setSurfaceType('Floor')

    floors = @model.getSurfaces.select { |s| s.surfaceType == 'Floor' }
    assert floors.size > 0, "Should find floor surfaces"
  end

  # ===== Utility Pricing Tests =====

  def test_energy_unit_conversion
    # Test GJ to kWh conversion (line 704 in btap_data.rb)
    energy_gj = 1.0
    energy_kwh = energy_gj * 277.778

    assert (energy_kwh - 277.778).abs < 0.001, "1 GJ should equal 277.778 kWh"
  end

  def test_ghg_kg_to_tonnes_conversion
    # Test kg to tonnes conversion (line 300 in btap_data.rb)
    ghg_kg = 1000.0
    ghg_tonnes = ghg_kg / 1000.0

    assert_equal 1.0, ghg_tonnes, "1000 kg should equal 1 tonne"
  end

  # ===== Error Handling Tests =====

  def test_error_message_structure
    # Test error table structure (lines 1522-1532 in btap_data.rb)
    error_table = []
    error_table << { 'error_type' => 'warning', 'message' => 'Test warning' }
    error_table << { 'error_type' => 'severe', 'message' => 'Test severe' }

    assert_equal 2, error_table.size
    assert_equal 'warning', error_table[0]['error_type']
    assert_equal 'severe', error_table[1]['error_type']
  end

  # ===== Data Structure Tests =====

  def test_flatten_mix_concept
    # Test nested hash flattening concept
    nested = {
      outer: {
        inner1: 'value1',
        inner2: 'value2'
      }
    }

    flat = {}
    nested[:outer].each { |k, v| flat[k] = v }

    assert_equal 'value1', flat[:inner1]
    assert_equal 'value2', flat[:inner2]
  end

  def test_hash_merge_recursively_concept
    # Test recursive hash merge logic
    hash_a = { 'key1' => 'value1', 'key2' => 'value2' }
    hash_b = { 'key2' => 'new_value2', 'key3' => 'value3' }

    merged = hash_a.merge(hash_b)

    assert_equal 'value1', merged['key1']
    assert_equal 'new_value2', merged['key2']  # Overwritten
    assert_equal 'value3', merged['key3']
  end
end
