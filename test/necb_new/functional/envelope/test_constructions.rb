require_relative '../../test_helper'

# Test NECB construction assignment to surfaces
# Tests that constructions are properly applied to model geometry and meet NECB requirements
#
# Methods tested:
# - NECB2011#apply_standard_construction_properties - Apply constructions to whole model
# - NECB2011#max_u_necb - Get maximum U-values by surface type and HDD
# - OpenstudioStandards::Constructions.surfaces_get_conductance - Get weighted average conductance
#
# References:
# - NECB 2011/2015/2017/2020 Table 3.2.1.3 (Maximum Overall Thermal Transmittance)
# - /lib/openstudio-standards/standards/necb/NECB2011/building_envelope.rb
class TestConstructions < Minitest::Test

  # ============================================================================
  # Helper Methods
  # ============================================================================

  # Helper method to setup a model with weather file and default construction set
  def setup_model_for_constructions(model_path, weather_file_name, standard)
    # Load model
    model = BTAP::FileIO.load_osm(model_path)

    # Set weather file
    weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file_name)
    epw_file = OpenStudio::EpwFile.new(weather_file_path)
    OpenstudioStandards::Weather.model_set_weather_file(model, epw_file)

    # Load a default construction set from NECB template
    # This provides all the necessary sub-construction sets
    construction_set = standard.model_add_construction_set_from_osm(model: model)
    model.getBuilding.setDefaultConstructionSet(construction_set)

    # Apply NECB constructions
    standard.apply_standard_construction_properties(model: model)

    return model
  end

  # ============================================================================
  # Test: Apply constructions for different HDD zones
  # ============================================================================

  def test_necb2011_apply_constructions_hdd_3000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',  # HDD ~2800
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify all exterior walls have constructions
    walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    refute_empty walls, "Model should have exterior walls"
    assert walls.all? { |w| w.construction.is_initialized }, "All exterior walls should have constructions assigned"

    # Verify wall U-values meet NECB limits for the calculated HDD
    max_u_wall = standard.max_u_necb('wall', 'outdoors', hdd)
    wall_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(walls)
    assert wall_conductance <= max_u_wall + 0.001,
      "Wall conductance #{wall_conductance.round(4)} W/m2K should meet NECB limit #{max_u_wall} W/m2K for HDD #{hdd.round(0)}"
  end

  def test_necb2011_apply_constructions_hdd_4000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify wall U-values meet NECB limits for the calculated HDD
    walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    max_u_wall = standard.max_u_necb('wall', 'outdoors', hdd)
    wall_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(walls)
    assert wall_conductance <= max_u_wall + 0.001,
      "Wall conductance #{wall_conductance.round(4)} W/m2K should meet NECB limit #{max_u_wall} W/m2K for HDD #{hdd.round(0)}"
  end

  def test_necb2011_apply_constructions_hdd_5000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',  # Toronto HDD ~3800
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify wall U-values meet NECB limits for the calculated HDD
    walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    max_u_wall = standard.max_u_necb('wall', 'outdoors', hdd)
    wall_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(walls)
    assert wall_conductance <= max_u_wall + 0.001,
      "Wall conductance #{wall_conductance.round(4)} W/m2K should meet NECB limit #{max_u_wall} W/m2K for HDD #{hdd.round(0)}"
  end

  def test_necb2011_apply_constructions_hdd_6000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw',  # Yellowknife is HDD 6000+
      standard
    )

    # Verify wall U-values meet NECB limits for HDD 6000+
    walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    max_u_wall = standard.max_u_necb('wall', 'outdoors', 6000)
    wall_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(walls)
    assert wall_conductance <= max_u_wall + 0.001,
      "Wall conductance #{wall_conductance.round(4)} W/m2K should meet NECB limit #{max_u_wall} W/m2K for HDD 6000+"
  end

  # ============================================================================
  # Test: Roof construction compliance
  # ============================================================================

  def test_necb2011_roof_constructions_hdd_3000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',  # HDD ~2800
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify all roofs have constructions
    roofs = model.getSurfaces.select { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
    refute_empty roofs, "Model should have exterior roofs"
    assert roofs.all? { |r| r.construction.is_initialized }, "All roofs should have constructions assigned"

    # Verify roof U-values meet NECB limits for the calculated HDD
    max_u_roof = standard.max_u_necb('roofceiling', 'outdoors', hdd)
    roof_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(roofs)
    assert roof_conductance <= max_u_roof + 0.001,
      "Roof conductance #{roof_conductance.round(4)} W/m2K should meet NECB limit #{max_u_roof} W/m2K for HDD #{hdd.round(0)}"
  end

  def test_necb2011_roof_constructions_hdd_6000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw',  # HDD ~8200
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify roof U-values meet NECB limits for the calculated HDD
    roofs = model.getSurfaces.select { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
    max_u_roof = standard.max_u_necb('roofceiling', 'outdoors', hdd)
    roof_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(roofs)
    assert roof_conductance <= max_u_roof + 0.001,
      "Roof conductance #{roof_conductance.round(4)} W/m2K should meet NECB limit #{max_u_roof} W/m2K for HDD #{hdd.round(0)}"
  end

  # ============================================================================
  # Test: Floor construction compliance
  # ============================================================================

  def test_necb2011_floor_constructions_ground
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',  # HDD ~5120
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify ground floors have constructions
    ground_floors = model.getSurfaces.select { |s| s.surfaceType == 'Floor' && s.outsideBoundaryCondition == 'Ground' }
    refute_empty ground_floors, "Model should have ground floors"
    assert ground_floors.all? { |f| f.construction.is_initialized }, "All ground floors should have constructions assigned"

    # Verify floor U-values meet NECB limits for the calculated HDD and ground boundary
    max_u_floor = standard.max_u_necb('floor', 'ground', hdd)
    floor_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(ground_floors)
    assert floor_conductance <= max_u_floor + 0.001,
      "Ground floor conductance #{floor_conductance.round(4)} W/m2K should meet NECB limit #{max_u_floor} W/m2K for HDD #{hdd.round(0)}"
  end

  # ============================================================================
  # Test: Window/Skylight construction compliance
  # ============================================================================

  def test_necb2011_window_constructions_hdd_3000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box_with_skylight.osm'),
      'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',  # HDD ~2800
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify windows have constructions
    windows = model.getSubSurfaces.select { |s| s.subSurfaceType.include?('Window') || s.subSurfaceType == 'FixedWindow' }
    if !windows.empty?
      assert windows.all? { |w| w.construction.is_initialized }, "All windows should have constructions assigned"

      # Verify window U-values meet NECB limits for the calculated HDD
      max_u_window = standard.max_u_necb('window', 'outdoors', hdd)
      window_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(windows)
      assert window_conductance <= max_u_window + 0.01,
        "Window conductance #{window_conductance.round(4)} W/m2K should meet NECB limit #{max_u_window} W/m2K for HDD #{hdd.round(0)}"
    end
  end

  def test_necb2011_skylight_constructions_hdd_4000
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box_with_skylight.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',  # HDD ~5120
      standard
    )

    # Get the actual HDD calculated from weather file
    hdd = standard.get_necb_hdd18(model: model)

    # Verify skylights have constructions
    skylights = model.getSubSurfaces.select { |s| s.subSurfaceType.include?('Skylight') }
    if !skylights.empty?
      assert skylights.all? { |sk| sk.construction.is_initialized }, "All skylights should have constructions assigned"

      # Verify skylight U-values meet NECB limits for the calculated HDD
      max_u_skylight = standard.max_u_necb('skylight', 'outdoors', hdd)
      skylight_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(skylights)
      assert skylight_conductance <= max_u_skylight + 0.01,
        "Skylight conductance #{skylight_conductance.round(4)} W/m2K should meet NECB limit #{max_u_skylight} W/m2K for HDD #{hdd.round(0)}"
    end
  end

  # ============================================================================
  # Test: NECB vintages comparison (2011 vs 2015 vs 2020)
  # ============================================================================

  def test_necb2015_apply_constructions_hdd_4000
    standard = Standard.build('NECB2015')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
      standard
    )

    # Verify constructions applied
    walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    assert walls.all? { |w| w.construction.is_initialized }, "All walls should have NECB2015 constructions assigned"

    # Verify wall U-values meet NECB2015 limits
    max_u_wall = standard.max_u_necb('wall', 'outdoors', 4000)
    wall_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(walls)
    assert wall_conductance <= max_u_wall + 0.001,
      "Wall conductance #{wall_conductance.round(4)} W/m2K should meet NECB2015 limit #{max_u_wall} W/m2K for HDD 4000"
  end

  def test_necb2020_apply_constructions_hdd_4000
    standard = Standard.build('NECB2020')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
      standard
    )

    # Verify constructions applied
    walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    assert walls.all? { |w| w.construction.is_initialized }, "All walls should have NECB2020 constructions assigned"

    # Verify wall U-values meet NECB2020 limits
    max_u_wall = standard.max_u_necb('wall', 'outdoors', 4000)
    wall_conductance = OpenstudioStandards::Constructions.surfaces_get_conductance(walls)
    assert wall_conductance <= max_u_wall + 0.001,
      "Wall conductance #{wall_conductance.round(4)} W/m2K should meet NECB2020 limit #{max_u_wall} W/m2K for HDD 4000"
  end

  # ============================================================================
  # Test: Construction naming conventions
  # ============================================================================

  def test_necb2011_construction_names_reasonable
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/simple_box.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
      standard
    )

    # Verify construction names are reasonable (not empty, not just numbers)
    all_surfaces = model.getSurfaces
    all_surfaces.each do |surface|
      next unless surface.construction.is_initialized

      construction = surface.construction.get
      construction_name = construction.name.to_s

      refute_empty construction_name, "Construction name should not be empty for surface #{surface.name}"
      assert construction_name.length > 5, "Construction name '#{construction_name}' should be descriptive"
    end
  end

  # ============================================================================
  # Test: Multi-zone building construction assignment
  # ============================================================================

  def test_necb2011_multi_zone_constructions
    standard = Standard.build('NECB2011')
    model = setup_model_for_constructions(
      File.join(__dir__, '../../fixtures/geometry/multi_zone_rectangle.osm'),
      'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
      standard
    )

    # Verify all exterior surfaces have constructions
    exterior_walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Outdoors' }
    exterior_roofs = model.getSurfaces.select { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
    ground_floors = model.getSurfaces.select { |s| s.surfaceType == 'Floor' && s.outsideBoundaryCondition == 'Ground' }

    refute_empty exterior_walls, "Multi-zone model should have exterior walls"
    refute_empty exterior_roofs, "Multi-zone model should have exterior roofs"
    refute_empty ground_floors, "Multi-zone model should have ground floors"

    assert exterior_walls.all? { |w| w.construction.is_initialized }, "All exterior walls should have constructions"
    assert exterior_roofs.all? { |r| r.construction.is_initialized }, "All exterior roofs should have constructions"
    assert ground_floors.all? { |f| f.construction.is_initialized }, "All ground floors should have constructions"

    # Verify internal surfaces have constructions too
    internal_walls = model.getSurfaces.select { |s| s.surfaceType == 'Wall' && s.outsideBoundaryCondition == 'Surface' }
    internal_floors = model.getSurfaces.select { |s| s.surfaceType == 'Floor' && s.outsideBoundaryCondition == 'Surface' }

    if !internal_walls.empty?
      assert internal_walls.all? { |w| w.construction.is_initialized }, "All internal walls should have constructions"
    end

    if !internal_floors.empty?
      assert internal_floors.all? { |f| f.construction.is_initialized }, "All internal floors/ceilings should have constructions"
    end
  end
end
