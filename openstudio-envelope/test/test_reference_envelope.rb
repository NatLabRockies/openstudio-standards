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

  # a "proposed" model: oversized windows, skylight, both kinds of shading
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

  def test_roof_absorptance_only_when_actual_used
    keep = proposed_model
    reference(keep) # default: not flagged
    set = proposed_model
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
    assert_in_delta 0.265, c.thermalConductance.to_f, 1e-3, 'Ut unchanged by the lightweight rebuild'

    infiltration = model.getSpaceInfiltrationDesignFlowRates
    assert_equal model.getSpaces.size, infiltration.size
    decision = audit.entries.find { |e| e[:action] == 'air-leakage default applied' }
    assert_match(/\(5\/75\)\^0\.6 x 1\.5/, decision[:value])
    assert_match(/8\.4\.2\.9\.\(2\)/, decision[:article])
    # rate sanity: (5/75)^0.6 = 0.1974; x1.5 = 0.296; xS/A_AGW > 0.296
    rate = infiltration.first.flowperExteriorWallArea.get * 1000.0
    assert_operator rate, :>, 0.29
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
