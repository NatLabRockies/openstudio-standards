require_relative '../../helpers/minitest_helper'

class TestConstructionsMaterials < Minitest::Test
  def setup
    @materials = OpenstudioStandards::Constructions::Materials
  end

  def test_material_get_conductance
    model = OpenStudio::Model::Model.new
    material = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0889, 2.31, 2322, 832)
    assert_in_delta(2.31 / 0.0889, @materials.material_get_conductance(material), 0.0001)

    material = OpenStudio::Model::AirGap.new(model, 0.2)
    assert_in_delta(1.0 / 0.2, @materials.material_get_conductance(material), 0.0001)

    material = OpenStudio::Model::Gas.new(model, 'Air', 0.01)
    assert_in_delta(2.561, @materials.material_get_conductance(material, temperature: 20.0), 0.001)

    material = OpenStudio::Model::Shade.new(model, 0.4, 0.5, 0.4, 0.5, 0.9, 0.0, 0.05, 0.1)
    assert_in_delta(0.1 / 0.05, @materials.material_get_conductance(material), 0.0001)
  end

  def test_opaque_material_set_thermal_resistance_standard
    model = OpenStudio::Model::Model.new
    material = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0889, 2.31, 2322, 832)
    assert(@materials.opaque_material_set_thermal_resistance(material, 0.9))
  end

  def test_opaque_material_set_thermal_resistance_massless
    model = OpenStudio::Model::Model.new
    material = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
    assert(@materials.opaque_material_set_thermal_resistance(material, 0.5))
  end

  def test_opaque_material_set_thermal_resistance_airgap
    model = OpenStudio::Model::Model.new
    material = OpenStudio::Model::AirGap.new(model)
    assert(@materials.opaque_material_set_thermal_resistance(material, 0.2))
  end

  def test_opaque_material_set_surface_properties
    model = OpenStudio::Model::Model.new
    material = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0889, 2.31, 2322, 832)
    result = @materials.opaque_material_set_surface_properties(material,
                                                               roughness: 'VerySmooth',
                                                               thermal_absorptance: 0.8,
                                                               solar_absorptance: 0.6,
                                                               visible_absorptance: 0.6)
    assert(result)
  end
end