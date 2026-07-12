require_relative 'test_helper'

# P1 gate: OpenStudioHVAC.characterize round-trips every catalog family (build ->
# characterize recovers family/energy facts) and classifies foreign OSMs structurally.
class TestClassify < Minitest::Test
  include FixtureHelper

  # family -> [catalog name, expectations]
  ROUND_TRIP = {
    'baseboards' => ['Baseboard gas boiler',
                     { heated: true, cooled: false, heat_fuel: 'NaturalGas', air_loop: false }],
    'psz' => ['PSZ RTU Gas and DX Coils and Electric Baseboard',
              { heated: true, cooled: true, heat_fuel: 'NaturalGas', cool_fuel: 'Electricity', air_loop: true }],
    'vav_reheat' => ['MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard',
                     { heated: true, cooled: true, heat_fuel: 'NaturalGas', terminal: :vav_reheat, air_loop: true }],
    'fan_coils' => ['FPFC MAU DX Coils with Scroll Chiller',
                    { heated: true, cooled: true, air_loop: true }],
    'mau_ptac' => ['PSZ MAU Electric and DX Coils and Electric Baseboard with PTAC',
                   { heated: true, cooled: true, air_loop: true }],
    'zone_terminal' => ['PTHP', { heated: true, cooled: true, heat_pump: true, air_loop: false }],
    'unit_heaters' => ['Gas unit heaters', { heated: true, cooled: false, heat_fuel: 'NaturalGas', air_loop: false }],
    'furnace' => ['Forced air furnace', { heated: true, air_loop: true }],
    'evap_cooler' => ['Direct evap coolers with no heat', { cooled: true, air_loop: true }],
    'wshp' => ['Water source heat pumps', { heated: true, cooled: true, heat_pump: true, air_loop: false }],
    'doas' => ['DOAS ventilation only', { air_loop: true }],
    'vrf' => ['VRF', { heated: true, cooled: true, heat_pump: true, air_loop: false }],
    'doas_pthp' => ['hs11_ashp_pthp', { heated: true, cooled: true, heat_pump: true }],
    'ecm_ashp_baseboard' => ['hs12_ashp_baseboard', { heated: true }],
    'ecm_doas_vrf' => ['hs08_ccashp_vrf', { heated: true, cooled: true, heat_pump: true }],
    'ecm_hp_fancoils' => ['hs15_cawhp_fancoils', { heated: true, cooled: true }]
  }.freeze

  def build_and_characterize(name, audit: nil)
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, name, zones)
    [model, OpenStudioHVAC.characterize(model, audit: audit)]
  end

  def test_round_trip_all_families
    failures = []
    ROUND_TRIP.each do |family, (name, expect)|
      _, facts = build_and_characterize(name)
      groups = facts[:zone_groups]
      air_groups = groups.select { |g| g[:air_loop] }

      if expect[:air_loop]
        failures << "#{family}: no air-loop group" if air_groups.empty?
        # gem fast path must recognize the catalog name on at least one loop
        unless air_groups.any? { |g| g[:family] == family || (family == 'furnace' && g[:family]) }
          failures << "#{family}: catalog name not recognized (families: #{air_groups.map { |g| g[:family] }.uniq})"
        end
      end
      failures << "#{family}: heated not detected" if expect[:heated] && groups.none? { |g| g[:heated] }
      failures << "#{family}: cooled not detected" if expect[:cooled] && groups.none? { |g| g[:cooled] }
      failures << "#{family}: heat pump not detected" if expect[:heat_pump] && groups.none? { |g| g[:heat_pump] }
      if expect[:heat_fuel] && groups.none? { |g| g[:heating_energy_types].include?(expect[:heat_fuel]) }
        failures << "#{family}: heating fuel #{expect[:heat_fuel]} missing (#{groups.flat_map { |g| g[:heating_energy_types] }.uniq})"
      end
      if expect[:cool_fuel] && groups.none? { |g| g[:cooling_energy_types].include?(expect[:cool_fuel]) }
        failures << "#{family}: cooling fuel #{expect[:cool_fuel]} missing"
      end
      if expect[:terminal] && groups.none? { |g| g[:terminal_type] == expect[:terminal] }
        failures << "#{family}: terminal #{expect[:terminal]} missing"
      end
    rescue StandardError => e
      failures << "#{family} (#{name}): #{e.class} #{e.message}"
    end
    assert_empty failures, failures.join("\n")
  end

  def test_gem_built_flag_and_composite
    _, facts = build_and_characterize('DOAS with fan coil chiller with boiler')
    assert facts[:built_by_gem], 'composite parts stamp resolvable catalog names'
    assert facts[:zone_groups].any? { |g| g[:heated] && g[:cooled] }
  end

  def test_foreign_model_structural_classification
    model, = build_and_characterize('MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard')
    model.getAirLoopHVACs.each_with_index { |al, i| al.setName("Building HVAC #{i + 1}") }
    facts = OpenStudioHVAC.characterize(model)

    refute facts[:built_by_gem]
    group = facts[:zone_groups].find { |g| g[:air_loop] }
    assert_nil group[:catalog_name]
    assert_equal :multizone_vav, group[:family_guess]
    assert group[:heated] && group[:cooled]
    assert_includes group[:heating_energy_types], 'NaturalGas' # via boiler on the HW loop
  end

  def test_purchased_energy_detected
    _, facts = build_and_characterize('Baseboard district hot water')
    assert facts[:purchased_energy][:heating], 'district hot water = purchased heating energy'
    group = facts[:zone_groups].first
    assert_includes group[:heating_energy_types], 'Purchased'
  end

  def test_design_cooling_kw_and_audit
    audit = OpenStudioHVAC::NECB::AuditLog.new
    model, facts = build_and_characterize('PSZ RTU Electric and DX Coils and Electric Baseboard', audit: audit)

    cooled = facts[:zone_groups].select { |g| g[:cooled] }
    assert cooled.all? { |g| g[:design_cooling_kw].nil? }, 'unsized -> nil, never a partial sum'
    assert audit.warnings.any? { |w| w[:action].include?('cooling capacity unsized') }

    model.getCoilCoolingDXSingleSpeeds.each { |c| c.setRatedTotalCoolingCapacity(10_000.0) }
    facts2 = OpenStudioHVAC.characterize(model)
    cooled2 = facts2[:zone_groups].select { |g| g[:cooled] }
    assert cooled2.all? { |g| (g[:design_cooling_kw] - 10.0).abs < 0.01 }

    # audit is serializable both ways
    parsed = JSON.parse(audit.to_json)
    assert parsed.is_a?(Array) && !parsed.empty?
    assert_includes audit.to_s, 'characterize'
    assert(audit.entries.any? { |e| e[:evidence] }, 'evidence recorded for conclusions')
  end

  def test_plants_classified
    _, facts = build_and_characterize('MZ BU RTU Hot Water Heating Coil Scroll Chiller and Hot Water Baseboard')
    types = facts[:plants].map { |p| p[:type] }
    assert_includes types, :hot_water
    assert_includes types, :chilled_water
    hw = facts[:plants].find { |p| p[:type] == :hot_water }
    assert_includes hw[:fuels], 'NaturalGas'
  end
end
