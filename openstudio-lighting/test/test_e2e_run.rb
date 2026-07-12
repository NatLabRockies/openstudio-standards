require_relative 'test_helper'
require 'tmpdir'

# P5 gate: gem-built lighting is ALIVE in EnergyPlus, and the full gem family
# composes: loads -> lighting -> hvac -> envelope on ONE model with ONE audit.
class TestE2ERun < Minitest::Test
  include FixtureHelper

  OFFICE = ['Space Function', 'Office enclosed > 25 m2'].freeze

  def loaded_lit_model
    model = load_fixture
    model.getLightss.each(&:remove)
    model.getLightsDefinitions.each(&:remove)
    map = model.getSpaces.to_h { |s| [s.nameString, OFFICE] }
    OpenStudioLoads.assign_space_types(model, map, vintage: '2020')
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020')
    model
  end

  def test_lighting_energy_alive_in_energyplus
    skip 'openstudio CLI not available' unless openstudio_cli?
    model = loaded_lit_model
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting.apply_lights(model, vintage: '2020', audit: audit)

    dir = Dir.mktmpdir('oslight-e2e-')
    attach_weather!(model)
    model.getThermalZones.each { |z| z.setUseIdealAirLoads(true) }
    run_dir = run_energyplus!(model, "#{dir}/lights", sizing_only: false)
    assert_clean_energyplus_run(run_dir, 'NECB lighting')

    sql = model.sqlFile.get
    lighting_gj = sql.execAndReturnFirstDouble(
      "SELECT SUM(Value) FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' " \
      "AND TableName='End Uses' AND RowName='Interior Lighting' AND Units='GJ'")
    assert lighting_gj.is_initialized
    assert_operator lighting_gj.get, :>, 0, 'interior lighting consumes energy on the NECB schedule'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_full_family_composition_one_audit
    hvac_lib = File.expand_path('../../openstudio-hvac/lib/openstudio_hvac', __dir__)
    envelope_lib = File.expand_path('../../openstudio-envelope/lib/openstudio_envelope', __dir__)
    skip 'sibling gems not present' unless File.exist?("#{hvac_lib}.rb") && File.exist?("#{envelope_lib}.rb")
    require hvac_lib
    require envelope_lib

    model = loaded_lit_model
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioLighting.apply_lights(model, vintage: '2020', audit: audit)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', model.getThermalZones.sort_by(&:nameString))
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890, audit: audit)
    OpenStudioLighting.cost(model, vintage: '2020', city: 'TORONTO', province_state: 'ONTARIO', audit: audit)

    steps = audit.entries.map { |e| e[:step] }.uniq
    %i[lighting coverage prescriptive costing_lighting].each { |s| assert_includes steps, s }
    refute_empty model.getSpaceTypes.flat_map { |st| st.lights.to_a }, 'lights present'
    refute_empty model.getPlantLoops.to_a, 'HVAC present'
    entries = JSON.parse(audit.to_json)
    assert_operator entries.size, :>, 25, 'ONE audit spans lighting apply + envelope + lighting costing'
  end
end
