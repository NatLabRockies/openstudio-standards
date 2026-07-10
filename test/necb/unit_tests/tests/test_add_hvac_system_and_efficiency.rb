require_relative '../../../helpers/minitest_helper'

# Tests for OpenstudioStandards::HVAC.add_hvac_system_and_efficiency and its sibling builders,
# which add any supported HVAC system (CBECS/generic, NECB reference sys1-6, NECB ECM) by
# descriptive name to a set of zones WITHOUT requiring NECB-tagged (standardsSpaceType) geometry.
class Test_Add_HVAC_System_And_Efficiency < Minitest::Test
  # Full facade runs include a sizing run (slow). Toggle off to skip only the sizing-based test.
  PERFORM_STANDARDS = true

  def load_untagged_model
    # 5ZoneNoHVAC has thermostats but NO standardsSpaceType tags — the premise of these tests.
    model = BTAP::FileIO.load_osm(File.join(__dir__, '../../models/5ZoneNoHVAC.osm'))
    epw = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw)
    model
  end

  def sizing_dir(name)
    dir = File.join(__dir__, "output/#{self.class.name}/#{name}")
    FileUtils.mkdir_p(dir)
    dir
  end

  # Confirm the fixture really is untagged, so the tests prove "no space types needed".
  def test_fixture_is_untagged_with_thermostats
    model = load_untagged_model
    tagged = model.getSpaceTypes.count { |st| st.standardsSpaceType.is_initialized }
    thermo = model.getThermalZones.count { |z| z.thermostatSetpointDualSetpoint.is_initialized }
    assert_equal(0, tagged, 'expected the fixture to have no standardsSpaceType tags')
    assert_equal(model.getThermalZones.size, thermo, 'expected all zones to have a thermostat')
  end

  # --- Topology (fast, no sizing run) ---

  def test_necb_reference_electric_sys3_builds_on_untagged_zones
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    zones = model.getThermalZones.to_a
    OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
      model, standard, 'PSZ RTU Electric and DX Coils and Electric Baseboard', zones
    )
    assert_equal(1, model.getAirLoopHVACs.size, 'sys3 should build one shared PSZ air loop')
    assert_equal(1, model.getCoilCoolingDXSingleSpeeds.size)
    assert_equal(zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size, 'each zone gets an electric baseboard')
    assert_empty(model.getBoilerHotWaters, 'all-electric sys3 needs no boiler')
    # control zone defaults to zones.first
    airloop = model.getAirLoopHVACs.first
    assert_includes(airloop.thermalZones.map(&:nameString), zones.first.nameString)
  end

  def test_necb_reference_hydronic_sys2_builds_hw_loop
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
      model, standard, 'FPFC MAU DX Coils with Scroll Chiller', model.getThermalZones.to_a
    )
    refute_empty(model.getBoilerHotWaters, 'hydronic FPFC (needs_boiler) should build a hot-water loop')
    refute_empty(model.getChillerElectricEIRs, 'FPFC with chiller should build a chiller')
  end

  def test_necb_reference_sys4_builds_via_control_zone
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    zones = model.getThermalZones.to_a
    # sys4 always elects a control zone; the caller-supplied one avoids the sizing/stored-loads path.
    OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
      model, standard, 'PSZ RTU with exhaust Gas and DX Coils and Electric Baseboard', zones,
      control_zone: zones[1]
    )
    assert_equal(1, model.getAirLoopHVACs.size)
    assert_includes(model.getAirLoopHVACs.first.thermalZones.map(&:nameString), zones[1].nameString)
  end

  def test_necb_ecm_hs08_builds_on_untagged_zones
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    OpenstudioStandards::HVAC.add_necb_ecm_hvac_system(
      model, standard, 'hs08_ccashp_vrf', model.getThermalZones.to_a
    )
    refute_empty(model.getAirConditionerVariableRefrigerantFlows, 'hs08 builds a VRF outdoor unit')
    refute_empty(model.getZoneHVACTerminalUnitVariableRefrigerantFlows, 'hs08 builds VRF terminals')
  end

  # --- remove_existing (zone-scoped teardown, replace instead of stack) ---

  def test_remove_existing_replaces_hvac_on_zones
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    zones = model.getThermalZones.to_a

    # Build a hydronic system first (MAU air loop + fan coils + boiler + chiller).
    OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
      model, standard, 'FPFC MAU DX Coils with Scroll Chiller', zones
    )
    refute_empty(model.getBoilerHotWaters)
    refute_empty(model.getChillerElectricEIRs)

    # Replace with all-electric sys3 on the same zones.
    OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
      model, standard, 'PSZ RTU Electric and DX Coils and Electric Baseboard', zones,
      remove_existing: true
    )

    # The orphaned hydronic plant loops should be torn down, leaving only the new electric sys3.
    assert_empty(model.getChillerElectricEIRs, 'chiller loop should be torn down')
    assert_empty(model.getBoilerHotWaters, 'boiler loop should be torn down')
    assert_equal(1, model.getAirLoopHVACs.size, 'only the new sys3 air loop should remain')
    assert_equal(zones.size, model.getZoneHVACBaseboardConvectiveElectrics.size)
    assert_equal(1, model.getCoilCoolingDXSingleSpeeds.size)
  end

  # --- Error handling ---

  def test_missing_thermostats_raises
    model = load_untagged_model
    model.getThermostatSetpointDualSetpoints.each(&:remove)
    standard = Standard.build('NECB2011')
    err = assert_raises(RuntimeError) do
      OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
        model, standard, 'PSZ RTU Electric and DX Coils and Electric Baseboard', model.getThermalZones.to_a
      )
    end
    assert_match(/thermostat/i, err.message)
  end

  def test_unknown_necb_name_raises
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    assert_raises(RuntimeError) do
      OpenstudioStandards::HVAC.add_necb_reference_hvac_system(
        model, standard, 'Not A Real System Name', model.getThermalZones.to_a
      )
    end
  end

  def test_control_zone_must_be_in_zones
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    zones = model.getThermalZones.to_a
    outsider = OpenStudio::Model::ThermalZone.new(model)
    err = assert_raises(RuntimeError) do
      standard.determine_control_zone(zones, control_zone: outsider)
    end
    assert_match(/control_zone/, err.message)
  end

  # --- classify_system ---

  def test_classify_system
    standard = Standard.build('NECB2011')
    assert_equal(:ecm, OpenstudioStandards::HVAC.classify_system(standard, 'hs08_ccashp_vrf'))
    assert_equal(:necb_ref, OpenstudioStandards::HVAC.classify_system(standard, 'PSZ RTU Gas and DX Coils and Hot Water Baseboard'))
    assert_equal(:cbecs, OpenstudioStandards::HVAC.classify_system(standard, 'Baseboard gas boiler'))
  end

  # --- determine_control_zone backward-compatibility (no control_zone => existing behaviour) ---

  def test_determine_control_zone_backward_compatible
    # With a supplied control_zone it must short-circuit to that zone (no stored-load read).
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    zones = model.getThermalZones.to_a
    assert_same(zones[2], standard.determine_control_zone(zones, control_zone: zones[2]))
  end

  # --- Full facade end-to-end incl. efficiency (slow: runs a sizing run) ---

  def test_facade_applies_necb_efficiency_end_to_end
    skip('PERFORM_STANDARDS is false') unless PERFORM_STANDARDS
    model = load_untagged_model
    standard = Standard.build('NECB2011')
    ok = OpenstudioStandards::HVAC.add_hvac_system_and_efficiency(
      model, standard,
      system: 'PSZ RTU Electric and DX Coils and Electric Baseboard',
      zones: model.getThermalZones.to_a,
      sizing_run_dir: sizing_dir('e2e_sys3')
    )
    assert(ok, 'facade should return true')
    coils = model.getCoilCoolingDXSingleSpeeds
    refute_empty(coils)
    coils.each do |coil|
      cop = coil.ratedCOP.respond_to?(:is_initialized) ? coil.ratedCOP.get : coil.ratedCOP
      assert(cop > 3.0, "expected a NECB COP (> OpenStudio default 3.0), got #{cop}")
      assert_equal('DXCOOL-NECB2011-REF-CAPFT', coil.totalCoolingCapacityFunctionOfTemperatureCurve.name.to_s,
                   'expected the NECB reference cap-f-T curve')
    end
  end
end
