require_relative 'test_helper'
require 'tmpdir'

# P3 E2E gate: a model with the full prescriptive envelope applied (U-values +
# FDWR windows + SRR skylights) must run in EnergyPlus with no Fatal/Severe.
class TestE2ERun < Minitest::Test
  include FixtureHelper

  def setup
    skip 'openstudio CLI not available' unless openstudio_cli?
    @dir = Dir.mktmpdir('osenv-e2e-')
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_prescriptive_envelope_sizes_cleanly
    model = attach_weather!(load_fixture)
    audit = OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020',
                                                        apply_fdwr: true, apply_srr: true)
    refute_empty audit.entries

    # ideal-air so the run exercises envelope only
    model.getThermalZones.each { |z| z.setUseIdealAirLoads(true) }
    run_dir = run_energyplus!(model, "#{@dir}/prescriptive")
    assert_clean_energyplus_run(run_dir, 'prescriptive envelope (U + FDWR + SRR)')
  end
end
