require_relative 'test_helper'

# ModelQuery: SDK -> plain hashes for the renderer (one of the two
# SDK-touching renderer files, with report.rb). Verifies envelope aggregation
# (incl. the SimpleGlazing uFactor fallback) and nil-safety.
class TestReportModelQuery < Minitest::Test
  include FixtureHelper
  MQ = OpenStudioNECB::Report::ModelQuery

  def test_nil_model
    assert_nil MQ.extract(nil)
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

end
