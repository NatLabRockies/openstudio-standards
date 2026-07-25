require_relative 'test_helper'
require 'tmpdir'

# P4 gate: the greenfield reference-envelope transform (8.4.4.3/8.4.4.4) — golden
# assertions on scaling, absorptance, shading census, lightweight rebuild, air
# leakage arithmetic, coverage emission; E2E clean E+ run; composition smoke with
# openstudio-hvac (one clone, one audit).
class TestReferenceEnvelope < Minitest::Test
  include FixtureHelper

  HDD = 3890
  FDWR_LIMIT = 0.40 # 3.2.1.4.(1): hdd <= 4000 -> flat 0.40 (linear piece starts above 4000)

  # a "proposed" model: oversized windows + both kinds of shading.
  # NOTE (was STALE): this comment used to claim a "skylight" was built here
  # too, but the method below never created one — the SRR/skylight reference
  # path (scale_fenestration_to_limits's roof-scaling branch in
  # necb/reference.rb) had ZERO test coverage in this suite as a result. That
  # path is now covered separately in test_necb_skylight_srr_reference.rb,
  # which builds its own hostile-SRR fixture; this proposed_model deliberately
  # stays skylight-free so the FDWR/shading/absorptance/air-leakage tests below
  # are unaffected.
  def proposed_model
    model = load_fixture
    walls = model.getSurfaces.select { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    walls.each { |w| w.setWindowToWallRatio(0.6) }

    space_shading = OpenStudio::Model::ShadingSurfaceGroup.new(model)
    space_shading.setShadingSurfaceType('Building')
    space_shading.setName('Overhangs')
    site_shading = OpenStudio::Model::ShadingSurfaceGroup.new(model)
    site_shading.setShadingSurfaceType('Site')
    site_shading.setName('Neighbour building')
    model
  end

  def reference(model, **kwargs)
    audit = OpenStudioEnvelope::AuditLog.new
    OpenStudioEnvelope::NECB.reference_envelope(model, vintage: '2020', hdd: HDD, audit: audit, **kwargs)
    audit
  end

  def test_fdwr_scaled_proportionally_not_rebuilt
    model = proposed_model
    before = OpenStudioEnvelope::Geometry.exposed_walls(model)
    window_count_before = model.getSubSurfaces.size
    assert_operator before[:fdwr], :>, FDWR_LIMIT, 'fixture starts over the limit'

    audit = reference(model)
    after = OpenStudioEnvelope::Geometry.exposed_walls(model)
    assert_in_delta FDWR_LIMIT, after[:fdwr], 0.005, 'scaled down to the limit'
    assert_equal window_count_before, model.getSubSurfaces.size,
                 '8.4.4.3.(3) scales EXISTING fenestration — no rebuild, same window count'
    decision = audit.entries.find { |e| e[:action].include?('scaled proportionally per orientation') }
    assert_match(/8\.4\.4\.3\.\(3\)/, decision[:article])
  end

  def test_shading_rules
    model = proposed_model
    audit = reference(model)
    types = model.getShadingSurfaceGroups.map(&:shadingSurfaceType)
    assert_equal ['Site'], types, 'Building/Space shading removed, Site (nearby structures) kept'
    decision = audit.entries.find { |e| e[:article].to_s.include?('3.(4)-(5)') }
    assert_equal 1, decision[:inputs][:site_groups_kept]
  end

  def hostile_roof_absorptance!(model, value)
    model.getSurfaces.select { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
         .each do |s|
      outer = s.construction.get.to_Construction.get.layers.first.to_OpaqueMaterial.get
      outer.setSolarAbsorptance(OpenStudio::OptionalDouble.new(value))
    end
  end

  # KEEP branch strengthened + DEFECT reproduction.
  #
  # The original test only ever checked the 'set' (actual_roof_absorptance_used:
  # true) branch, and never asserted anything about 'keep' at all — a classic
  # weak assertion: the KEEP branch could silently misbehave and this test would
  # still pass.
  #
  # Giving 'keep' a HOSTILE pre-set absorptance (0.3, not the fixture's
  # coincidental 0.7 default) exposes a real defect: apply_lightweight_construction
  # (reference.rb:137-165) rebuilds EVERY opaque assembly — reached
  # unconditionally, regardless of actual_roof_absorptance_used — into a fresh
  # OpenStudio::Model::MasslessOpaqueMaterial without copying solar/thermal/
  # visible absorptance from the original layer. The SDK's own default
  # solarAbsorptance for a new MasslessOpaqueMaterial is 0.7 (verified via
  # `OpenStudio::Model::MasslessOpaqueMaterial.new(...).solarAbsorptance`) —
  # IDENTICAL to roof_absorptance_if_actual_used in envelope_rules_2020.json —
  # so the reference roof absorptance ends up at 0.7 EVEN WHEN THE FLAG IS
  # FALSE, which happens to look correct only because the NECB target and the
  # SDK default coincide. A hostile 0.3 proves it: 8.4.4.3.(2)(a) says the
  # reference "keeps" the proposed value when actual_roof_absorptance_used is
  # false, but the model shows 0.7 instead of 0.3.
  #
  # This also means the 'set' assertion below has never actually proven that
  # apply_roof_absorptance's mutation survives to the end of the pipeline —
  # only that the rebuild's own default happens to match. That branch is
  # unaffected (still 0.7, now via a hostile 0.3 precondition instead of the
  # fixture's stock 0.7), so it is left green.
  #
  # EXPECTED TO FAIL until apply_lightweight_construction preserves the
  # pre-rebuild absorptance. See openstudio-envelope/lib/openstudio_envelope/necb/reference.rb:137.
  def test_roof_absorptance_only_when_actual_used
    keep = proposed_model
    hostile_roof_absorptance!(keep, 0.3)
    reference(keep) # default: actual_roof_absorptance_used false -> must NOT touch absorptance
    keep_roof = keep.getSurfaces.find { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
    keep_outer = keep_roof.construction.get.to_Construction.get.layers.first.to_OpaqueMaterial.get
    assert_in_delta 0.3, keep_outer.solarAbsorptance, 1e-6,
                    'DEFECT: actual_roof_absorptance_used: false must leave the hostile proposed roof ' \
                    'absorptance untouched (8.4.4.3.(2)(a)), but apply_lightweight_construction rebuilds ' \
                    'every opaque assembly into a fresh MasslessOpaqueMaterial without copying absorptance — ' \
                    "the SDK's own default (0.7) silently overwrites it regardless of the flag. " \
                    'See necb/reference.rb:137 (apply_lightweight_construction).'

    set = proposed_model
    hostile_roof_absorptance!(set, 0.3)
    reference(set, actual_roof_absorptance_used: true)

    set_roof = set.getSurfaces.find { |s| s.surfaceType == 'RoofCeiling' && s.outsideBoundaryCondition == 'Outdoors' }
    outer = set_roof.construction.get.to_Construction.get.layers.first.to_OpaqueMaterial.get
    assert_in_delta 0.7, outer.solarAbsorptance, 1e-6
  end

  def test_lightweight_and_air_leakage
    model = proposed_model
    audit = reference(model)

    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    c = wall.construction.get.to_Construction.get
    assert_match(/Lightweight/, c.nameString)
    assert_equal 1, c.layers.size
    assert c.layers.first.to_MasslessOpaqueMaterial.is_initialized, 'zero thermal mass'
    # 0.27595 = 1/(1/0.265 - wall films): table U incl. films (default convention)
    assert_in_delta 0.27595, c.thermalConductance.to_f, 1e-3, 'Ut unchanged by the lightweight rebuild'

    infiltration = model.getSpaceInfiltrationDesignFlowRates
    assert_equal model.getSpaces.size, infiltration.size
    decision = audit.entries.find { |e| e[:action] == 'air-leakage default applied' }
    assert_match(/\(5\/75\)\^0\.6 x 1\.5/, decision[:value])
    assert_match(/8\.4\.2\.9\.\(2\)/, decision[:article])
    # rate sanity: (5/75)^0.6 = 0.1974; x1.5 = 0.296; xS/A_AGW > 0.296
    rate = infiltration.first.flowperExteriorWallArea.get * 1000.0
    assert_operator rate, :>, 0.29
    # D-19: no proposed infiltration -> constant convention (A=1)
    assert_in_delta 1.0, infiltration.first.constantTermCoefficient, 1e-9
  end

  # D-19: the reference inherits the PROPOSED's infiltration modulation
  # (E+ modifier coefficients + schedule) — identical design totals with
  # asymmetric conventions change delivered infiltration ~2x. A proposed
  # whose total deviates from the untested 8.4.3.3.(3) default warns.
  def test_air_leakage_inherits_proposed_convention_and_checks_total
    model = proposed_model
    sched = model.alwaysOnDiscreteSchedule
    model.getSpaceInfiltrationDesignFlowRates.each(&:remove) # fixture defaults would win the donor pick
    model.getSpaces.each do |space|
      i = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
      i.setFlowperExteriorSurfaceArea(0.00001) # far below the default -> warn
      i.setConstantTermCoefficient(0.0)
      i.setVelocityTermCoefficient(0.224) # DOE-2 wind-driven convention
      i.setSchedule(sched)
      i.setSpace(space)
    end
    audit = reference(model)
    i = model.getSpaceInfiltrationDesignFlowRates.min_by(&:nameString)
    assert_match(/NECB Ref Infiltration/, i.nameString, 'proposed objects replaced')
    assert_in_delta 0.0, i.constantTermCoefficient, 1e-9, 'wind-driven convention inherited'
    assert_in_delta 0.224, i.velocityTermCoefficient, 1e-9
    assert_equal sched.nameString, i.schedule.get.nameString
    assert(audit.warnings.any? { |w| w[:action] =~ /DEVIATES from the untested 8\.4\.3\.3\.\(3\) default/ },
           'below-default proposed infiltration warns (permissive direction)')
  end

  # D-21 / 3.2.4.2.(1)(c): S is the enclosure of the CONDITIONED volume. A
  # 10x10x3 conditioned box under a 10x10x2 unconditioned attic: S = walls
  # (120) + ground slab (100) + ceiling-to-attic (100) = 320 m2; the attic
  # roof (100) and gables (80) are NOT envelope. A_AGW = 120 (conditioned
  # walls only). Installed total must equal (5/75)^0.6 x 1.5 x S, and the
  # attic must receive NO infiltration object (its exterior walls sit outside
  # A_AGW — giving it flow-per-wall-area would re-inflate the total).
  def test_air_leakage_envelope_area_excludes_attic_per_3_2_4_2
    model = OpenStudio::Model::Model.new
    print_at = lambda do |z|
      pts = OpenStudio::Point3dVector.new
      [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| pts << OpenStudio::Point3d.new(x, y, z) }
      pts
    end
    cond = OpenStudio::Model::Space.fromFloorPrint(print_at.call(0.0), 3.0, model).get
    attic = OpenStudio::Model::Space.fromFloorPrint(print_at.call(3.0), 2.0, model).get
    spaces = OpenStudio::Model::SpaceVector.new
    [cond, attic].each { |s| spaces << s }
    OpenStudio::Model.matchSurfaces(spaces) # pairs ceiling <-> attic floor
    attic.setPartofTotalFloorArea(false)
    [cond, attic].each { |s| s.setThermalZone(OpenStudio::Model::ThermalZone.new(model)) }

    audit = OpenStudioEnvelope::AuditLog.new
    OpenStudioEnvelope::NECB::Reference.apply_air_leakage_default(model, '8.4.4', audit)

    decision = audit.entries.find { |e| e[:action] == 'air-leakage default applied' }
    assert_in_delta 320.0, decision[:inputs][:envelope_area_m2], 0.5, 'attic roof/gables excluded; ceiling included'
    assert_in_delta 120.0, decision[:inputs][:ag_wall_area_m2], 0.5, 'conditioned walls only'

    infiltration = model.getSpaceInfiltrationDesignFlowRates
    assert_equal 1, infiltration.size, 'attic receives NO infiltration object'
    assert_equal cond.handle, infiltration.first.space.get.handle
    installed_l_s = infiltration.first.flowperExteriorWallArea.get * cond.exteriorWallArea * 1000.0
    expected_l_s = ((5.0 / 75.0)**0.6) * 1.5 * 320.0
    assert_in_delta expected_l_s, installed_l_s, 0.2, 'installed total = code default over the (1)(c) enclosure'
  end

  def test_coverage_emitted_all_16_articles
    audit = reference(proposed_model)
    coverage = audit.entries.select { |e| e[:step] == :coverage }
    assert_equal 16, coverage.size # 14 + 8.4.1.1 (envelope slice) + 8.4.2.9 air leakage
    ref3 = coverage.find { |e| e[:article] == '8.4.4.3.' }
    assert_equal 'implemented', ref3[:inputs][:status]
    assert_operator ref3[:inputs][:decisions_citing], :>, 0
    # honest gaps still warn
    assert(coverage.any? { |e| e[:level] == :warning && e[:article] == '3.2.4.1.' })
    assert JSON.parse(audit.to_json).size > 20
  end

  def test_reference_envelope_runs_in_energyplus
    skip 'openstudio CLI not available' unless openstudio_cli?
    dir = Dir.mktmpdir('osenv-ref-')
    model = attach_weather!(proposed_model)
    reference(model)
    model.getThermalZones.each { |z| z.setUseIdealAirLoads(true) }
    run_dir = run_energyplus!(model, "#{dir}/ref")
    assert_clean_energyplus_run(run_dir, 'reference envelope')
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  # Composition: HVAC + envelope reference on ONE clone with ONE audit.
  def test_composition_with_openstudio_hvac
    hvac_lib = File.expand_path('../../openstudio-hvac/lib/openstudio_hvac', __dir__)
    skip 'openstudio-hvac not present' unless File.exist?("#{hvac_lib}.rb")
    require hvac_lib

    proposed = proposed_model
    zones = proposed.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(proposed, 'Baseboard gas boiler', zones)
    types = proposed.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }

    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(proposed, vintage: '2020',
                                                 building: { storeys: 1, zone_types: types,
                                                             winter_design_temp_c: -20 },
                                                 audit: audit)
    OpenStudioEnvelope::NECB.reference_envelope(result.model, vintage: '2020', hdd: HDD, audit: audit)

    steps = audit.entries.map { |e| e[:step] }.uniq
    %i[selection build rules efficiency coverage reference prescriptive].each do |s|
      assert_includes steps, s, 'one audit spans HVAC + envelope reference generation'
    end
    refute_empty result.model.getAirLoopHVACs, 'HVAC reference present'
    wall = result.model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    assert_match(/Lightweight/, wall.construction.get.nameString, 'envelope reference present on the SAME clone')
    assert JSON.parse(audit.to_json).size > 50
  end
end
