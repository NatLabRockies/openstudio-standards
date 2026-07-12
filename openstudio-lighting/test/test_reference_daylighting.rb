require_relative 'test_helper'
require 'tmpdir'

# 8.4.4.5.(5)-(12): reference photocontrol evaluation — reflectances, set-point
# inheritance, placement, and the E+ comparative gate (photocontrols REDUCE
# lighting energy in the reference).
class TestReferenceDaylighting < Minitest::Test
  include FixtureHelper

  OFFICE = ['Space Function', 'Office enclosed > 25 m2'].freeze

  def windowed_office_model
    model = load_fixture
    map = model.getSpaces.to_h { |s| [s.nameString, OFFICE] }
    OpenStudioLoads.assign_space_types(model, map, vintage: '2020')
    model.getSurfaces.select { |s| s.outsideBoundaryCondition == 'Outdoors' && s.surfaceType == 'Wall' }
         .each { |w| w.setWindowToWallRatio(0.4) }
    OpenStudioLighting.apply_lights(model, vintage: '2020')
    model
  end

  def test_reflectances_and_setpoint_inheritance
    proposed = windowed_office_model
    control = OpenStudio::Model::DaylightingControl.new(proposed)
    control.setSpace(proposed.getSpaces.sort_by(&:nameString).first)
    control.setIlluminanceSetpoint(555.0)

    reference = proposed.clone(true).to_Model
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_daylighting(reference, vintage: '2020', proposed: proposed,
                                                   placement: :all, audit: audit)

    # (10)(b) reflectances on interior-facing layers
    floor = reference.getSurfaces.find { |s| s.surfaceType == 'Floor' && s.construction.is_initialized }
    inner = floor.construction.get.to_LayeredConstruction.get.layers.last.to_OpaqueMaterial.get
    assert_in_delta 0.85, inner.visibleAbsorptance, 1e-6, 'floor reflectance 0.15'

    # (11)(a): the proposed control's set-point wins for its space
    first_space = reference.getSpaces.sort_by(&:nameString).first
    ref_control = reference.getDaylightingControls.find { |c| c.space.is_initialized && c.space.get.nameString == first_space.nameString }
    refute_nil ref_control
    assert_in_delta 555.0, ref_control.illuminanceSetpoint, 1e-6, 'proposed photocontrol set-point inherited'

    # (11)(b): other spaces fall back to the space-type illuminance
    other = reference.getDaylightingControls.find { |c| c.space.is_initialized && c.space.get.nameString != first_space.nameString }
    assert_in_delta 400.0, other.illuminanceSetpoint, 1e-6

    %w[(10)(b) (10)(d) (5)-(8) (12)].each do |sentence|
      assert(audit.entries.any? { |e| e[:article].to_s.include?(sentence) }, "sentence #{sentence} audited")
    end
  end

  def test_necb_default_placement_flows_through
    reference = windowed_office_model
    audit = OpenStudioLighting::AuditLog.new
    OpenStudioLighting::NECB.reference_daylighting(reference, vintage: '2020',
                                                   placement: :necb_default,
                                                   office_match: :legacy, audit: audit)
    assert_equal 0, reference.getDaylightingControls.size,
                 'legacy threshold semantics: window-only spaces are excepted'
    assert(audit.warnings.any? { |w| w[:action].include?("'Office - enclosed'") })
  end

  def test_photocontrols_reduce_lighting_energy
    skip 'openstudio CLI not available' unless openstudio_cli?
    lighting_gj = {}
    { without: false, with: true }.each do |label, daylighting|
      model = windowed_office_model
      OpenStudioLighting::NECB.reference_daylighting(model, vintage: '2020', placement: :all) if daylighting
      model.getThermalZones.each { |z| z.setUseIdealAirLoads(true) }
      dir = Dir.mktmpdir("osdl-#{label}-")
      attach_weather!(model)
      run_dir = run_energyplus!(model, "#{dir}/run", sizing_only: false)
      assert_clean_energyplus_run(run_dir, "reference daylighting #{label}")
      sql = model.sqlFile.get
      value = sql.execAndReturnFirstDouble(
        "SELECT SUM(Value) FROM TabularDataWithStrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' " \
        "AND TableName='End Uses' AND RowName='Interior Lighting' AND Units='GJ'")
      lighting_gj[label] = value.get
      FileUtils.remove_entry(dir)
    end

    assert_operator lighting_gj[:with], :<, lighting_gj[:without],
                    "photocontrols must REDUCE lighting energy (with #{lighting_gj[:with].round(3)} GJ " \
                    "vs without #{lighting_gj[:without].round(3)} GJ) — the evaluation is LIVE in E+"
  end
end
