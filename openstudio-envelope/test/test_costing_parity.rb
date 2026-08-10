require_relative 'test_helper'

# Costing parity vs legacy BTAP: (1) the interpolator, (2) cost_construction dollar
# math across EVERY constructions.json candidate, (3) per-surface RSI convention vs
# TBD.rsi. Runs under the repo bundle (openstudio-standards + tbd); skips standalone.
class TestCostingParity < Minitest::Test
  include FixtureHelper

  CITY = 'TORONTO'.freeze
  PROVINCE = 'ONTARIO'.freeze

  def self.legacy
    @legacy ||= begin
      require 'openstudio-standards' # the PINNED oracle (legacy_pin/Gemfile)
      # BTAP sub-files are required BY PATH inside the oracle — resolve the
      # oracle's own root (the pinned checkout), never this repo's lib/.
      legacy_root = Gem.loaded_specs['openstudio-standards'].full_gem_path
      legacy_dir = File.join(legacy_root, 'lib/openstudio-standards/btap')
      # PR #2120 renamed these: btap/common_paths -> btap/paths,
      # btap/costing/btap_database -> btap/costing/database, and the classes
      # BTAPCosting/BTAPDatabase are now BTAP::Costing / BTAP::Database.
      require File.join(legacy_dir, 'paths')
      require File.join(legacy_dir, 'costing/database')
      require File.join(legacy_dir, 'costing/btap_costing')
      require File.join(legacy_dir, 'costing/envelope_costing')
      require File.join(legacy_dir, 'linear_regression')
      coster = BTAP::Costing.allocate
      coster.instance_variable_set(:@costing_database, BTAP::Database.instance)
      coster
    rescue LoadError, StandardError => e
      warn "legacy costing parity skipped: #{e.class}: #{e.message[0, 100]}"
      :unavailable
    end
  end

  def legacy
    coster = self.class.legacy
    if coster == :unavailable
      msg = 'legacy oracle not bundled — run under BUNDLE_GEMFILE=legacy_pin/Gemfile'
      ENV['LEGACY_PIN_REQUIRED'] == '1' ? flunk(msg) : skip(msg)
    end
    coster
  end

  def test_interpolate_parity
    legacy
    points_sets = [
      [[1.0, 10.0], [2.0, 20.0], [4.0, 30.0]],
      [[0.5, 100.0], [0.9, 90.0], [1.7, 260.0], [3.2, 410.0]],
      [[2.0, 55.5]]
    ]
    xs = [0.4, 0.5, 0.55, 0.99, 1.0, 1.5, 2.0, 3.05, 3.99, 4.0, 4.05, 4.2, 9.0]
    mismatches = []
    points_sets.each do |points|
      xs.each do |x|
        legacy_value, = BTAP::LinearRegression.interpolate(x_y_array: points.map(&:dup), x2: x)
        gem_value = OpenStudioEnvelope::Costing::Interpolate.interpolate(x_y_array: points.map(&:dup), x2: x).value
        mismatches << [points.first, x, legacy_value, gem_value] unless (legacy_value.to_f - gem_value).abs < 1e-9
      end
    end
    BTAP::LinearRegression.extrapolation_boundaries_exceeded? # reset legacy sticky flag
    assert_empty mismatches, "interpolate mismatches: #{mismatches.inspect[0, 400]}"
  end

  def test_cost_construction_parity_every_candidate
    coster = legacy
    database = OpenStudioEnvelope::Costing::Database.new
    checked = 0
    mismatches = []

    database.constructions.each do |sheet, assemblies|
      assemblies.each_key do |assembly|
        database.construction_candidates(sheet, assembly).each do |rsi, construction|
          legacy_hash = { 'type' => construction['type'], 'id_layers' => construction['id_layers'].dup }
          coster.cost_construction(legacy_hash, PROVINCE, CITY)
          gem_cost = OpenStudioEnvelope::Costing::EnvelopeCosts.construction_cost(
            database, construction, PROVINCE, CITY)
          checked += 1
          next if (legacy_hash['cost'] - gem_cost).abs < 0.011 # per-layer cent rounding

          mismatches << [sheet, assembly, rsi.round(3), legacy_hash['cost'], gem_cost]
        end
      end
    end

    assert_operator checked, :>=, 90, 'every candidate in every assembly catalog compared (92 in the vendored catalogs)'
    assert_empty mismatches, "$ mismatches (sheet, assembly, rsi, legacy, gem): #{mismatches.inspect[0, 600]}"
  end

  def test_rsi_parity_vs_tbd
    legacy
    require 'tbd'
    model = load_fixture
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890,
                                                audit: OpenStudioEnvelope::AuditLog.new)
    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    wall.setWindowToWallRatio(0.3)
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890,
                                                audit: OpenStudioEnvelope::AuditLog.new)

    mismatches = []
    model.getSurfaces.sort_by(&:nameString).each do |surface|
      next if surface.construction.empty? || surface.construction.get.to_LayeredConstruction.empty?
      next unless surface.outsideBoundaryCondition == 'Outdoors' ||
                  OpenStudioEnvelope::Costing::Quantify::GROUND_BOUNDARIES.include?(surface.outsideBoundaryCondition)

      lc = surface.construction.get.to_LayeredConstruction.get
      legacy_rsi = TBD.rsi(lc, surface.filmResistance)
      gem_rsi = OpenStudioEnvelope::Costing::Quantify.rsi_of(surface, film: true)
      mismatches << [surface.nameString, legacy_rsi, gem_rsi] unless (legacy_rsi - gem_rsi).abs < 1e-6
    end
    model.getSubSurfaces.sort_by(&:nameString).each do |sub|
      next if sub.construction.empty? || sub.construction.get.to_LayeredConstruction.empty?

      lc = sub.construction.get.to_LayeredConstruction.get
      legacy_rsi = TBD.rsi(lc, 0)
      gem_rsi = OpenStudioEnvelope::Costing::Quantify.rsi_of(sub, film: false)
      mismatches << [sub.nameString, legacy_rsi, gem_rsi] unless (legacy_rsi - gem_rsi).abs < 1e-6
    end
    assert_empty mismatches, "RSI mismatches vs TBD.rsi: #{mismatches.inspect[0, 400]}"
  end

  def test_tb_material_quantities_parity
    legacy
    tallies = { 'parapet' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 100.0 },
                'jamb' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 50.0 },
                'sill' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 25.0 },
                'rimjoist' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 30.0 },
                'transition' => { 'BTAP-ExteriorWall-SteelFramed-1 good' => 500.0 } }
    legacy_quantities = BTAP::BridgingData.get_material_quantities_for_edges(tallies)
    database = OpenStudioEnvelope::Costing::Database.new
    gem_quantities, = OpenStudioEnvelope::Costing::ThermalBridgingCosts.material_quantities(
      tallies, database, nil)
    legacy_quantities.each do |id, qty|
      assert_in_delta qty, gem_quantities[id.to_s], 1e-9, "material #{id} quantity"
    end
    assert_equal legacy_quantities.keys.sort, gem_quantities.keys.sort
  rescue NameError
    # BridgingData needs the tbd-dependent bridging.rb; load it explicitly
    require File.join(Gem.loaded_specs['openstudio-standards'].full_gem_path, 'lib/openstudio-standards/btap/bridging')
    retry
  end
end
