require_relative 'test_helper'

# P2 gate (parity half): gem lookups byte-match legacy openstudio-standards NECB2020.
# Skips when the host repo isn't loadable (the gem suite must stand alone).
class TestLookupParity < Minitest::Test
  HDD_SWEEP = [0, 1500, 2999, 3000, 3999, 4000, 4001, 5500, 6999, 7000, 8000, 9998, 9999, 12_000].freeze

  def self.legacy_standard
    @legacy_standard ||= begin
      require 'openstudio-standards' # the PINNED oracle (legacy_pin/Gemfile)
      Standard.build('NECB2020')
    rescue LoadError, StandardError => e
      warn "legacy parity skipped: #{e.class}: #{e.message[0, 80]}"
      :unavailable
    end
  end

  def legacy
    std = self.class.legacy_standard
    if std == :unavailable
      msg = 'legacy oracle not bundled — run under BUNDLE_GEMFILE=legacy_pin/Gemfile'
      ENV['LEGACY_PIN_REQUIRED'] == '1' ? flunk(msg) : skip(msg)
    end
    std
  end

  def test_max_u_parity_full_sweep
    mismatches = []
    { 'outdoors' => %w[wall roofceiling floor window skylight door],
      'ground' => %w[wall roofceiling floor] }.each do |boundary, surfaces|
      surfaces.each do |surface|
        HDD_SWEEP.each do |hdd|
          gem_u = OpenStudioEnvelope::NECB.max_u(vintage: '2020', surface: surface, boundary: boundary, hdd: hdd)
          legacy_u = legacy.max_u_necb(surface, boundary, hdd)
          next if (gem_u - legacy_u).abs < 1e-9

          mismatches << "#{boundary}/#{surface}@#{hdd}: gem #{gem_u} vs legacy #{legacy_u}"
        end
      end
    end
    assert_empty mismatches, mismatches.join("\n")
  end

  def test_max_fdwr_parity_sweep
    HDD_SWEEP.each do |hdd|
      gem_v = OpenStudioEnvelope::NECB.max_fdwr(vintage: '2020', hdd: hdd)
      legacy_v = legacy.max_fwdr(hdd)
      assert_in_delta legacy_v, gem_v, 1e-9, "fdwr mismatch at hdd=#{hdd}"
    end
  end

  def test_srr_parity
    legacy_srr = legacy.get_standards_constant('skylight_to_roof_ratio_max_value')
    assert_in_delta legacy_srr, OpenStudioEnvelope::NECB.max_srr(vintage: '2020'), 1e-9
  end

  def test_hdd_parity_toronto
    model = OpenStudio::Model::Model.load(OpenStudio::Path.new(FixtureHelper::FIXTURE)).get
    epw = OpenStudio::EpwFile.new(OpenStudio::Path.new(FixtureHelper::EPW))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw)

    legacy_hdd = legacy.get_necb_hdd18(model: model, necb_hdd: true)
    gem_hdd = OpenStudioEnvelope::Climate.hdd18(model)
    assert_equal legacy_hdd, gem_hdd, 'nearest-Table-C-1-city HDD must match legacy'
  end
end
