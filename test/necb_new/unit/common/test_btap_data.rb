require_relative '../../test_helper'
require_relative '../../fixtures/sized_model_fixture_manager'

# Test suite for BTAP data extraction methods that require SQL files
# Tests lib/openstudio-standards/standards/necb/common/btap_data.rb with sized models
class TestBtapData < Minitest::Test

  # Building Data Extraction Tests
  def test_btap_data_attributes
    fixture = SizedModelFixtureManager.get_or_create_sized_model(
      template: 'NECB2011',
      system_type: 'System1',
      climate: 'toronto')

    model = OpenStudio::OSVersion::VersionTranslator.new.loadModel(fixture[:osm_path]).get
    model.setSqlFile(OpenStudio::SqlFile.new(OpenStudio::Path.new(fixture[:sql_path])))

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

    btap_data = BTAPData.new(
      model: model,
      runner: nil,
      cost_result: nil,
      carbon_result: nil,
      qaqc: qaqc_stub)

    assert btap_data.building_data.is_a?(Hash), "Should return hash"
    assert btap_data.building_data['bldg_name'], "Should have building name"
    assert btap_data.building_data['bldg_conditioned_floor_area_m_sq'], "Should have floor area"
    assert btap_data.building_data['bldg_conditioned_floor_area_m_sq'] > 0, "Floor area should be positive"
    assert btap_data.building_data['bldg_surface_to_volume_ratio'], "Should calculate S/V ratio"
    assert btap_data.building_data['bldg_surface_to_volume_ratio'] > 0, "S/V ratio should be positive"
    assert btap_data.building_data.is_a?(Hash), "Should return hash"

    assert btap_data.energy_eui_data(model).key?('total_site_eui_gj_per_m_sq'), "Should have total site EUI"

    assert btap_data.plant_loop_table(model).is_a?(Array), "Should return array"

    assert btap_data.climate_data.is_a?(Hash), "Should return hash"
    assert btap_data.climate_data['location_state_province_region'], "Should have province"

    assert btap_data.energy_peak_data.is_a?(Hash), "Should return hash"
    assert btap_data.energy_peak_data.key?('energy_peak_electric_w_per_m_sq'), "Should have electric peak"
    assert btap_data.energy_peak_data['energy_peak_electric_w_per_m_sq'] >= 0, "Peak should be non-negative"

    assert btap_data.unmet_hours(model).is_a?(Hash), "Should return hash"

    assert btap_data.service_water_heating_data.is_a?(Hash), "Should return hash"

    assert btap_data.outdoor_air_data(model).is_a?(Hash), "Should return hash"

    assert btap_data.envelope_exterior_surface_table.is_a?(Array)

    assert btap_data.get_national_ghg_cost(year: 2030).is_a?(Numeric)

    assert btap_data.btap_data.keys.select { |k| k.to_s.start_with?('phius') }.is_a?(Array)
    assert btap_data.btap_data.keys.select { |k| k.to_s.match?(/tedi|meui/) }.is_a?(Array)

    refute_equal 'N/A',
                 btap_data.validate_optional(model.building.get.name, model),
                 "Initialized Optional should return its value"

    construction_set = model.building.get.defaultConstructionSet
    if construction_set.empty?
      assert_equal 'N/A',
                   btap_data.validate_optional(construction_set, model),
                   "Empty Optional should return 'N/A'"
    end

    sql_tables = btap_data.sql_data_tables(model)
    assert sql_tables.is_a?(Array), "sql_data_tables returns an array of parsed table rows"
    refute sql_tables.empty?, "Should include at least one parsed table (AnnualBuildingUtilityPerformanceSummary/End Uses)"

    utility = btap_data.utility(model: model, utility_pricing_year: 2020)
    assert utility.is_a?(Hash), "Should return hash"
    assert utility['cost_utility_neb_total_cost_per_m_sq'], "Should calculate total utility cost"
    assert utility['cost_utility_ghg_total_kg_per_m_sq'], "Should calculate total GHG"

    utility_ghg_kg_per_gj = btap_data.get_utility_ghg_kg_per_gj(province: 'ON', fuel_type: 'Electricity')
    assert utility_ghg_kg_per_gj.is_a?(Numeric)
    assert utility_ghg_kg_per_gj >= 0

    utility_ghg_kg_per_gj = btap_data.get_utility_ghg_kg_per_gj(province: 'ON', fuel_type: 'NaturalGas')
    assert utility_ghg_kg_per_gj.is_a?(Numeric)
    assert utility_ghg_kg_per_gj >= 0

    thermal_zones_equipment = btap_data.thermal_zones_equipment_table(model)
    assert thermal_zones_equipment.is_a?(Array)
    if thermal_zones_equipment.any?
      first = thermal_zones_equipment.first
      assert first.key?('air_loop_name')
      assert first.key?('thermal_zone_name')
      assert first.key?('zone_equipment_name')
      assert first.key?('type')
    end

    spaces = btap_data.space_type_table(model)
    assert spaces.is_a?(Array), "Should return array"
    if spaces.size > 0
      first_space_type = spaces.first
      assert first_space_type['name'], "Should have space type name"
      assert first_space_type['floor_m_sq'], "Should have floor area"
      assert first_space_type['percent_area'], "Should have percent area"
    end
  end
end
