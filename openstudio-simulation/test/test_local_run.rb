require_relative 'test_helper'

# Real end-to-end LOCAL EnergyPlus runs via the default (Local/CLI) backend.
# Skips entirely when the `openstudio` CLI is not on PATH.
class TestLocalRun < Minitest::Test
  include FixtureHelper

  Runner = OpenStudioSimulation::Runner

  SCRATCH = File.join('/tmp/claude-1000/-workspaces-openstudio-standards',
                      '14d4ffe0-7e76-41d2-9609-bba51763b608/scratchpad', 'sim_local').freeze

  def setup
    skip('openstudio CLI not on PATH') unless openstudio_cli?
    FileUtils.mkdir_p(SCRATCH)
  end

  # A model with a real, simulatable HVAC system. openstudio-simulation has NO
  # runtime dependency on openstudio-hvac — this require is a TEST-TIME
  # convenience via the sibling monorepo path, nothing more.
  def proposed_with_hvac
    begin
      require 'openstudio_hvac'
    rescue LoadError
      require File.expand_path('../../openstudio-hvac/lib/openstudio_hvac', __dir__)
    end
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    model
  end

  # Sizing needs no HVAC: attach weather, run a design-day-only pass on the bare
  # fixture (which carries thermostats), and confirm a clean SQL landed.
  def test_sizing_only_run_of_bare_fixture
    model = load_fixture
    dir = File.join(SCRATCH, 'sizing')

    result = OpenStudioSimulation.run(
      model, run_dir: dir, weather: { epw: EPW, ddy: DDY }, sizing_only: true
    )

    assert result.clean?, 'sizing run should complete cleanly'
    assert File.exist?("#{dir}/run/eplusout.sql"), 'eplusout.sql missing after sizing run'
    assert_equal "#{dir}/run", result.run_dir
    assert_nil result.energy, 'sizing_only run reports no energy'
    assert_nil result.unmet_hours, 'sizing_only run reports no unmet hours'
  end

  # A short annual (one-week) run on a model with a simple system: proves the
  # real end-to-end path AND that energy_results / unmet_occupied_hours parse.
  def test_short_annual_run_parses_results
    model = proposed_with_hvac
    dir = File.join(SCRATCH, 'annual')

    result = OpenStudioSimulation.run(
      model, run_dir: dir, weather: { epw: EPW, ddy: DDY },
      run_period: { begin_month: 1, begin_day: 1, end_month: 1, end_day: 7 }
    )

    assert result.clean?, 'annual run should complete cleanly'
    assert File.exist?("#{dir}/run/eplusout.sql"), 'eplusout.sql missing after annual run'

    energy = result.energy
    assert_instance_of Hash, energy
    %w[total_site_kwh electricity_kwh natural_gas_kwh floor_area_m2 end_uses_kwh].each do |key|
      assert energy.key?(key), "energy_results missing '#{key}'"
    end
    assert_instance_of Hash, energy['end_uses_kwh']
    %w[heating cooling fans pumps interior_lighting interior_equipment water_systems].each do |key|
      assert energy['end_uses_kwh'].key?(key), "end_uses_kwh missing '#{key}'"
    end
    assert energy['floor_area_m2'].positive?, 'floor area should be positive'
    assert (energy['total_site_kwh']).positive?, 'a gas-heated week should consume site energy'

    unmet = result.unmet_hours
    assert_instance_of Hash, unmet
    assert unmet.key?('heating')
    assert unmet.key?('cooling')
  end
end
