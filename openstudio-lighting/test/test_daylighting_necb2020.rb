require_relative 'test_helper'

# NECB 2020/2025 4.2.2.1.(10)-(15): the daylighted-area geometry (4.2.2.3./
# 4.2.2.5., unioned) and the input-POWER photocontrol requirement built on it.
# This is the D-57 gate; the legacy NECB 2011 rule it replaced lives behind
# placement: :necb2011 and is pinned by test_daylighting_parity.rb.
class TestDaylightingNecb2020 < Minitest::Test
  DA = OpenStudioLighting::NECB::DaylightedAreas
  REQ = OpenStudioLighting::NECB::DaylightControlRequirement

  # --- fixtures -------------------------------------------------------------

  def add_surface(model, space, points, type, outside = nil)
    vector = OpenStudio::Point3dVector.new
    points.each { |x, y, z| vector << OpenStudio::Point3d.new(x, y, z) }
    surface = OpenStudio::Model::Surface.new(vector, model)
    surface.setSpace(space)
    surface.setSurfaceType(type)
    surface.setOutsideBoundaryCondition(outside) if outside
    surface
  end

  def glazing(model, visible_transmittance)
    simple = OpenStudio::Model::SimpleGlazing.new(model)
    simple.setUFactor(2.0)
    simple.setSolarHeatGainCoefficient(0.4)
    simple.setVisibleTransmittance(visible_transmittance)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setLayers([simple])
    construction
  end

  # A single rectangular space, width x depth x height, with the given windows
  # ([x0, x1, z0, z1] on the y = 0 wall) and skylights ([x0, x1, y0, y1]).
  def box(windows: [], skylights: [], width: 10.0, depth: 8.0, height: 3.0,
          skylight_vt: 0.7, space_type: nil, latitude: nil)
    model = OpenStudio::Model::Model.new
    model.getSite.setLatitude(latitude) if latitude
    space = OpenStudio::Model::Space.new(model)
    space.setName('test space')
    add_surface(model, space, [[0, 0, 0], [0, depth, 0], [width, depth, 0], [width, 0, 0]], 'Floor')
    wall = add_surface(model, space, [[0, 0, height], [0, 0, 0], [width, 0, 0], [width, 0, height]],
                       'Wall', 'Outdoors')
    roof = add_surface(model, space, [[0, 0, height], [width, 0, height], [width, depth, height],
                                     [0, depth, height]], 'RoofCeiling', 'Outdoors')
    windows.each_with_index do |(x0, x1, z0, z1), index|
      vector = OpenStudio::Point3dVector.new
      [[x0, 0, z1], [x0, 0, z0], [x1, 0, z0], [x1, 0, z1]].each { |x, y, z| vector << OpenStudio::Point3d.new(x, y, z) }
      sub = OpenStudio::Model::SubSurface.new(vector, model)
      sub.setName("window #{index}")
      sub.setSurface(wall)
      sub.setSubSurfaceType('FixedWindow')
      sub.setConstruction(glazing(model, 0.6))
    end
    skylights.each_with_index do |(x0, x1, y0, y1), index|
      vector = OpenStudio::Point3dVector.new
      [[x0, y0, height], [x1, y0, height], [x1, y1, height], [x0, y1, height]].each do |x, y, z|
        vector << OpenStudio::Point3d.new(x, y, z)
      end
      sub = OpenStudio::Model::SubSurface.new(vector, model)
      sub.setName("skylight #{index}")
      sub.setSurface(roof)
      sub.setSubSurfaceType('Skylight')
      sub.setConstruction(glazing(model, skylight_vt))
    end
    if space_type
      zone = OpenStudio::Model::ThermalZone.new(model)
      space.setThermalZone(zone)
      OpenStudioLoads.assign_space_types(model, { space.nameString => ['Space Function', space_type] },
                                         vintage: '2020')
      OpenStudioLighting.apply_lights(model, vintage: '2020')
    end
    [model, space]
  end

  # --- geometry: 4.2.2.3. / 4.2.2.5. ---------------------------------------

  def test_primary_and_secondary_use_half_head_height_and_one_head_height_depth
    # 4 m window, head 2.5 m: width 4 + 2 x (2.5/2) = 6.5 m, depth = head = 2.5 m
    _model, space = box(windows: [[2.0, 6.0, 0.5, 2.5]])
    areas = DA.areas(space)
    assert_in_delta 16.25, areas[:primary_sidelighted_m2], 0.02, '4.2.2.3.(3)(a)/(4)(a): 6.5 m x 2.5 m'
    # 4.2.2.3.(8)(a): the secondary band starts where the primary ends and runs
    # one further head height — the legacy port computed NO secondary area at all
    assert_in_delta 16.25, areas[:secondary_sidelighted_m2], 0.02, '4.2.2.3.(6)-(8) secondary band'
    assert_operator areas[:secondary_sidelighted_m2], :>, 0.0, 'legacy computed zero secondary area (L-26)'
  end

  def test_overlapping_windows_are_unioned_not_summed
    # Two 2 m windows 0.5 m apart, head 2.5 -> each band 4.5 m wide, bands OVERLAP.
    # Union spans x 0.75..7.75 = 7.0 m; a per-window sum would give 9.0 m.
    _model, space = box(windows: [[2.0, 4.0, 0.5, 2.5], [4.5, 6.5, 0.5, 2.5]])
    overlapping = DA.areas(space)
    assert_in_delta 7.0 * 2.5, overlapping[:primary_sidelighted_m2], 0.05,
                    '4.2.2.3.(1): combined WITHOUT double-counting overlapping areas'
    assert_operator overlapping[:primary_sidelighted_m2], :<, 9.0 * 2.5,
                    'a per-window sum would double-count the overlap'

    # Same two windows moved apart so the bands do not touch: now the total is the
    # sum (clipped at the room edge), proving the union is not simply shrinking.
    _model2, apart = box(windows: [[2.0, 4.0, 0.5, 2.5], [7.0, 9.0, 0.5, 2.5]])
    separated = DA.areas(apart)
    assert_operator separated[:primary_sidelighted_m2], :>, overlapping[:primary_sidelighted_m2]
  end

  def test_bands_are_clipped_to_the_space_enclosure
    # Window hard against the x = 10 wall: its band cannot extend past the wall.
    _model, space = box(windows: [[7.0, 9.0, 0.5, 2.5]])
    areas = DA.areas(space)
    # band x 5.75..10.25 clipped to 5.75..10.0 = 4.25 m wide, depth 2.5
    assert_in_delta 4.25 * 2.5, areas[:primary_sidelighted_m2], 0.05,
                    '4.2.2.3.(3)(b)/(4)(b): the enclosure bounds the band'
    assert_operator areas[:primary_sidelighted_m2] + areas[:secondary_sidelighted_m2] +
                    areas[:toplighted_m2], :<=, areas[:floor_m2] + 0.01,
                    'no daylighted area escapes the floor'
  end

  def test_skylight_only_space_gets_toplighted_area
    # 2 x 2 skylight, 3 m ceiling: extension 0.7 x 3 = 2.1 m each way -> 6.2 x 6.2.
    # The LEGACY port returns ZERO here (its accumulator sits inside the exterior-
    # window loop), which is half of why L-26's conjunctive test never fires.
    _model, space = box(skylights: [[4.0, 6.0, 3.0, 5.0]])
    areas = DA.areas(space)
    assert_in_delta 6.2 * 6.2, areas[:toplighted_m2], 0.05, '4.2.2.5.(2)(a): 70% of ceiling height'
    legacy = OpenStudioLighting::NECB::Daylighting.skylight_parameters(space)
    assert_in_delta 0.0, legacy[:area_m2], 1e-9, 'the legacy port still returns zero (defect preserved)'
  end

  def test_necb_precedence_primary_beats_toplit_and_secondary_loses_to_both
    # Window and skylight whose areas overlap. 4.2.2.5.(2)(b) caps the skylight
    # extension at the primary sidelighted area, so PRIMARY survives intact and
    # the TOPLIT area is reduced — the opposite of the ASHRAE 90.1 precedence in
    # the openstudio-standards method this geometry was adapted from.
    _model, space = box(windows: [[2.0, 6.0, 0.5, 2.5]], skylights: [[2.0, 6.0, 1.0, 3.0]])
    areas = DA.areas(space)
    assert_in_delta 16.25, areas[:primary_sidelighted_m2], 0.05, 'primary is NOT reduced by the skylight'
    toplit_gross = [8.1, 10.0].min * [5.1, 8.0].min
    assert_operator areas[:toplighted_m2], :<, toplit_gross, '4.2.2.5.(2)(b): toplit stops at the primary'
    assert_in_delta 0.0, areas[:secondary_sidelighted_m2], 0.05,
                    '4.2.2.3.(9): no secondary area beyond an under-skylight area'
    assert_operator areas[:primary_sidelighted_m2] + areas[:secondary_sidelighted_m2] +
                    areas[:toplighted_m2], :<=, areas[:floor_m2] + 0.01
  end

  def test_secondary_never_exceeds_primary_so_the_300_w_test_is_never_decisive_alone
    # Each secondary band is a translate of its primary band and loses every
    # overlap, so total secondary <= total primary and combined <= 2 x primary.
    # Therefore 4.2.2.1.(10)(b)'s 300 W can only be met when (10)(a)'s 150 W
    # already is. Recorded so the redundancy is a known property, not a surprise.
    [{ windows: [[2.0, 6.0, 0.5, 2.5]] },
     { windows: [[0.0, 10.0, 0.0, 3.0]] },
     { windows: [[2.0, 4.0, 0.5, 2.5], [4.5, 6.5, 0.5, 2.5]] },
     { windows: [[0.0, 10.0, 0.5, 2.5]], depth: 3.0 }].each_with_index do |args, index|
      _model, space = box(**args)
      areas = DA.areas(space)
      assert_operator areas[:secondary_sidelighted_m2], :<=, areas[:primary_sidelighted_m2] + 0.01,
                      "case #{index}: secondary <= primary"
    end
  end

  # --- Table 4.2.1.6. control matrix ---------------------------------------

  def test_control_matrix_states_are_all_legal_and_the_residue_is_recorded
    rows = REQ.table['space_types']
    assert_operator rows.size, :>=, 105, 'every NECB space-function catalog name is mapped'
    legal = %w[required not_required not_applicable not_listed unknown]
    rows.each do |name, row|
      assert_includes legal, row['sidelighting'], "#{name} sidelighting"
      assert_includes legal, row['toplighting'], "#{name} toplighting"
    end
    # anything not decided from the code text must be enumerated, not buried
    published = REQ.residue.map { |r| r['space_type'] }
    unresolved = rows.select do |_, r|
      %w[unknown not_listed].include?(r['sidelighting']) || %w[unknown not_listed].include?(r['toplighting'])
    end.keys
    assert_equal unresolved.sort, published.sort,
                 'every column not read straight off the table appears in the published residue list'
    assert_operator REQ.residue.size, :<=, 12, 'the residue stays small enough to file'
  end

  def test_dwelling_units_are_not_listed_rather_than_unknown
    # 4.2.2.1.(10)/(13) reach only spaces requiring the control "in accordance
    # with Table 4.2.1.6.", and 4.2.2.1.(2) ties that to the table's space-by-space
    # types. Dwelling units have no row (their LPD is 8.4.4.5.(2)), so the
    # sentences do not reach them — a determination from the code text, NOT a
    # conservative guess. Getting this wrong photocontrolled 122 apartment spaces.
    %w[general long-term].each do |suffix|
      row = REQ.requirement("Dwelling units #{suffix}")
      assert_equal 'not_listed', row['sidelighting']
      assert_equal 'not_listed', row['toplighting']
    end
    _model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Dwelling units general')
    verdict, audit = evaluate(space)
    refute verdict[:required], 'no photocontrols in a dwelling unit'
    assert_empty audit.warnings.select { |w| w[:action].include?('UNRESOLVED') },
                 'not a conservative-default guess: no unresolved-column warning'
    assert(audit.entries.any? { |e| e[:action].include?('has NO Table 4.2.1.6. row') },
           'the determination is recorded with its reasoning')
  end

  def test_control_matrix_spot_values
    assert_equal 'required', REQ.requirement('Office enclosed > 25 m2')['sidelighting']
    assert_equal 'required', REQ.requirement('Office enclosed > 25 m2')['toplighting']
    # 'X' in the corrected table (hbix#88) — it was not_required only in the
    # corrupt extraction. A genuine '-' row instead:
    assert_equal 'required', REQ.requirement('Library reading area')['sidelighting']
    assert_equal 'not_required', REQ.requirement('Dormitory living quarters')['sidelighting']
    # Table 4.2.1.6. refers these two out to other articles entirely
    assert_equal 'not_applicable', REQ.requirement('Guest room')['sidelighting']
    assert_equal 'not_applicable', REQ.requirement('Storage garage interior')['toplighting']
    # schedule-letter suffixes resolve to the same row
    assert_equal REQ.requirement('Computer/Server room'), REQ.requirement('Computer/Server room-sch-C')
    assert REQ.requirement('Retail facility mall concourse')['retail'], '4.2.2.1.(12)(c) retail flag'
  end

  # --- 4.2.2.1.(10)/(13): the power tests ----------------------------------

  def evaluate(space, **kwargs)
    audit = OpenStudioLighting::AuditLog.new
    [REQ.evaluate(space, audit: audit, **kwargs), audit]
  end

  def test_sidelighting_required_when_primary_power_reaches_150_w
    # Office enclosed > 25 m2 = 7.1 W/m2; full-wall glazing head 3 m gives a
    # 10 m x 3 m primary band = 30 m2 -> 213 W >= 150 W.
    _model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    assert verdict[:sidelighting][:required], verdict[:sidelighting][:reason]
    assert_match(/4\.2\.2\.1\.\(10\)\(a\)/, verdict[:sidelighting][:reason])
    assert verdict[:required]
  end

  def test_sidelighting_not_required_below_both_thresholds
    # One small window: 6.5 m x 2.5 m = 16.25 m2 primary -> 115 W < 150 W, and
    # 32.5 m2 primary + secondary -> 231 W < 300 W.
    _model, space = box(windows: [[2.0, 6.0, 0.5, 2.5]], space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    refute verdict[:sidelighting][:required], verdict[:sidelighting][:reason]
    assert_match(/below both/, verdict[:sidelighting][:reason])
  end

  def test_toplighting_alone_qualifies_a_space_with_no_windows
    # THE L-26 DEFECT, DIRECTLY: the legacy criteria ANDed sidelighting and
    # skylight tests, so a skylight-only space could never qualify. (13) is
    # independent of (10).
    _model, space = box(skylights: [[4.0, 6.0, 3.0, 5.0]], space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    refute verdict[:sidelighting][:required], 'no glazing: 4.2.2.1.(12)(b) excepts sidelighting'
    assert verdict[:toplighting][:required], verdict[:toplighting][:reason]
    assert_match(/4\.2\.2\.1\.\(13\)/, verdict[:toplighting][:reason])
    assert verdict[:required], 'the space qualifies on toplighting ALONE'
  end

  def test_sidelighting_alone_qualifies_a_space_with_no_skylights
    _model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    assert verdict[:sidelighting][:required]
    refute verdict[:toplighting][:required], 'no skylights: zero toplighted area'
    assert verdict[:required], 'the space qualifies on sidelighting ALONE'
  end

  # --- exceptions ----------------------------------------------------------

  def test_glazing_under_2_m2_excepts_sidelighting
    _model, space = box(windows: [[2.0, 3.0, 2.0, 2.5]], space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    refute verdict[:sidelighting][:required]
    assert_match(/4\.2\.2\.1\.\(12\)\(b\)/, verdict[:sidelighting][:reason])
  end

  def test_retail_space_excepts_sidelighting_but_not_toplighting
    _model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], skylights: [[4.0, 6.0, 3.0, 5.0]],
                        space_type: 'Retail facility mall concourse')
    verdict, = evaluate(space)
    refute verdict[:sidelighting][:required]
    assert_match(/4\.2\.2\.1\.\(12\)\(c\)/, verdict[:sidelighting][:reason])
    assert verdict[:toplighting][:required], '(12) excepts (10) only — (13) is untouched'
  end

  def test_obstruction_ratio_of_two_excepts_sidelighting
    model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    assert verdict[:sidelighting][:required], 'baseline: required with no adjacent structure'

    # a wall 5 m from the glazing rising 13 m above the window head: ratio 2.6
    group = OpenStudio::Model::ShadingSurfaceGroup.new(model)
    vector = OpenStudio::Point3dVector.new
    [[0, -5, 0], [10, -5, 0], [10, -5, 16], [0, -5, 16]].each { |x, y, z| vector << OpenStudio::Point3d.new(x, y, z) }
    OpenStudio::Model::ShadingSurface.new(vector, model).setShadingSurfaceGroup(group)

    obstructed, = evaluate(space)
    refute obstructed[:sidelighting][:required]
    assert_match(/4\.2\.2\.1\.\(12\)\(a\)/, obstructed[:sidelighting][:reason])
  end

  def test_low_visible_transmittance_excepts_toplighting
    _model, space = box(skylights: [[4.0, 6.0, 3.0, 5.0]], skylight_vt: 0.3,
                        space_type: 'Office enclosed > 25 m2')
    verdict, = evaluate(space)
    refute verdict[:toplighting][:required]
    assert_match(/4\.2\.2\.1\.\(15\)\(b\)/, verdict[:toplighting][:reason])
  end

  def test_above_55_north_with_under_200_w_excepts_toplighting
    # 0.8 x 0.8 skylight, 3 m ceiling -> 5.0 x 5.0 = 25 m2 -> 7.1 x 25 = 178 W:
    # over (13)'s 150 W but under (15)(c)'s 200 W.
    args = { skylights: [[4.0, 4.8, 3.0, 3.8]], space_type: 'Office enclosed > 25 m2' }
    _model, south = box(**args, latitude: 45.0)
    verdict_south, = evaluate(south)
    assert verdict_south[:toplighting][:required], verdict_south[:toplighting][:reason]
    assert_operator verdict_south[:toplighting][:power_w], :<, 200.0

    _model2, north = box(**args, latitude: 60.0)
    verdict_north, = evaluate(north)
    refute verdict_north[:toplighting][:required]
    assert_match(/4\.2\.2\.1\.\(15\)\(c\)/, verdict_north[:toplighting][:reason])
  end

  def test_table_column_closes_the_gate_entirely
    _model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], skylights: [[4.0, 6.0, 3.0, 5.0]],
                        space_type: 'Dormitory living quarters')
    verdict, = evaluate(space)
    refute verdict[:required], 'Table 4.2.1.6. requires neither column for this space type'
    assert_match(/Table 4\.2\.1\.6\./, verdict[:sidelighting][:reason])
    assert_match(/Table 4\.2\.1\.6\./, verdict[:toplighting][:reason])
  end

  def test_unresolved_table_column_warns_and_takes_the_conservative_default
    # A space type with NO Table 4.2.1.6. row at all — the only unresolved kind
    # left once hbix#88 was fixed (the four extraction CONFLICTs are resolved).
    args = { windows: [[0.0, 30.0, 0.0, 3.0]], width: 30.0,
             space_type: 'Audience seating area permanent - convention centre' }
    _model, space = box(**args)
    verdict, audit = evaluate(space)
    assert verdict[:sidelighting][:required], 'conservative default: required'
    assert(audit.warnings.any? { |w| w[:action].include?('TABLE 4.2.1.6. SIDELIGHTING COLUMN IS UNRESOLVED') },
           'the unresolved column is SHOUTED, never silent')

    _model2, space2 = box(**args)
    lenient, lenient_audit = evaluate(space2, unknown_default: :not_required)
    refute lenient[:sidelighting][:required], 'the caller can flip the default'
    refute_empty lenient_audit.warnings, 'flipping it still warns'
  end

  # --- wiring: add_controls / reference_daylighting -------------------------

  def test_controls_are_placed_with_a_daylighted_area_fraction_not_1_0
    model, space = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    created = OpenStudioLighting.add_daylighting_controls(model, vintage: '2020', placement: :necb2020,
                                                          audit: audit)
    assert_equal 1, created
    zone = space.thermalZone.get
    assert zone.primaryDaylightingControl.is_initialized
    fraction = zone.fractionofZoneControlledbyPrimaryDaylightingControl
    # primary 30 m2 + secondary 30 m2 of an 80 m2 floor = 0.75
    assert_in_delta 0.75, fraction, 0.02,
                    '4.2.2.1.(10) controls the lighting IN the daylighted areas, not the whole room'
    assert_operator fraction, :<, 1.0
    control = zone.primaryDaylightingControl.get
    assert_equal 'Stepped', control.lightingControlType
    assert_equal 3, control.numberofSteppedControlSteps,
                 '4.2.2.1.(11)(a)(i): 67% / 33% / off, not the 2011 two-step minimum'
    assert(audit.entries.any? { |e| e[:ruling] == 'D-57' }, 'the ruling is cited')
  end

  def test_legacy_2011_placement_is_still_reachable_and_shouts
    model, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    created = OpenStudioLighting.add_daylighting_controls(model, vintage: '2020',
                                                          placement: :necb2011, audit: audit)
    assert_equal 0, created, 'the 2011 criteria cannot qualify a window-only space (L-26)'
    assert(audit.warnings.any? { |w| w[:action].include?('LEGACY NECB 2011 THRESHOLD EVALUATION IN USE') })
  end

  def test_reference_daylighting_defaults_to_the_2020_rule
    model, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_daylighting(model, vintage: '2020', audit: audit)
    assert_equal 1, model.getDaylightingControls.size,
                 'the reference now gets photocontrols where 4.2.2.1.(10) requires them'
    assert(audit.entries.any? { |e| e[:ruling].to_s.include?('D-57') && e[:level] == :decision })
    # the 2011 alias still reaches the legacy rule for the parity gate
    legacy_model, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    OpenStudioLighting::NECB.reference_daylighting(legacy_model, vintage: '2020', placement: :necb_default,
                                                  office_match: :legacy)
    assert_equal 0, legacy_model.getDaylightingControls.size
  end

  def test_unevaluated_1500_hour_exception_is_declared_every_run
    model, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting.add_daylighting_controls(model, vintage: '2020', placement: :necb2020, audit: audit)
    assert(audit.warnings.any? { |w| w[:action].include?('4.2.2.1.(15)(a) EXCEPTION IS NOT EVALUATED') },
           'the un-modellable exception is declared, not hidden')
    assert(audit.entries.any? { |e| e[:action].include?('ROOF') && e[:action].include?('MONITORS') },
           'roof monitors being undetectable is declared')
  end

  # --- the deprecated `option:` alias -------------------------------------
  # `placement:` is the single selector now; `option:` still works (callers
  # exist in the wild) and must land on the SAME rule it used to, loudly.

  def test_deprecated_option_alias_still_selects_the_same_rule
    # option: 'NECB_Default' == placement: :necb2020, end to end
    model, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    audit = OpenStudioLighting::AuditLog.new
    created = OpenStudioLighting.add_daylighting_controls(model, vintage: '2020', option: 'NECB_Default',
                                                          audit: audit)
    assert_equal 1, created
    assert_equal 3, model.getThermalZones.first.primaryDaylightingControl.get.numberofSteppedControlSteps,
                 'the 2020 rule ran, not the blanket one'
    deprecation = audit.entries.find { |e| e[:action].include?('`option:` argument is DEPRECATED') }
    refute_nil deprecation, 'passing the deprecated kwarg is audited'
    assert_equal :necb2020, deprecation[:inputs][:placement_used]

    # option: 'NECB_Default' + placement: :necb2011 still reaches the legacy rule
    legacy, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    assert_equal 0, OpenStudioLighting.add_daylighting_controls(legacy, vintage: '2020', option: 'NECB_Default',
                                                                placement: :necb2011)

    # option: 'all' wins over placement:, exactly as it silently used to
    blanket, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    blanket_audit = OpenStudioLighting::AuditLog.new
    assert_equal 1, OpenStudioLighting.add_daylighting_controls(blanket, vintage: '2020', option: 'all',
                                                                placement: :necb2011, audit: blanket_audit)
    assert_equal 2, blanket.getThermalZones.first.primaryDaylightingControl.get.numberofSteppedControlSteps
    assert_in_delta 1.0, blanket.getThermalZones.first.fractionofZoneControlledbyPrimaryDaylightingControl, 1e-9,
                    'the blanket path controls the whole zone'
    assert(blanket_audit.entries.any? { |e| e[:inputs] && e[:inputs][:placement_used] == :all })
  end

  def test_placement_default_is_the_blanket_rule_and_unknowns_raise
    model, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    created = OpenStudioLighting.add_daylighting_controls(model, vintage: '2020')
    assert_equal 1, created
    assert_equal 2, model.getThermalZones.first.primaryDaylightingControl.get.numberofSteppedControlSteps,
                 'bare add_daylighting_controls is still the legacy blanket behaviour (placement: :all)'

    other, = box(windows: [[0.0, 10.0, 0.0, 3.0]], space_type: 'Office enclosed > 25 m2')
    assert_raises(ArgumentError) { OpenStudioLighting.add_daylighting_controls(other, placement: :necb2050) }
  end
end
