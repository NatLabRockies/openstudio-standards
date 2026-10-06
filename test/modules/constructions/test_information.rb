require_relative '../../helpers/minitest_helper'

class TestConstructionsInformation < Minitest::Test
  def setup
    @create = OpenstudioStandards::CreateTypical
    @geo = OpenstudioStandards::Geometry
    @constructions = OpenstudioStandards::Constructions
  end

  def test_film_coefficients_r_value
    # Film values from 90.1-2010 A9.4.1 Air Films
    film_ext_surf_r_ip = 0.17
    film_semi_ext_surf_r_ip = 0.46
    film_int_surf_ht_flow_up_r_ip = 0.61
    film_int_surf_ht_flow_dwn_r_ip = 0.92
    fil_int_surf_vertical_r_ip = 0.68

    film_ext_surf_r_si = OpenStudio.convert(film_ext_surf_r_ip, 'ft^2*hr*R/Btu', 'm^2*K/W').get
    film_semi_ext_surf_r_si = OpenStudio.convert(film_semi_ext_surf_r_ip, 'ft^2*hr*R/Btu', 'm^2*K/W').get
    film_int_surf_ht_flow_up_r_si = OpenStudio.convert(film_int_surf_ht_flow_up_r_ip, 'ft^2*hr*R/Btu', 'm^2*K/W').get
    film_int_surf_ht_flow_dwn_r_si = OpenStudio.convert(film_int_surf_ht_flow_dwn_r_ip, 'ft^2*hr*R/Btu', 'm^2*K/W').get
    fil_int_surf_vertical_r_si = OpenStudio.convert(fil_int_surf_vertical_r_ip, 'ft^2*hr*R/Btu', 'm^2*K/W').get

    result = @constructions.film_coefficients_r_value('AtticFloor', true, true)
    assert_in_delta(film_int_surf_ht_flow_up_r_si + film_semi_ext_surf_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('AtticWall', true, true)
    assert_in_delta(film_ext_surf_r_si + film_semi_ext_surf_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('InteriorCeiling', true, true)
    assert_in_delta(film_int_surf_ht_flow_dwn_r_si + film_int_surf_ht_flow_up_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('ExteriorRoof', true, true)
    assert_in_delta(film_ext_surf_r_si + film_int_surf_ht_flow_up_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('ExteriorFloor', true, true)
    assert_in_delta(film_ext_surf_r_si + film_int_surf_ht_flow_dwn_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('ExteriorWall', true, true)
    assert_in_delta(film_ext_surf_r_si + fil_int_surf_vertical_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('GroundContactFloor', true, true)
    assert_in_delta(film_int_surf_ht_flow_dwn_r_si, result, 0.001)
    result = @constructions.film_coefficients_r_value('GroundContactWall', true, true)
    assert_in_delta(fil_int_surf_vertical_r_si, result, 0.001)
  end

  def test_construction_simple_glazing?
    model = OpenStudio::Model::Model.new
    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([simple_glazing])
    assert(@constructions.construction_simple_glazing?(construction))

    op_mat = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    construction.setLayers([op_mat])
    assert(!@constructions.construction_simple_glazing?(construction))
  end

  def test_construction_get_conductance
    model = OpenStudio::Model::Model.new
    construction = OpenStudio::Model::Construction.new(model)
    material1 = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.12, 2.0, 2322, 832)
    material2 = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.09, 1.5, 2322, 832)
    calc = 1.0 / ((1.0 / (2.0 / 0.12)) + (1.0 / (1.5 / 0.09)))
    construction.setLayers([material1, material2])
    assert_in_delta(calc, @constructions.construction_get_conductance(construction), 0.0001)

    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model, 0.2, 0.40)
    construction.setLayers([simple_glazing])
    assert_in_delta(0.2, @constructions.construction_get_conductance(construction), 0.0001)

    material1 = OpenStudio::Model::Gas.new(model, 'Air', 0.01)
    material2 = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.1)
    construction.setLayers([material2, material1, material2])
    assert_in_delta(1.6, @constructions.construction_get_conductance(construction, temperature: 10.0), 0.001)
  end

  def test_construction_get_solar_transmittance
    model = OpenStudio::Model::Model.new
    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
    simple_glazing.setSolarHeatGainCoefficient(0.45)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([simple_glazing])
    assert(0.45, @constructions.construction_get_solar_transmittance(construction))

    standard_glazing = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
    standard_glazing.setSolarTransmittance(0.5)
    construction.setLayers([standard_glazing])
    assert(0.5, @constructions.construction_get_solar_transmittance(construction))

    construction.setLayers([standard_glazing, standard_glazing])
    assert(0.25, @constructions.construction_get_solar_transmittance(construction))
  end

  def test_construction_get_visible_transmittance
    model = OpenStudio::Model::Model.new
    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
    simple_glazing.setVisibleTransmittance(0.45)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([simple_glazing])
    assert_in_delta(0.45, @constructions.construction_get_visible_transmittance(construction), 0.001)

    standard_glazing = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
    standard_glazing.setVisibleTransmittance(0.5)
    construction.setLayers([standard_glazing])
    assert_in_delta(0.5, @constructions.construction_get_visible_transmittance(construction), 0.001)

    construction.setLayers([standard_glazing, standard_glazing])
    assert_in_delta(0.25, @constructions.construction_get_visible_transmittance(construction), 0.001)
  end

  def test_construction_get_solar_reflectance_index
    model = OpenStudio::Model::Model.new
    layers = OpenStudio::Model::MaterialVector.new
    layers << OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0889, 2.31, 2322, 832)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers(layers)
    sri = @constructions.construction_get_solar_reflectance_index(construction)
    assert(sri  > 0)
  end

  def test_surfaces_get_conductance
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get

    south_wall_surface = nil
    space.surfaces.each do |surface|
      next unless surface.surfaceType == 'Wall'
      next unless @geo.surface_get_cardinal_direction(surface) == 'S'

      south_wall_surface = surface
    end

    wall_construction = OpenStudio::Model::Construction.new(model)
    material1 = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.12, 2.0, 2322, 832)
    material2 = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.09, 1.5, 2322, 832)
    wall_u = 1.0 / ((1.0 / (2.0 / 0.12)) + (1.0 / (1.5 / 0.09)))
    wall_construction.setLayers([material1, material2])
    south_wall_surface.setConstruction(wall_construction)

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(1.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(1.0, 0.0, 2.0)
    window1 = OpenStudio::Model::SubSurface.new(vertices, model)
    window1.setSurface(south_wall_surface)

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(3.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(3.0, 0.0, 2.0)
    window2 = OpenStudio::Model::SubSurface.new(vertices, model)
    window2.setSurface(south_wall_surface)

    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model, 0.40, 0.50)
    construction1 = OpenStudio::Model::Construction.new(model)
    construction1.setLayers([simple_glazing])
    window1.setConstruction(construction1)

    material1 = OpenStudio::Model::Gas.new(model, 'Air', 0.01)
    material2 = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.1)
    construction2 = OpenStudio::Model::Construction.new(model)
    construction2.setLayers([material2, material1, material2])
    window2.setConstruction(construction2)

    avg_cond = @constructions.surfaces_get_conductance([window1, window2])
    assert_in_delta((0.4 + 1.568) / 2.0, avg_cond, 0.001)

    avg_cond = @constructions.surfaces_get_conductance([window1, window2, south_wall_surface])
    assert_in_delta((0.4 + 1.568 + 13 * wall_u) / 15.0, avg_cond, 0.001)
  end

  def test_surfaces_get_solar_transmittance
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get

    south_wall_surface = nil
    space.surfaces.each do |surface|
      next unless surface.surfaceType == 'Wall'
      next unless @geo.surface_get_cardinal_direction(surface) == 'S'

      south_wall_surface = surface
    end

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(1.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(1.0, 0.0, 2.0)
    window1 = OpenStudio::Model::SubSurface.new(vertices, model)
    window1.setSurface(south_wall_surface)

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(3.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(3.0, 0.0, 2.0)
    window2 = OpenStudio::Model::SubSurface.new(vertices, model)
    window2.setSurface(south_wall_surface)

    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
    simple_glazing.setSolarHeatGainCoefficient(0.3)
    construction1 = OpenStudio::Model::Construction.new(model)
    construction1.setLayers([simple_glazing])
    window1.setConstruction(construction1)

    standard_glazing = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
    standard_glazing.setSolarTransmittance(0.6)
    construction2 = OpenStudio::Model::Construction.new(model)
    construction2.setLayers([standard_glazing])
    window2.setConstruction(construction2)

    avg_tsol = @constructions.surfaces_get_solar_transmittance([window1, window2])
    assert_in_delta((0.3 + 0.6) / 2.0, avg_tsol, 0.001)
  end

  def test_surfaces_get_visible_transmittance
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get

    south_wall_surface = nil
    space.surfaces.each do |surface|
      next unless surface.surfaceType == 'Wall'
      next unless @geo.surface_get_cardinal_direction(surface) == 'S'

      south_wall_surface = surface
    end

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(1.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(2.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(1.0, 0.0, 2.0)
    window1 = OpenStudio::Model::SubSurface.new(vertices, model)
    window1.setSurface(south_wall_surface)

    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(3.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 1.0)
    vertices << OpenStudio::Point3d.new(4.0, 0.0, 2.0)
    vertices << OpenStudio::Point3d.new(3.0, 0.0, 2.0)
    window2 = OpenStudio::Model::SubSurface.new(vertices, model)
    window2.setSurface(south_wall_surface)

    simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
    simple_glazing.setVisibleTransmittance(0.3)
    construction1 = OpenStudio::Model::Construction.new(model)
    construction1.setLayers([simple_glazing])
    window1.setConstruction(construction1)

    standard_glazing = OpenStudio::Model::StandardGlazing.new(model, 'SpectralAverage', 0.003)
    standard_glazing.setVisibleTransmittance(0.6)
    construction2 = OpenStudio::Model::Construction.new(model)
    construction2.setLayers([standard_glazing])
    window2.setConstruction(construction2)

    avg_tvis = @constructions.surfaces_get_visible_transmittance([window1, window2])
    assert_in_delta((0.3 + 0.6) / 2.0, avg_tvis, 0.001)
  end

  def test_construction_set_get_constructions
    model = OpenStudio::Model::Model.new
    building_type = 'PrimarySchool'
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    @create.create_space_types_and_constructions(model, building_type, template, climate_zone)
    default_construction_set = model.getDefaultConstructionSets[0]
    construction_array = @constructions.construction_set_get_constructions(default_construction_set)
    assert(construction_array.size > 2)
  end

  def test_model_get_constructions
    model = OpenStudio::Model::Model.new
    polygon = OpenStudio::Point3dVector.new
    origin = OpenStudio::Point3d.new(0.0, 0.0, 0.0)
    polygon << origin
    polygon << origin + OpenStudio::Vector3d.new(0.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 5.0, 0.0)
    polygon << origin + OpenStudio::Vector3d.new(5.0, 0.0, 0.0)
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    building_type = 'PrimarySchool'
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    @create.create_space_types_and_constructions(model, building_type, template, climate_zone)
    roof_constructions = @constructions.model_get_constructions(model, 'Outdoors', 'ExteriorRoof')
    assert_equal(1, roof_constructions.size)

    # hard assign construction
    mat1 = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.2, 1.729, 2243, 837)
    mat1.setName('Material 1')
    insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Smooth', 0.068, 0.0432, 91, 837)
    insulation.setName('Insulation')
    mat2 = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0127, 0.16, 785, 830)
    mat2.setName('Material 2')
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([mat1, insulation, mat2])
    construction.setName('New Construction')
    surface = model.getSurfaceByName('Surface 6').get
    surface.setConstruction(construction)
    roof_constructions = @constructions.model_get_constructions(model, 'Outdoors', 'ExteriorRoof')
    assert_equal(2, roof_constructions.size)
  end
end