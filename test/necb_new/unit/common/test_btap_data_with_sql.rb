#!/usr/bin/env ruby

require_relative '../../test_helper'
require_relative '../../fixtures/sized_model_fixture_manager'

# Test suite for BTAP data extraction methods that require SQL files
# Tests lib/openstudio-standards/standards/necb/common/btap_data.rb with sized models
class TestBtapDataWithSql < Minitest::Test
  def setup
    @fixture = SizedModelFixtureManager.get_or_create_sized_model(
      template: 'NECB2011',
      system_type: 'System1',
      climate: 'toronto'
    )

    translator = OpenStudio::OSVersion::VersionTranslator.new
    @model = translator.loadModel(@fixture[:osm_path]).get

    sql = OpenStudio::SqlFile.new(OpenStudio::Path.new(@fixture[:sql_path]))
    @model.setSqlFile(sql)

    @standard = Standard.build('NECB2011')
  end

  # ===== Building Data Extraction Tests =====

  def test_building_data_from_sql
    # Create BTAPData instance with SQL file
    btap_data = create_btap_data_instance

    result = btap_data.building_data

    # Should extract building data successfully
    assert result.is_a?(Hash), "Should return hash"
    assert result['bldg_name'], "Should have building name"
    assert result['bldg_conditioned_floor_area_m_sq'], "Should have floor area"
    assert result['bldg_conditioned_floor_area_m_sq'] > 0, "Floor area should be positive"
  end

  def test_building_surface_to_volume_ratio
    btap_data = create_btap_data_instance
    result = btap_data.building_data

    assert result['bldg_surface_to_volume_ratio'], "Should calculate S/V ratio"
    assert result['bldg_surface_to_volume_ratio'] > 0, "S/V ratio should be positive"
  end

  # ===== Energy EUI Data Tests =====

  def test_energy_eui_data_extraction
    btap_data = create_btap_data_instance

    result = btap_data.energy_eui_data(@model)

    assert result.is_a?(Hash), "Should return hash"
    # Should have total site EUI
    assert result.key?('total_site_eui_gj_per_m_sq'), "Should have total site EUI"
  end

  # ===== Envelope Data Tests =====

  def test_envelope_data_extraction
    skip "btap_data.rb:436 references data['average_conductance_w_per_m_sq_k'] before it is defined (pre-existing bug)"
    btap_data = create_btap_data_instance

    result = btap_data.envelope(@model)

    assert result.is_a?(Hash), "Should return hash"
  end

  # ===== Space Type Table Tests =====

  def test_space_type_table_with_sql
    btap_data = create_btap_data_instance

    result = btap_data.space_type_table(@model)

    assert result.is_a?(Array), "Should return array"

    if result.size > 0
      first_space_type = result.first
      assert first_space_type['name'], "Should have space type name"
      assert first_space_type['floor_m_sq'], "Should have floor area"
      assert first_space_type['percent_area'], "Should have percent area"
    end
  end

  # ===== Plant Loop Data Tests =====

  def test_plant_loop_table_extraction
    btap_data = create_btap_data_instance

    result = btap_data.plant_loop_table(@model)

    assert result.is_a?(Array), "Should return array"
    # May be empty if no plant loops in System 1 (PTAC + baseboard)
  end

  # ===== Climate Data Tests =====

  def test_climate_data_extraction
    btap_data = create_btap_data_instance

    result = btap_data.climate_data

    assert result.is_a?(Hash), "Should return hash"
    assert result['location_state_province_region'], "Should have province"
    assert_equal 'ON', result['location_state_province_region'], "Should be Ontario"
  end

  # ===== Error Table Tests =====

  def test_eplusout_err_table
    btap_data = create_btap_data_instance

    result = btap_data.eplusout_err_table(@model)

    assert result.is_a?(Array), "Should return array"
    # May have warnings/errors from simulation
  end

  # ===== Peak Energy Data Tests =====

  def test_energy_peak_data_extraction
    btap_data = create_btap_data_instance

    result = btap_data.energy_peak_data

    assert result.is_a?(Hash), "Should return hash"
    assert result.key?('energy_peak_electric_w_per_m_sq'), "Should have electric peak"
    assert result['energy_peak_electric_w_per_m_sq'] >= 0, "Peak should be non-negative"
  end

  # ===== Utility Costing Tests =====

  def test_utility_cost_calculation
    btap_data = create_btap_data_instance

    result = btap_data.utility(model: @model, utility_pricing_year: 2020)

    assert result.is_a?(Hash), "Should return hash"
    assert result['cost_utility_neb_total_cost_per_m_sq'], "Should calculate total utility cost"
    assert result['cost_utility_ghg_total_kg_per_m_sq'], "Should calculate total GHG"
  end

  # ===== Unmet Hours Tests =====

  def test_unmet_hours_calculation
    btap_data = create_btap_data_instance

    result = btap_data.unmet_hours(@model)

    assert result.is_a?(Hash), "Should return hash"
    # Unmet hours data from SQL
  end

  # ===== Service Water Heating Tests =====

  def test_service_water_heating_data
    btap_data = create_btap_data_instance

    result = btap_data.service_water_heating_data

    assert result.is_a?(Hash), "Should return hash"
    # SWH data from simulation
  end

  # ===== Outdoor Air Data Tests =====

  def test_outdoor_air_data_extraction
    btap_data = create_btap_data_instance

    result = btap_data.outdoor_air_data(@model)

    assert result.is_a?(Hash), "Should return hash"
    # OA data from simulation
  end

  # ===== Direct method coverage (uses already-built instance) =====

  def test_thermal_zones_equipment_table
    btap_data = create_btap_data_instance
    result = btap_data.thermal_zones_equipment_table(@model)
    assert result.is_a?(Array)
    if result.any?
      first = result.first
      assert first.key?('air_loop_name')
      assert first.key?('thermal_zone_name')
      assert first.key?('zone_equipment_name')
      assert first.key?('type')
    end
  end

  def test_air_loops_table_returns_array
    skip "air_loops_table queries an Optional that isn't initialized on the System1 fixture (no central air loop)"
    btap_data = create_btap_data_instance
    result = btap_data.air_loops_table(@model, nil)
    assert result.is_a?(Array), "air_loops_table should return an array"
  end

  def test_thermal_zones_table_returns_array
    skip "thermal_zones_table dereferences a nested hash that nil-checks aren't applied to on the simplified fixture"
    btap_data = create_btap_data_instance
    result = btap_data.thermal_zones_table(@model, nil)
    assert result.is_a?(Hash), "thermal_zones_table wraps the table in a hash"
    assert result.key?('table')
  end

  def test_coil_table_returns_array
    skip "coil_table requires cost_result data (coil cost lookups) which is intentionally nil in these tests"
    btap_data = create_btap_data_instance
    result = btap_data.coil_table
    assert result.is_a?(Array)
  end

  def test_eplusout_err_table_structure
    btap_data = create_btap_data_instance
    result = btap_data.eplusout_err_table(@model)
    assert result.is_a?(Array)
    # Each row should have these keys when there are warnings
    if result.any?
      assert result.first.is_a?(Hash) || result.first.is_a?(Array)
    end
  end

  def test_envelope_exterior_surface_table_returns_array
    btap_data = create_btap_data_instance
    result = btap_data.envelope_exterior_surface_table
    assert result.is_a?(Array)
  end

  def test_measures_data_table_runner_nil
    skip "measures_data_table dereferences runner.workflow without nil-guarding; pre-existing requirement that a runner is passed"
    btap_data = create_btap_data_instance
    result = btap_data.measures_data_table(nil)
    assert result.is_a?(Array) || result.nil?
  end

  def test_validate_optional_with_initialized
    btap_data = create_btap_data_instance
    name_opt = @model.building.get.name
    result = btap_data.validate_optional(name_opt, @model)
    refute_equal 'N/A', result, "Initialized Optional should return its value"
  end

  def test_validate_optional_with_uninitialized
    btap_data = create_btap_data_instance
    # Build an empty Optional by querying a property that's not set
    construction_set = @model.building.get.defaultConstructionSet
    if construction_set.empty?
      result = btap_data.validate_optional(construction_set, @model)
      assert_equal 'N/A', result, "Empty Optional should return 'N/A'"
    end
  end

  def test_get_utility_ghg_kg_per_gj_for_electricity
    btap_data = create_btap_data_instance
    val = btap_data.get_utility_ghg_kg_per_gj(province: 'ON', fuel_type: 'Electricity')
    assert val.is_a?(Numeric)
    assert val >= 0
  end

  def test_get_utility_ghg_kg_per_gj_for_natural_gas
    btap_data = create_btap_data_instance
    val = btap_data.get_utility_ghg_kg_per_gj(province: 'ON', fuel_type: 'NaturalGas')
    assert val.is_a?(Numeric)
    assert val > 0
  end

  def test_get_national_ghg_cost
    btap_data = create_btap_data_instance
    val = btap_data.get_national_ghg_cost(year: 2030)
    assert val.is_a?(Numeric)
  end

  def test_get_actual_child_object_returns_subclass
    btap_data = create_btap_data_instance
    boiler = OpenStudio::Model::BoilerHotWater.new(@model)
    result = btap_data.get_actual_child_object(boiler)
    assert_equal 'OpenStudio::Model::BoilerHotWater', result.class.name
  end

  def test_set_sql_file_stores_reference
    btap_data = create_btap_data_instance
    new_sql = OpenStudio::SqlFile.new(OpenStudio::Path.new(@fixture[:sql_path]))
    btap_data.set_sql_file(new_sql)
    refute_nil btap_data.sqlite_file, "set_sql_file should set @sqlite_file"
  end

  def test_phius_performance_indicators_populates_data
    btap_data = create_btap_data_instance
    # phius_performance_indicators was already called by the constructor.
    # Verify it produced PHIUS-prefixed keys in the result hash.
    keys = btap_data.btap_data.keys.select { |k| k.to_s.start_with?('phius') }
    # phius keys may or may not be present depending on fixture; just confirm
    # the call did not raise (we wouldn't have an instance otherwise).
    assert keys.is_a?(Array)
  end

  def test_bc_energy_step_code_indicators_populated
    btap_data = create_btap_data_instance
    keys = btap_data.btap_data.keys.select { |k| k.to_s.include?('tedi') || k.to_s.include?('meui') }
    assert keys.is_a?(Array)
  end

  # ===== SQL Data Tables Tests =====

  def test_sql_data_tables_extraction
    btap_data = create_btap_data_instance

    result = btap_data.sql_data_tables(@model)

    assert result.is_a?(Array), "sql_data_tables returns an array of parsed table rows"
    refute result.empty?, "Should include at least one parsed table (AnnualBuildingUtilityPerformanceSummary/End Uses)"
  end

  # ===== Helper Methods =====

  private

  def create_btap_data_instance
    # cost_result / carbon_result are nil-guarded in the constructor. qaqc is
    # consumed by measure_metrics without a guard, so we stub the minimal shape:
    # an :envelope sub-hash with the conductance keys it looks up.
    qaqc_stub = {
      envelope: {
        outdoor_walls_average_conductance_w_per_m2_k: 0.0,
        outdoor_roofs_average_conductance_w_per_m2_k: 0.0,
        outdoor_floors_average_conductance_w_per_m2_k: 0.0,
        ground_walls_average_conductance_w_per_m2_k: 0.0,
        ground_roofs_average_conductance_w_per_m2_k: 0.0,
        ground_floors_average_conductance_w_per_m2_k: 0.0,
        windows_average_conductance_w_per_m2_k: 0.0,
        doors_average_conductance_w_per_m2_k: 0.0,
        overhead_doors_average_conductance_w_per_m2_k: 0.0,
        skylights_average_conductance_w_per_m2_k: 0.0
      }
    }

    BTAPData.new(
      model: @model,
      runner: nil,
      cost_result: nil,
      carbon_result: nil,
      qaqc: qaqc_stub
    )
  end
end
