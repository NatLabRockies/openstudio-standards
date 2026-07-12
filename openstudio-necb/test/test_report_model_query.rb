require_relative 'test_helper'

# ModelQuery: the only SDK-touching renderer file. Verifies component-chain
# classification, envelope aggregation (incl. the SimpleGlazing uFactor
# fallback), and nil-safety.
class TestReportModelQuery < Minitest::Test
  include FixtureHelper
  MQ = OpenStudioNECB::Report::ModelQuery

  def test_nil_model
    assert_nil MQ.extract(nil)
  end

  def test_air_loop_chain_sequence
    model = proposed_with_hvac('PSZ RTU with exhaust Gas and DX Coils and Hot Water Baseboard')
    data = MQ.extract(model)
    refute_empty data[:air_loops]
    kinds = data[:air_loops].first[:chain].map { |c| c[:kind] }
    assert_includes kinds, :oa
    assert_includes kinds, :cooling_coil
    assert_includes kinds, :heating_coil
    assert_includes kinds, :fan
    assert_operator data[:air_loops].first[:zone_count], :>=, 1
  end

  def test_plant_loop_chain_sequence
    model = proposed_with_hvac # Baseboard gas boiler
    data = MQ.extract(model)
    refute_empty data[:plant_loops]
    kinds = data[:plant_loops].first[:chain].map { |c| c[:kind] }
    assert_includes kinds, :boiler
    assert_includes kinds, :pump
    assert_operator data[:plant_loops].first[:demand_count], :>=, 1
  end

  def test_envelope_aggregation
    model = load_fixture
    data = MQ.extract(model)
    types = data[:envelope][:surfaces].map { |s| s[:type] }
    assert_includes types, 'Wall'
    assert_includes types, 'RoofCeiling'
    wall = data[:envelope][:surfaces].find { |s| s[:type] == 'Wall' }
    assert_operator wall[:area_m2], :>, 0
    assert wall[:avg_u_w_per_m2k].nil? || wall[:avg_u_w_per_m2k].positive?
  end

  def test_simple_glazing_u_fallback
    model = load_fixture
    glazing = OpenStudio::Model::SimpleGlazing.new(model)
    glazing.setUFactor(2.4)
    glazing.setSolarHeatGainCoefficient(0.4)
    construction = OpenStudio::Model::Construction.new(model)
    construction.insertLayer(0, glazing)
    surface = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    surface.setConstruction(construction)
    u = MQ.construction_conductance(surface.construction)
    assert_in_delta 2.4, u, 0.2, 'SimpleGlazing constructions fall back to uFactor'
  end

  def test_classify_unmatched_returns_nil
    assert_nil MQ.classify('OS_Node')
    assert_equal :fan, MQ.classify('OS_Fan_VariableVolume')
    assert_equal :water_heater, MQ.classify('OS_WaterHeater_Mixed')
  end
end
