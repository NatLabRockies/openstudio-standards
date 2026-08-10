require_relative 'test_helper'

# Daylighted-area geometry parity vs legacy get_parameters_sidelighting /
# get_parameters_skylight, plus NECB_Default selection parity vs
# model_add_daylighting_controls. Repo bundle only.
class TestDaylightingParity < Minitest::Test
  include FixtureHelper

  def self.legacy
    @legacy ||= begin
      require 'openstudio-standards' # the PINNED oracle (legacy_pin/Gemfile)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy
    if std == :unavailable
      msg = 'legacy oracle not bundled — run under BUNDLE_GEMFILE=legacy_pin/Gemfile'
      ENV['LEGACY_PIN_REQUIRED'] == '1' ? flunk(msg) : skip(msg)
    end
    std
  end

  def add_surface(model, space, points, type)
    vec = OpenStudio::Point3dVector.new
    points.each { |x, y, z| vec << OpenStudio::Point3d.new(x, y, z) }
    surface = OpenStudio::Model::Surface.new(vec, model)
    surface.setSpace(space)
    surface.setSurfaceType(type)
    surface
  end

  def glazing_construction(model, vt)
    glazing = OpenStudio::Model::SimpleGlazing.new(model)
    glazing.setUFactor(2.0)
    glazing.setSolarHeatGainCoefficient(0.4)
    glazing.setVisibleTransmittance(vt)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([glazing])
    construction
  end

  # Build a clean 10x8x3 box with one south exterior wall + optional window/skylight.
  def build_case(window: nil, skylight: nil)
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.new(model)
    floor = add_surface(model, space, [[0, 0, 0], [0, 8, 0], [10, 8, 0], [10, 0, 0]], 'Floor')
    wall = add_surface(model, space, [[0, 0, 3], [0, 0, 0], [10, 0, 0], [10, 0, 3]], 'Wall')
    wall.setOutsideBoundaryCondition('Outdoors')
    roof = add_surface(model, space, [[0, 0, 3], [10, 0, 3], [10, 8, 3], [0, 8, 3]], 'RoofCeiling')
    roof.setOutsideBoundaryCondition('Outdoors')

    if window
      x0, x1, z0, z1 = window
      vec = OpenStudio::Point3dVector.new
      [[x0, 0, z1], [x0, 0, z0], [x1, 0, z0], [x1, 0, z1]].each { |x, y, z| vec << OpenStudio::Point3d.new(x, y, z) }
      sub = OpenStudio::Model::SubSurface.new(vec, model)
      sub.setSurface(wall)
      sub.setSubSurfaceType('FixedWindow')
      sub.setConstruction(glazing_construction(model, 0.6))
    end
    if skylight
      x0, x1, y0, y1 = skylight
      vec = OpenStudio::Point3dVector.new
      [[x0, y0, 3], [x1, y0, 3], [x1, y1, 3], [x0, y1, 3]].each { |x, y, z| vec << OpenStudio::Point3d.new(x, y, z) }
      sub = OpenStudio::Model::SubSurface.new(vec, model)
      sub.setSurface(roof)
      sub.setSubSurfaceType('Skylight')
      sub.setConstruction(glazing_construction(model, 0.7))
    end
    [model, space, floor]
  end

  def legacy_sidelighting(std, space, floor)
    floor_vertices = [floor.vertices]
    std.get_parameters_sidelighting(daylight_space: space, floor_surface: floor,
                                    floor_vertices: floor_vertices, floor_area: floor.netArea,
                                    primary_sidelighted_area: 0.0, area_weighted_vt_handle: 0.0,
                                    window_area_sum: 0.0)
  end

  def test_sidelighting_area_parity
    std = legacy
    cases = [
      { window: [2.0, 6.0, 0.8, 2.5] },   # mid-wall window
      { window: [0.2, 3.0, 0.5, 2.9] },   # near-corner window (side distance < 0.6 m)
      { window: [0.0, 10.0, 0.0, 3.0] }   # full-wall glazing
    ]
    cases.each_with_index do |c, index|
      model, space, floor = build_case(**c)
      legacy_psa, legacy_vt, legacy_win = legacy_sidelighting(std, space, floor)
      gem = OpenStudioLighting::NECB::Daylighting.sidelighting_parameters(space)
      assert_in_delta legacy_psa, gem[:area_m2], 1e-9, "case #{index}: primary sidelighted area"
      assert_in_delta legacy_vt, gem[:vt_handle], 1e-9, "case #{index}: VT handle"
      assert_in_delta legacy_win, gem[:window_area_m2], 1e-9, "case #{index}: window area"
    end
  end

  def test_skylight_area_parity
    std = legacy
    # skylight + window: the window loop re-computes the width/length, then the
    # area is accumulated ONCE (#2119 moved the accumulation out of that loop).
    model, space, = build_case(window: [2.0, 6.0, 0.8, 2.5], skylight: [4.0, 6.0, 3.0, 5.0])
    legacy_area, legacy_vt, legacy_sum = std.get_parameters_skylight(
      daylight_space: space, skylight_area_weighted_vt_handle: 0.0,
      skylight_area_sum: 0.0, daylighted_under_skylight_area: 0.0)
    gem = OpenStudioLighting::NECB::Daylighting.skylight_parameters(space)
    assert_in_delta legacy_area, gem[:area_m2], 1e-9, 'daylighted area under skylight'
    assert_in_delta legacy_vt, gem[:vt_handle], 1e-9
    assert_in_delta legacy_sum, gem[:skylight_area_m2], 1e-9

    # skylight only, NO exterior window: this used to compute ZERO on both sides
    # (the accumulator sat inside the exterior-window loop). #2119 fixed legacy;
    # the quarantine port mirrors it, so both are now NONZERO and equal.
    model2, space2, = build_case(skylight: [4.0, 6.0, 3.0, 5.0])
    legacy_area2, legacy_vt2, legacy_sum2 = std.get_parameters_skylight(
      daylight_space: space2, skylight_area_weighted_vt_handle: 0.0,
      skylight_area_sum: 0.0, daylighted_under_skylight_area: 0.0)
    gem2 = OpenStudioLighting::NECB::Daylighting.skylight_parameters(space2)
    assert_operator legacy_area2, :>, 0.0, 'post-#2119 legacy: a skylight-only space has a real daylighted area'
    assert_in_delta legacy_area2, gem2[:area_m2], 1e-9, 'skylight-only daylighted area tracks fixed legacy'
    assert_in_delta legacy_vt2, gem2[:vt_handle], 1e-9
    assert_in_delta legacy_sum2, gem2[:skylight_area_m2], 1e-9
  end

  def test_necb_default_selection_parity_on_fixture
    std = legacy
    # office-tagged fixture with windows. Post-#2119 legacy: the skylight
    # criteria no longer apply to window-only spaces, and the >=25 m2 office
    # exemption matches the NECB2020 name — so controls ARE created. The gate is
    # equality with whatever legacy produces, never a hardcoded count.
    legacy_model = load_fixture
    map = legacy_model.getSpaces.to_h { |s| [s.nameString, ['Space Function', 'Office enclosed > 25 m2']] }
    OpenStudioLoads.assign_space_types(legacy_model, map, vintage: '2020')
    wall = legacy_model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    wall.setWindowToWallRatio(0.4)
    gem_model = legacy_model.clone(true).to_Model

    std.model_add_daylighting_controls(model: legacy_model, daylighting_type: 'NECB_Default')
    audit = OpenStudioLighting::AuditLog.new
    # placement: :necb2011 names the legacy rule explicitly — neither of the
    # other two placements does what legacy does (:all is the blanket default of
    # this entry point, :necb2020 is the code rule, 4.2.2.1.(10)-(15), D-57).
    # This gate exists to prove the 2011 port is still faithful.
    created = OpenStudioLighting.add_daylighting_controls(gem_model, vintage: '2020',
                                                          placement: :necb2011, audit: audit)

    legacy_controls = legacy_model.getDaylightingControls
    gem_controls = gem_model.getDaylightingControls

    assert_operator legacy_controls.size, :>, 0,
                    'post-#2119 legacy premise: the 2011 criteria DO place controls on this fixture'
    assert_equal legacy_controls.size, gem_controls.size, 'same control count as legacy'
    assert_equal legacy_controls.size, created, 'every legacy control is one the gem reports creating'

    # Same spaces, same sensor positions (legacy puts one sensor at the centre
    # of the lowest-floor bounding box, 0.8 m up).
    assert_equal legacy_controls.map(&:nameString).sort, gem_controls.map(&:nameString).sort,
                 'controls land on the same spaces'
    legacy_pos = legacy_controls.to_h { |c| [c.nameString, [c.positionXCoordinate, c.positionYCoordinate, c.positionZCoordinate]] }
    gem_controls.each do |control|
      expected = legacy_pos[control.nameString]
      %w[x y z].each_with_index do |axis, i|
        actual = [control.positionXCoordinate, control.positionYCoordinate, control.positionZCoordinate][i]
        assert_in_delta expected[i], actual, 1e-9, "#{control.nameString}: sensor #{axis} position"
      end
      assert_equal 'Stepped', control.lightingControlType
    end

    # #2119 replaced legacy's exact 'Office - enclosed' comparison with
    # /office\s*-?\s*enclosed/i, so the office-name-drift warning must NOT fire
    # any more — the exemption matches the NECB2020 names on both sides.
    refute(audit.warnings.any? { |w| w[:action].include?("'Office - enclosed'") },
           'the 2020 office-name drift warning is obsolete: #2119 made the legacy matcher a regex')
  end
end
