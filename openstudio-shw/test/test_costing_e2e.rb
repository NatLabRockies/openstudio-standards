require_relative 'test_helper'
require 'tmpdir'

# P4 gate: SHW costing on the hvac engine, SHW energy alive in EnergyPlus,
# and the family composition with ONE audit.
class TestCostingE2E < Minitest::Test
  include FixtureHelper

  CITY = 'TORONTO'.freeze
  PROVINCE = 'ONTARIO'.freeze

  def shw_model(fuel: 'NaturalGas')
    model = tagged_model
    OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: fuel)
    model
  end

  def test_costing_gas_tank
    audit = OpenStudioSHW::AuditLog.new
    report = OpenStudioSHW.cost(shw_model, city: CITY, province_state: PROVINCE, audit: audit)
    assert_operator report.total, :>, 0
    assert_operator report.shw[:tanks], :>=, 1
    # small-volume tanks route to the Et=0.9 'all others' row -> efficiency >= 0.85
    # -> HE classification (PVC flue + power vent), matching legacy semantics
    assert_operator report.shw[:reg_gas] + report.shw[:he_gas], :>=, 1
    assert_equal 1, report.shw[:pumps]
    decisions = audit.entries.select { |e| e[:step] == :costing_equipment }.map { |e| e[:action] }
    %w[flue fuel\ line utility\ conduit tank-to-pump].each do |token|
      assert(decisions.any? { |d| d.include?(token) }, "#{token} costed")
    end
    assert(decisions.any? { |d| d.include?('power vent') }, 'HE tank gets a power vent') if report.shw[:he_gas].positive?
  end

  def test_costing_electric_tank_no_flue
    audit = OpenStudioSHW::AuditLog.new
    report = OpenStudioSHW.cost(shw_model(fuel: 'Electricity'), city: CITY, province_state: PROVINCE, audit: audit)
    assert_operator report.total, :>, 0
    assert_operator report.shw[:elec], :>=, 1
    decisions = audit.entries.select { |e| e[:step] == :costing_equipment }.map { |e| e[:action] }
    refute(decisions.any? { |d| d.include?('flue') }, 'no flue for electric tanks')
    refute(decisions.any? { |d| d.include?('fuel line') }, 'no fuel line for electric tanks')
  end

  def test_no_shw_costs_nothing
    report = OpenStudioSHW.cost(load_fixture, city: CITY, province_state: PROVINCE)
    assert_equal 0.0, report.total
  end

  def test_shw_energy_alive_in_energyplus
    skip 'openstudio CLI not available' unless openstudio_cli?
    model = shw_model
    model.getThermalZones.each { |z| z.setUseIdealAirLoads(true) }
    dir = Dir.mktmpdir('osshw-e2e-')
    attach_weather!(model)
    run_dir = run_energyplus!(model, "#{dir}/shw", sizing_only: false)
    assert_clean_energyplus_run(run_dir, 'NECB SHW')

    sql = model.sqlFile.get
    water_gj = sql.execAndReturnFirstDouble(
      "SELECT SUM(Value) FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' " \
      "AND TableName='End Uses' AND RowName='Water Systems' AND Units='GJ'")
    assert water_gj.is_initialized
    assert_operator water_gj.get, :>, 0, 'water systems consume energy on the NECB SWH schedule'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_family_composition_one_audit
    envelope_lib = File.expand_path('../../openstudio-envelope/lib/openstudio_envelope', __dir__)
    skip 'envelope gem not present' unless File.exist?("#{envelope_lib}.rb")
    require envelope_lib

    model = tagged_model
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)
    OpenStudioSHW.apply_shw(model, vintage: '2020', fuel: 'NaturalGas', audit: audit)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', model.getThermalZones.sort_by(&:nameString))
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890, audit: audit)
    OpenStudioSHW.cost(model, city: CITY, province_state: PROVINCE, audit: audit)

    steps = audit.entries.map { |e| e[:step] }.uniq
    %i[loads shw shw_efficiency prescriptive costing_shw].each { |s| assert_includes steps, s }
    assert_equal 2, model.getPlantLoops.size, 'SHW loop + heating loop coexist'
    assert(audit.entries.any? { |e| e[:article].to_s.include?('6.2.2.1') })
  end
end
