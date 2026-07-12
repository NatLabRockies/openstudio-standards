require_relative 'test_helper'

# Coverage-loop gate (hvac slices): 8.4.4.12 reference economizers, 8.4.4.17
# fan power curves, and the Part 5 prescriptive checker.
class TestEconomizerFancurveChecker < Minitest::Test
  include FixtureHelper

  def zone_types(model)
    model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }
  end

  def reference_for(system_zone_type, storeys: 1)
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    audit = OpenStudioHVAC::AuditLog.new
    result = OpenStudioHVAC::NECB.reference_hvac(
      model, vintage: '2020',
      building: { storeys: storeys, zone_types: model.getThermalZones.to_h { |z| [z.nameString, system_zone_type] },
                  winter_design_temp_c: -20 }, audit: audit)
    [result, audit]
  end

  def test_reference_air_systems_get_economizers
    result, audit = reference_for('Office - enclosed') # sys3/PSZ with DX cooling
    economized = result.model.getAirLoopHVACs.select do |loop|
      oa = loop.airLoopHVACOutdoorAirSystem
      oa.is_initialized && oa.get.getControllerOutdoorAir.getEconomizerControlType == 'DifferentialEnthalpy'
    end
    refute_empty economized, '8.4.4.12: mechanically-cooled reference air systems get DifferentialEnthalpy economizers'
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.12') })
  end

  def test_fan_power_curve_applied_after_sizing
    skip 'openstudio CLI not available' unless openstudio_cli?
    require 'tmpdir'
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'Baseboard gas boiler', zones)
    result, = reference_for('Office - open plan', storeys: 5) # drive toward sys6/VAV if selected
    reference = result.model
    vav_fans = reference.getFanVariableVolumes
    skip 'no VAV fans in this reference selection' if vav_fans.empty?

    dir = Dir.mktmpdir('oshvac-fc-')
    attach_weather!(reference)
    run_energyplus!(reference, "#{dir}/sizing", sizing_only: true)
    audit = OpenStudioHVAC::AuditLog.new
    OpenStudioHVAC::NECB.apply_efficiencies(reference, vintage: '2020', audit: audit)

    fan = reference.getFanVariableVolumes.first
    assert_in_delta 0.227143, fan.fanPowerCoefficient1.to_f, 1e-5, 'Table 8.4.4.17 row applied (small fan -> airfoil riding)'
    assert_in_delta 0.47, fan.fanPowerMinimumFlowFraction, 1e-6, 'below-D floor via minimum-flow clamp'
    assert(audit.entries.any? { |e| e[:article].to_s.include?('8.4.4.17') })
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  def test_part5_checker
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, 'PSZ RTU with exhaust Gas and DX Coils and Hot Water Baseboard', zones)
    # cripple a DX coil below the code minimum (hard-sized: the 5.2.12 lookup
    # bins by capacity, so unsized equipment cannot be checked)
    coil = model.getCoilCoolingDXSingleSpeeds.first
    coil.setRatedTotalCoolingCapacity(10_000.0)
    coil.setRatedAirFlowRate(0.5)
    coil.setRatedCOP(1.5)
    # strip economizers
    model.getAirLoopHVACs.each do |loop|
      oa = loop.airLoopHVACOutdoorAirSystem
      oa.get.getControllerOutdoorAir.setEconomizerControlType('NoEconomizer') if oa.is_initialized
    end

    audit = OpenStudioHVAC::NECB.check_part5(model, vintage: '2020',
                                             building: { winter_design_temp_c: -20 })
    warnings = audit.warnings.map { |w| w[:action] }
    assert(warnings.any? { |w| w.include?('NO economizer') }, '5.2.2.8 violation flagged')
    assert(warnings.any? { |w| w.include?('BELOW the NECB 2020 minimum') }, '5.2.12 violation flagged (COP 1.5)')
    assert(audit.entries.any? { |e| e[:step] == :check_part5 && e[:level] == :decision })
    refute_empty model.getCoilCoolingDXSingleSpeeds.select { |c| (c.ratedCOP.respond_to?(:get) ? c.ratedCOP.get : c.ratedCOP).round(2) == 1.5 },
                 'checker NEVER modifies the model'
  end
end
