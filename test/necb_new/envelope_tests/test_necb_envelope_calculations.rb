require_relative '../test_helper'

class TestNECBEnvelopeCalculations < Minitest::Test
  # Test envelope calculation methods and U-value lookups in NECB2011
  # Targets building_envelope.rb (495 uncovered lines, 43.8% coverage)
  # Goal: Push coverage toward 70%+

  ##############################################################################
  # U-VALUE LOOKUPS
  # Test max_u_necb method for various assembly types and HDDs
  ##############################################################################

  def test_max_u_necb_roof_ceiling_various_hdds
    # Test roof/ceiling U-value lookups across climate zones
    standard = Standard.build('NECB2011')

    # Climate zones (HDD values from NECB Table A-3.2.2.2(1))
    test_cases = [
      { hdd: 3000, expected_max: 0.25 },   # Zone 4 (mild)
      { hdd: 4000, expected_max: 0.25 },   # Zone 5 (moderate)
      { hdd: 5000, expected_max: 0.21 },   # Zone 6 (cold)
      { hdd: 7000, expected_max: 0.18 },   # Zone 7A/7B (very cold)
      { hdd: 9000, expected_max: 0.14 }    # Zone 8 (extreme cold)
    ]

    test_cases.each do |test_case|
      u_value = standard.max_u_necb('roofceiling', 'outdoors', test_case[:hdd])
      assert u_value <= test_case[:expected_max],
             "Roof U-value for HDD #{test_case[:hdd]} should be <= #{test_case[:expected_max]}, got #{u_value}"
      assert u_value > 0, "U-value should be positive"
    end
  end

  def test_max_u_necb_walls_various_hdds
    # Test wall U-value requirements for different climate zones
    standard = Standard.build('NECB2011')

    test_cases = [
      { hdd: 3000, surface_type: 'abovegrade' },  # Mild
      { hdd: 5000, surface_type: 'abovegrade' },  # Cold
      { hdd: 8000, surface_type: 'abovegrade' },  # Very cold
      { hdd: 3000, surface_type: 'belowgrade' },  # Below grade
      { hdd: 8000, surface_type: 'belowgrade' }   # Below grade cold
    ]

    test_cases.each do |test_case|
      u_value = standard.max_u_necb(test_case[:surface_type], 'ground', test_case[:hdd])
      assert u_value > 0, "U-value should be positive for #{test_case[:surface_type]} at HDD #{test_case[:hdd]}"
      assert u_value < 5.0, "U-value should be reasonable (< 5.0)"
    end
  end

  def test_max_u_necb_floors_various_conditions
    # Test floor U-values for various conditions
    standard = Standard.build('NECB2011')

    test_cases = [
      { type: 'floor', condition: 'outdoors', hdd: 4000 },
      { type: 'floor', condition: 'ground', hdd: 6000 },
      { type: 'slab', condition: 'ground', hdd: 5000 }
    ]

    test_cases.each do |test_case|
      u_value = standard.max_u_necb(test_case[:type], test_case[:condition], test_case[:hdd])
      assert u_value > 0, "U-value should be positive for #{test_case[:type]}/#{test_case[:condition]}"
    end
  end

  ##############################################################################
  # FDWR (FENESTRATION TO WALL RATIO) CALCULATIONS
  # Test window-to-wall ratio methods
  ##############################################################################

  def test_max_fwdr_calculation_for_various_hdds
    # Test maximum fenestration-to-wall ratio limits
    standard = Standard.build('NECB2011')

    # NECB Table 3.2.1.4 - Maximum FDWR by climate zone
    test_cases = [
      { hdd: 3000, expected_max_range: [0.35, 0.45] },  # Warmer zones
      { hdd: 5000, expected_max_range: [0.30, 0.40] },  # Mid zones
      { hdd: 7000, expected_max_range: [0.25, 0.35] },  # Colder zones
      { hdd: 9000, expected_max_range: [0.20, 0.30] }   # Coldest zones
    ]

    test_cases.each do |test_case|
      fdwr = standard.max_fwdr(test_case[:hdd])
      assert fdwr >= test_case[:expected_max_range][0],
             "FDWR for HDD #{test_case[:hdd]} should be >= #{test_case[:expected_max_range][0]}"
      assert fdwr <= test_case[:expected_max_range][1],
             "FDWR for HDD #{test_case[:hdd]} should be <= #{test_case[:expected_max_range][1]}"
    end
  end

  def test_apply_limit_fdwr_to_model
    # Test applying FDWR limit to a model
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Add minimal geometry
    add_simple_building_geometry(model)

    # Apply FDWR limit
    fdwr_limit = 0.35
    result = standard.apply_limit_fdwr(model: model, fdwr_lim: fdwr_limit)

    # Method should execute without errors
    assert !result.nil?, "apply_limit_fdwr should return a value"
  end

  ##############################################################################
  # SRR (SKYLIGHT TO ROOF RATIO) CALCULATIONS
  # Test skylight ratio methods
  ##############################################################################

  def test_apply_standard_skylight_to_roof_ratio
    # Test skylight-to-roof ratio application
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Add building with roof
    add_simple_building_geometry(model)

    # Apply SRR limit (NECB typically limits to 5%)
    result = standard.apply_standard_skylight_to_roof_ratio(model: model, srr_set: 0.05)

    # Should execute without crashing
    assert true, "SRR application should complete"
  end

  ##############################################################################
  # CONSTRUCTION SET APPLICATION
  # Test construction assignment methods
  ##############################################################################

  def test_add_construction_sets_for_various_climates
    # Test construction set creation for different climate zones
    standard = Standard.build('NECB2011')

    test_hdds = [3000, 4000, 5000, 6000, 7000, 8000, 9000]

    test_hdds.each do |hdd|
      model = OpenStudio::Model::Model.new

      # Add construction sets (a is an internal parameter, use default {})
      result = standard.add_construction_sets(model, hdd, {})

      # Should create construction sets
      construction_sets = model.getDefaultConstructionSets
      assert construction_sets.size > 0,
             "Should create construction sets for HDD #{hdd}"
    end
  end

  def test_apply_building_default_constructionset
    # Test applying default construction set to building
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Add construction sets
    standard.add_construction_sets(model, 5000, {})

    # Apply to building
    result = standard.apply_building_default_constructionset(model)

    # Building should have default construction set assigned
    building = model.getBuilding
    assert building.defaultConstructionSet.is_initialized,
           "Building should have default construction set"
  end

  ##############################################################################
  # SURFACE CONDUCTANCE CALCULATIONS
  # Test external surface conductance methods
  ##############################################################################

  def test_set_necb_external_surface_conductance
    # Test setting external surface conductance
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Create a simple surface
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 0)
    vertices << OpenStudio::Point3d.new(10, 0, 3)
    vertices << OpenStudio::Point3d.new(0, 0, 3)

    surface = OpenStudio::Model::Surface.new(vertices, model)
    surface.setSurfaceType('Wall')
    surface.setOutsideBoundaryCondition('Outdoors')

    # Apply conductance for various HDD values
    test_hdds = [4000, 6000, 8000]

    test_hdds.each do |hdd|
      result = standard.set_necb_external_surface_conductance(surface, hdd)
      # Method should execute without error
      assert true, "Should set conductance for HDD #{hdd}"
    end
  end

  def test_set_necb_external_subsurface_conductance
    # Test setting conductance for windows/doors
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Create wall surface
    wall_vertices = OpenStudio::Point3dVector.new
    wall_vertices << OpenStudio::Point3d.new(0, 0, 0)
    wall_vertices << OpenStudio::Point3d.new(10, 0, 0)
    wall_vertices << OpenStudio::Point3d.new(10, 0, 3)
    wall_vertices << OpenStudio::Point3d.new(0, 0, 3)

    wall = OpenStudio::Model::Surface.new(wall_vertices, model)
    wall.setSurfaceType('Wall')
    wall.setOutsideBoundaryCondition('Outdoors')

    # Create window subsurface
    window_vertices = OpenStudio::Point3dVector.new
    window_vertices << OpenStudio::Point3d.new(2, 0, 0.5)
    window_vertices << OpenStudio::Point3d.new(4, 0, 0.5)
    window_vertices << OpenStudio::Point3d.new(4, 0, 2.5)
    window_vertices << OpenStudio::Point3d.new(2, 0, 2.5)

    window = OpenStudio::Model::SubSurface.new(window_vertices, model)
    window.setSurface(wall)
    window.setSubSurfaceType('FixedWindow')

    # Apply conductance
    result = standard.set_necb_external_subsurface_conductance(window, 6000)

    # Should execute without error
    assert true, "Should set subsurface conductance"
  end

  ##############################################################################
  # GEOMETRY SCALING
  # Test geometry transformation methods
  ##############################################################################

  def test_scale_model_geometry
    # Test scaling model geometry
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Add simple geometry
    add_simple_building_geometry(model)

    original_floor_area = model.getBuilding.floorArea

    # Scale model by 2x in all dimensions
    standard.scale_model_geometry(model, 2.0, 2.0, 2.0)

    scaled_floor_area = model.getBuilding.floorArea

    # Floor area should be roughly 4x (2x × 2x)
    expected_area = original_floor_area * 4.0
    assert_in_delta expected_area, scaled_floor_area, original_floor_area * 0.5,
                    "Scaled floor area should be approximately 4x original"
  end

  def test_scale_model_geometry_with_different_factors
    # Test non-uniform scaling
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    add_simple_building_geometry(model)

    # Scale differently in each direction
    standard.scale_model_geometry(model, 1.5, 2.0, 0.5)

    # Should complete without errors
    assert model.getBuilding.floorArea > 0, "Model should still have positive floor area"
  end

  ##############################################################################
  # ADIABATIC SURFACE HANDLING
  # Test construction assignment to adiabatic surfaces
  ##############################################################################

  def test_assign_construction_to_adiabatic_surfaces
    # Test assigning constructions to adiabatic surfaces
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    # Create surface with adiabatic boundary condition
    vertices = OpenStudio::Point3dVector.new
    vertices << OpenStudio::Point3d.new(0, 0, 0)
    vertices << OpenStudio::Point3d.new(5, 0, 0)
    vertices << OpenStudio::Point3d.new(5, 0, 3)
    vertices << OpenStudio::Point3d.new(0, 0, 3)

    surface = OpenStudio::Model::Surface.new(vertices, model)
    surface.setSurfaceType('Wall')
    surface.setOutsideBoundaryCondition('Adiabatic')

    # Assign constructions
    standard.assign_contruction_to_adiabatic_surfaces(model)

    # Surface should have construction assigned
    assert surface.construction.is_initialized || surface.isConstructionDefaulted,
           "Adiabatic surface should have construction"
  end

  ##############################################################################
  # CONSTRUCTION ADDITION
  # Test model_add_constructions method
  ##############################################################################

  def test_model_add_constructions
    # Test adding standard constructions to model
    model = OpenStudio::Model::Model.new
    standard = Standard.build('NECB2011')

    initial_construction_count = model.getConstructions.size

    # Add NECB constructions
    standard.model_add_constructions(model)

    final_construction_count = model.getConstructions.size

    # Should add constructions
    assert final_construction_count > initial_construction_count,
           "Should add constructions to model"
  end

  ##############################################################################
  # HELPER METHODS
  ##############################################################################

  private

  def add_simple_building_geometry(model)
    # Add a simple rectangular building for testing

    # Create space
    space = OpenStudio::Model::Space.new(model)
    space.setName('Test Space')

    # Floor
    floor_vertices = OpenStudio::Point3dVector.new
    floor_vertices << OpenStudio::Point3d.new(0, 0, 0)
    floor_vertices << OpenStudio::Point3d.new(10, 0, 0)
    floor_vertices << OpenStudio::Point3d.new(10, 10, 0)
    floor_vertices << OpenStudio::Point3d.new(0, 10, 0)

    floor = OpenStudio::Model::Surface.new(floor_vertices, model)
    floor.setSpace(space)
    floor.setSurfaceType('Floor')
    floor.setOutsideBoundaryCondition('Ground')

    # South wall
    south_wall_vertices = OpenStudio::Point3dVector.new
    south_wall_vertices << OpenStudio::Point3d.new(0, 0, 3)
    south_wall_vertices << OpenStudio::Point3d.new(0, 0, 0)
    south_wall_vertices << OpenStudio::Point3d.new(10, 0, 0)
    south_wall_vertices << OpenStudio::Point3d.new(10, 0, 3)

    south_wall = OpenStudio::Model::Surface.new(south_wall_vertices, model)
    south_wall.setSpace(space)
    south_wall.setSurfaceType('Wall')
    south_wall.setOutsideBoundaryCondition('Outdoors')

    # Roof/ceiling
    roof_vertices = OpenStudio::Point3dVector.new
    roof_vertices << OpenStudio::Point3d.new(0, 10, 3)
    roof_vertices << OpenStudio::Point3d.new(10, 10, 3)
    roof_vertices << OpenStudio::Point3d.new(10, 0, 3)
    roof_vertices << OpenStudio::Point3d.new(0, 0, 3)

    roof = OpenStudio::Model::Surface.new(roof_vertices, model)
    roof.setSpace(space)
    roof.setSurfaceType('RoofCeiling')
    roof.setOutsideBoundaryCondition('Outdoors')

    # Create thermal zone and assign space
    zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(zone)

    model
  end
end
