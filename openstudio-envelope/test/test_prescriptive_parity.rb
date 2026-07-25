require_relative 'test_helper'

# P3 gate (parity half): resulting PER-SURFACE construction conductances match legacy
# apply_standard_construction_properties (mechanism-agnostic — legacy rewrites default
# construction sets via BTAP; the gem hard-assigns). Skips without openstudio-standards.
class TestPrescriptiveParity < Minitest::Test
  include FixtureHelper

  def self.legacy_standard
    @legacy_standard ||= begin
      require File.expand_path('../../lib/openstudio-standards', __dir__)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy_standard
    skip 'openstudio-standards not loadable — parity gate runs from the monorepo' if std == :unavailable
    std
  end

  # The BTAP-Mass default set in this repo lacks a few subsurface constructions
  # (tubular domes/diffusers), which crashes legacy customize_default_sub_surface_
  # constructions_conductance with 'Optional not initialized'. Fill the gaps with
  # sensible stand-ins so the legacy path can run; this does not affect the
  # surface-conductance comparison.
  def complete_default_subsurface_set!(model)
    model.getDefaultConstructionSets.each do |set|
      subs = set.defaultExteriorSubSurfaceConstructions
      next if subs.empty?

      subs = subs.get
      fallback_glazing = subs.fixedWindowConstruction
      fallback_opaque = subs.doorConstruction
      next if fallback_glazing.empty?

      subs.setOperableWindowConstruction(fallback_glazing.get) if subs.operableWindowConstruction.empty?
      subs.setGlassDoorConstruction(fallback_glazing.get) if subs.glassDoorConstruction.empty?
      subs.setSkylightConstruction(fallback_glazing.get) if subs.skylightConstruction.empty?
      subs.setTubularDaylightDomeConstruction(fallback_glazing.get) if subs.tubularDaylightDomeConstruction.empty?
      subs.setTubularDaylightDiffuserConstruction(fallback_glazing.get) if subs.tubularDaylightDiffuserConstruction.empty?
      subs.setOverheadDoorConstruction(fallback_opaque.get) if !fallback_opaque.empty? && subs.overheadDoorConstruction.empty?
    end
  end

  def surface_conductances(model)
    model.getSurfaces.sort_by(&:nameString).filter_map do |s|
      next unless %w[Outdoors Ground Foundation].include?(s.outsideBoundaryCondition)
      # D-32: ground FLOORS excluded — legacy BTAP retargets them to the Table
      # 3.2.3.1 strip value over the FULL area; the gem implements the printed
      # zone-conditional rule (perimeter strip only below zone 8), an
      # intentional divergence verified against the code text via MCP.
      next if s.isGroundSurface && s.surfaceType == 'Floor'
      next if s.construction.empty? || s.construction.get.to_Construction.empty?

      [s.nameString, s.construction.get.to_Construction.get.thermalConductance.to_f.round(4)]
    end.to_h
  end

  def test_per_surface_conductance_parity
    std = legacy

    legacy_model = attach_weather!(load_fixture)
    std.model_add_constructions(legacy_model)
    complete_default_subsurface_set!(legacy_model)
    std.apply_standard_construction_properties(model: legacy_model)
    legacy_c = surface_conductances(legacy_model)

    gem_model = attach_weather!(load_fixture)
    # same starting constructions as the legacy path so base assemblies match.
    # include_films: false — this is a MECHANISM-parity gate against legacy
    # apply_standard_construction_properties (BTAP, construction-only
    # conductance); the gem's default is include_films: true (code-literal,
    # matching the OSut path the NECB2020 prototypes actually use).
    std.model_add_constructions(gem_model)
    OpenStudioEnvelope::NECB.apply_prescriptive(gem_model, vintage: '2020', include_films: false)
    gem_c = surface_conductances(gem_model)

    mismatches = legacy_c.keys.filter_map do |name|
      l = legacy_c[name]
      g = gem_c[name]
      "#{name}: legacy #{l} vs gem #{g}" if g.nil? || (l - g).abs > 1e-3
    end
    assert_empty mismatches, mismatches.join("\n")
    assert_operator legacy_c.size, :>, 8, 'meaningful surface count compared (ground floors excluded per D-32)'
  end

  def test_fdwr_area_parity
    std = legacy

    legacy_model = attach_weather!(load_fixture)
    std.model_add_constructions(legacy_model)
    std.apply_standard_window_to_wall_ratio(model: legacy_model) # -1 default = NECB max
    legacy_census = OpenStudioEnvelope::Geometry.exposed_walls(legacy_model)

    gem_model = attach_weather!(load_fixture)
    std.model_add_constructions(gem_model)
    OpenStudioEnvelope::NECB.apply_prescriptive(gem_model, vintage: '2020', apply_fdwr: true)
    gem_census = OpenStudioEnvelope::Geometry.exposed_walls(gem_model)

    assert_in_delta legacy_census[:fdwr], gem_census[:fdwr], 0.01,
                    'FDWR after mutation matches legacy apply_max_fdwr_nrcan'
  end
end
