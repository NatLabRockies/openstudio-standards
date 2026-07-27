require_relative 'test_helper'

# P2 gate: NECB 2020 Table 8.4.4.7.-A selection rules, one test per rule, each quoting
# the code text it implements. Pure logic — synthetic facts, no OpenStudio model needed.
class TestNecbSelector < Minitest::Test
  def group(zones: ['Z1'], heated: true, cooled: true, heat_fuels: ['NaturalGas'],
            heat_pump: false, cooling_kw: 10.0, family: nil, family_guess: nil)
    { zones: zones, air_loop: 'L1', family: family, catalog_name: nil,
      family_guess: family_guess, heated: heated, cooled: cooled,
      heating_energy_types: heat_fuels, cooling_energy_types: cooled ? ['Electricity'] : [],
      heat_pump: heat_pump, terminal_type: :none, design_cooling_kw: cooling_kw, evidence: [] }
  end

  def facts_for(*groups)
    { built_by_gem: false, zone_groups: groups, plants: [],
      purchased_energy: { heating: false, cooling: false } }
  end

  def select(groups, zone_types:, storeys: 1, audit: nil, **building_extra)
    OpenStudioHVAC::NECB.select_reference_systems(
      facts: facts_for(*groups),
      building: { storeys: storeys, zone_types: zone_types, **building_extra },
      vintage: '2020', audit: audit
    )
  end

  # "General Area: office, banking, healthcare clinic, library, retail/mall ...
  #  Maximum 2 storeys -> System 3; More than 2 storeys -> System 6" (Table 8.4.4.7.-A)
  def test_general_area_storey_split
    low = select([group], zone_types: { 'Z1' => 'Office - enclosed' }, storeys: 2).first
    assert_equal 3, low.reference_system
    high = select([group], zone_types: { 'Z1' => 'Office - enclosed' }, storeys: 3).first
    assert_equal 6, high.reference_system
    assert_match(/8\.4\.4\.7/, high.articles.join)
  end

  # "Assembly Area ... Maximum 4 storeys -> System 3; More than 4 storeys -> System 6"
  def test_assembly_area_storey_split
    assert_equal 3, select([group], zone_types: { 'Z1' => 'Classroom/lecture/training' }, storeys: 4).first.reference_system
    assert_equal 6, select([group], zone_types: { 'Z1' => 'Classroom/lecture/training' }, storeys: 5).first.reference_system
  end

  # "Data Processing Area ... Where the proposed building or space has a cooling capacity
  #  exceeding 20 kW, the reference building or space shall use System 2; otherwise ...
  #  System 1." (Table 8.4.4.7.-A)
  def test_data_centre_cooling_threshold
    big = select([group(cooling_kw: 25.0)], zone_types: { 'Z1' => 'Data centre' }).first
    assert_equal 2, big.reference_system
    small = select([group(cooling_kw: 15.0)], zone_types: { 'Z1' => 'Data centre' }).first
    assert_equal 1, small.reference_system
    # exactly 20 kW does NOT exceed 20 kW
    at = select([group(cooling_kw: 20.0)], zone_types: { 'Z1' => 'Data centre' }).first
    assert_equal 1, at.reference_system
  end

  def test_data_centre_unsized_warns_and_takes_smaller_branch
    audit = OpenStudioHVAC::NECB::AuditLog.new
    a = select([group(cooling_kw: nil)], zone_types: { 'Z1' => 'Data centre' }, audit: audit).first
    assert_equal 1, a.reference_system
    assert audit.warnings.any? { |w| w[:action].include?('needs a sized model') }
  end

  # "Automotive Area: repair garage or storage garage ... All sizes -> System 4"
  def test_automotive_area
    assert_equal 4, select([group], zone_types: { 'Z1' => 'Storage garage' }).first.reference_system
  end

  # "Warehouse Area ... All sizes of non-refrigerated space -> System 4;
  #  All sizes of refrigerated space -> System 5"
  def test_warehouse_refrigerated_split
    dry = select([group], zone_types: { 'Z1' => 'Warehouse - med/blk' }).first
    assert_equal 4, dry.reference_system
    cold = select([group], zone_types: { 'Z1' => 'Warehouse - med/blk' },
                  refrigerated_zones: ['Z1']).first
    assert_equal 5, cold.reference_system
  end

  # "Supermarket/Food Service Area ... food preparation without kitchen hood -> System 3;
  #  food preparation with kitchen hood or vented appliance -> System 4"
  def test_food_service_kitchen_hood_split
    no_hood = select([group], zone_types: { 'Z1' => 'Food preparation' }).first
    assert_equal 3, no_hood.reference_system
    hooded = select([group], zone_types: { 'Z1' => 'Food preparation' },
                    kitchen_hood_zones: ['Z1']).first
    assert_equal 4, hooded.reference_system
  end

  # "Residential/Accommodation Area ... Where the proposed building or space is heated
  #  only, the reference building or space shall use System 1."
  def test_residential_heated_only
    a = select([group(heated: true, cooled: false, cooling_kw: 0.0)],
               zone_types: { 'Z1' => 'Dwelling units general' }).first
    assert_equal 1, a.reference_system
    assert_equal :build, a.action
  end

  # "Where ... heated as well as being cooled with an air-cooled unitary, packaged
  #  terminal or room air conditioner (or heat pumps), or fan coils, the reference ...
  #  shall be modeled as being identical to that of the proposed building or space"
  def test_residential_compatible_cooling_copies_proposed
    a = select([group(family: 'zone_terminal')],
               zone_types: { 'Z1' => 'Hotel/Motel - rooms' }).first
    assert_equal :copy_proposed, a.action
    assert_nil a.catalog_name
  end

  # D-34 (A1 ruled follow-legacy): a residential group WITH a heat pump takes
  # the 8.4.4.7.(4) ASHP redirect — never the copy rule, even though its
  # cooling family would otherwise qualify as compatible.
  def test_residential_heat_pump_redirects_not_copies
    a = select([group(heat_pump: true, family: 'zone_terminal')],
               zone_types: { 'Z1' => 'Multi-unit residential' }).first
    assert_equal :build, a.action
    assert_equal 'hp', a.reference_system
  end

  # "otherwise, the reference building or space shall use through-the-wall systems."
  def test_residential_otherwise_through_the_wall
    a = select([group(family: 'vav_reheat', family_guess: :multizone_vav)],
               zone_types: { 'Z1' => 'Multi-unit residential' }).first
    assert_equal :through_the_wall, a.action
    assert_equal 1, a.reference_system
  end

  # "Where the proposed building's HVAC system includes an air-source, water-source or
  #  ground-source heat pump ..., the reference building's HVAC system for that thermal
  #  block shall be an air-source heat pump described in Table 8.4.4.13." (8.4.4.13.(2))
  def test_heat_pump_override
    a = select([group(heat_pump: true)], zone_types: { 'Z1' => 'Office - enclosed' }).first
    assert_equal 'hp', a.reference_system
    assert_match(/8\.4\.4\.13/, a.articles.join)
    assert_match(/ASHP/, a.catalog_name)
  end

  # Table 8.4.4.13: "System 2 -> See Table 8.4.4.7.-B" (HP override does not apply)
  def test_heat_pump_does_not_override_system_2
    a = select([group(heat_pump: true, cooling_kw: 30.0)],
               zone_types: { 'Z1' => 'Museum archives' }).first
    assert_equal 2, a.reference_system
  end

  # 8.4.4.9.(4): "the energy type of the reference building's heating system shall be
  #  modeled as being identical to the energy type of the proposed building's heating system"
  def test_energy_type_follows_proposed
    gas = select([group(heat_fuels: ['NaturalGas'])], zone_types: { 'Z1' => 'Office' }).first
    assert_equal 'gas', gas.energy_type
    assert_match(/Gas|Hot Water/, gas.catalog_name)
    elec = select([group(heat_fuels: ['Electricity'])], zone_types: { 'Z1' => 'Office' }).first
    assert_equal 'electric', elec.energy_type
    assert_match(/Electric/, elec.catalog_name)
  end

  # 8.4.4.6.(1): "one gas-fired modulating boiler ... shall be used to represent the
  #  purchased energy equipment"
  def test_purchased_heating_becomes_gas
    a = select([group(heat_fuels: ['Purchased'])], zone_types: { 'Z1' => 'Office' }).first
    assert_equal 'gas', a.energy_type
  end

  # 8.4.4.7.(3): "If the building or space type ... is not listed in Table 8.4.4.7.-A,
  #  the type that most closely corresponds ... shall be used" (default + warning)
  def test_unlisted_space_type_defaults_with_warning
    audit = OpenStudioHVAC::NECB::AuditLog.new
    a = select([group], zone_types: { 'Z1' => 'Zamboni staging pit' }, audit: audit).first
    assert_equal 'General Area', a.category
    assert audit.warnings.any? { |w| w[:article].to_s.include?('8.4.4.7.(3)') }
  end

  def test_unconditioned_groups_get_no_assignment
    a = select([group(heated: false, cooled: false, heat_fuels: [], cooling_kw: 0.0)],
               zone_types: { 'Z1' => 'Office' })
    assert_empty a
  end

  # provenance lint: every selection rule block that sets a system carries article
  # citations at the file level, and all catalog names in system_definitions resolve
  def test_rules_provenance_and_catalog_names_resolve
    rules = OpenStudioHVAC::NECB.rules('2020')
    assert rules['provenance']['articles'].include?('8.4.4.7')
    %w[oversizing heating_plant furnace_staging cooling_plant dx_staging fans hydronic_pumps].each do |block|
      assert rules[block]['article'], "#{block} missing article citation"
    end
    rules['system_definitions'].each do |key, defn|
      next if key == 'table'

      %w[gas electric].each do |fuel|
        name = defn.fetch(fuel).fetch('name')
        assert OpenStudioHVAC::Catalog.resolve(name), "unresolvable catalog name for system #{key}/#{fuel}"
      end
    end
  end
end
