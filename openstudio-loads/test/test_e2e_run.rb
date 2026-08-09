require_relative 'test_helper'
require 'tmpdir'

# P4 gate: the bare-geometry on-ramp produces a SIMULABLE model — strip the
# fixture's loads entirely, rebuild them from NECB data, run EnergyPlus for a
# January week on ideal air, and prove the loads are live (people/equipment
# energy) and the NECB set-points condition the zones. Plus the three-gem
# composition smoke: loads -> hvac -> envelope with ONE audit.
class TestE2ERun < Minitest::Test
  include FixtureHelper

  OFFICE = ['Space Function', 'Office enclosed > 25 m2'].freeze

  # The fixture minus every load: space types, thermostats, internal loads.
  def bare_geometry
    model = load_fixture
    model.getThermostatSetpointDualSetpoints.each(&:remove)
    model.getPeoples.each(&:remove)
    model.getPeopleDefinitions.each(&:remove)
    model.getElectricEquipments.each(&:remove)
    model.getElectricEquipmentDefinitions.each(&:remove)
    model.getLightss.each(&:remove)
    model.getLightsDefinitions.each(&:remove)
    model.getSpaceInfiltrationDesignFlowRates.each(&:remove)
    model.getDesignSpecificationOutdoorAirs.each(&:remove)
    model.getDefaultScheduleSets.each(&:remove)
    model.getSpaceTypes.each(&:remove)
    model
  end

  def office_map(model)
    model.getSpaces.to_h { |s| [s.nameString, OFFICE] }
  end

  def test_bare_geometry_to_clean_energyplus_run
    skip 'openstudio CLI not available' unless openstudio_cli?
    model = bare_geometry
    assert_empty model.getPeoples.to_a
    assert model.getThermalZones.none? { |z| z.thermostatSetpointDualSetpoint.is_initialized }

    audit = OpenStudioLoads::AuditLog.new
    OpenStudioLoads.assign_space_types(model, office_map(model), vintage: '2020', audit: audit)
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)

    assert model.getThermalZones.all? { |z| z.thermostatSetpointDualSetpoint.is_initialized },
           'space-type thermostats hooked to every zone'

    dir = Dir.mktmpdir('osloads-e2e-')
    attach_weather!(model)
    model.getThermalZones.each { |z| z.setUseIdealAirLoads(true) }
    run_dir = run_energyplus!(model, "#{dir}/loads", sizing_only: false)
    assert_clean_energyplus_run(run_dir, 'NECB loads on bare geometry')

    sql = model.sqlFile.get
    equip_kwh = sql.execAndReturnFirstDouble(
      "SELECT SUM(Value) FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' " \
      "AND TableName='End Uses' AND RowName='Interior Equipment' AND Units='GJ'")
    assert equip_kwh.is_initialized
    assert_operator equip_kwh.get, :>, 0, 'plug loads are alive'

    heating = sql.execAndReturnFirstDouble(
      "SELECT SUM(Value) FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' " \
      "AND TableName='End Uses' AND RowName='Heating' AND Units='GJ'")
    assert_operator heating.get, :>, 0, 'NECB heating set-points drive conditioning in a Toronto January week'
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_three_gem_composition_one_audit
    hvac_lib = File.expand_path('../../openstudio-hvac/lib/openstudio_hvac', __dir__)
    envelope_lib = File.expand_path('../../openstudio-envelope/lib/openstudio_envelope', __dir__)
    skip 'sibling gems not present' unless File.exist?("#{hvac_lib}.rb") && File.exist?("#{envelope_lib}.rb")
    require hvac_lib
    require envelope_lib

    model = bare_geometry
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioLoads.assign_space_types(model, office_map(model), vintage: '2020', audit: audit)
    OpenStudioLoads::NECB.apply_loads(model, vintage: '2020', audit: audit)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', model.getThermalZones.sort_by(&:nameString))
    OpenStudioEnvelope::NECB.apply_prescriptive(model, vintage: '2020', hdd: 3890, audit: audit)

    steps = audit.entries.map { |e| e[:step] }.uniq
    %i[loads schedules coverage prescriptive].each { |s| assert_includes steps, s }
    refute_empty model.getPlantLoops.to_a, 'HVAC built on the loaded model'
    refute_empty model.getPeoples.to_a, 'loads present'
    wall = model.getSurfaces.find { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
    # D-23: table 0.265 is OVERALL U (incl. films) — constructions are named by
    # the construction-only conductance 1/(1/0.265 - R_films) = 0.2759.
    assert_match(/:U-0\.2759/, wall.construction.get.nameString,
                 'prescriptive CONSTRUCTION-ONLY target for the 0.265 overall table value (HDD 3890 wall target)')
    entries = JSON.parse(audit.to_json)
    assert_operator entries.size, :>, 20, 'ONE audit spans loads + envelope decisions'
    assert(audit.entries.any? { |e| e[:step] == :loads } && audit.entries.any? { |e| e[:step] == :prescriptive })
  end
end
