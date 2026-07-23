require_relative 'test_helper'

# P1 gate: the vendored NECB loads data is structurally sound, equals the legacy
# MERGED runtime tables, and matches MCP-verified code values.
class TestDataIntegrity < Minitest::Test
  SCHEDULE_CATEGORIES = ['Occupancy', 'Lighting', 'Electric-Equipment', 'Fan',
                         'Service Water Heating', 'Thermostat Setpoint-Heating',
                         'Thermostat Setpoint-Cooling'].freeze

  def space_types
    OpenStudioLoads::NECB.table('2020', 'space_types')
  end

  def schedules
    OpenStudioLoads::NECB.table('2020', 'schedules')
  end

  def test_counts_and_keys
    assert_equal 308, space_types.size
    assert_equal 80, space_types.first.keys.size
    assert_equal 240, schedules.size
    %w[building_type space_type occupancy_per_area electric_equipment_per_area
       ventilation_per_area ventilation_per_person occupancy_schedule
       heating_setpoint_schedule necb_schedule_type].each do |key|
      assert space_types.first.key?(key), "space-type records carry #{key}"
    end
  end

  def test_schedule_letters_have_complete_category_sets
    by_name = schedules.group_by { |r| r['name'] }
    ('A'..'I').each do |letter|
      SCHEDULE_CATEGORIES.each do |category|
        name = "NECB-#{letter}-#{category}"
        assert by_name.key?(name), "#{name} present"
      end
    end
    assert by_name.key?('NECB-Activity')
    assert by_name.key?('Always On')
  end

  def test_every_space_type_schedule_reference_resolves
    names = schedules.map { |r| r['name'] }.to_set
    missing = []
    space_types.each do |st|
      %w[occupancy_schedule occupancy_activity_schedule electric_equipment_schedule
         infiltration_schedule heating_setpoint_schedule cooling_setpoint_schedule].each do |key|
        ref = st[key]
        missing << "#{st['space_type']}: #{key}=#{ref}" if ref && !names.include?(ref)
      end
    end
    assert_empty missing, "dangling schedule references: #{missing.first(5).inspect}"
  end

  def test_mcp_verified_schedule_a_values
    # Table A-8.4.3.2.(1)-A (2020) == A-8.4.3.2.(1)(b)-A (2025), cell-verified via MCP:
    occ = schedules.find { |r| r['name'] == 'NECB-A-Occupancy' && r['day_types'] == 'Default|Wkdy' }
    assert_equal [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.7, 0.9, 0.9, 0.9, 0.5, 0.5,
                  0.9, 0.9, 0.9, 0.7, 0.3, 0.1, 0.1, 0.1, 0.1, 0.0], occ['values'].map(&:to_f)

    # NOTE legacy transcription convention: all schedules are MIDNIGHT-FIRST —
    # values[0] corresponds to the code table's trailing "12" (midnight) column,
    # then 1a..11p. The 24-value multisets match the code table exactly.
    equip = schedules.find { |r| r['name'] == 'NECB-A-Electric-Equipment' && r['day_types'] == 'Default|Wkdy' }
    assert_equal [0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.3, 0.8, 0.9, 0.9, 0.9, 0.9, 0.9,
                  0.9, 0.9, 0.9, 0.9, 0.5, 0.3, 0.3, 0.2, 0.2, 0.2], equip['values'].map(&:to_f)

    heat = schedules.find { |r| r['name'] == 'NECB-A-Thermostat Setpoint-Heating' && r['day_types'] == 'Default|Wkdy' }
    assert_equal [18.0] * 6 + [20.0] + [22.0] * 14 + [18.0] * 3, heat['values'].map(&:to_f)

    sat = schedules.find { |r| r['name'] == 'NECB-A-Occupancy' && r['day_types'].include?('Sat') }
    assert_equal [0.0] * 24, sat['values'].map(&:to_f), 'schedule A Saturdays unoccupied'
  end

  def test_mcp_verified_load_densities
    # Table A-8.4.3.2.(2)-B: Office 20 m2/occupant + 7.5 W/m2 receptacle, schedule A.
    # Legacy IP: people/1000ft2 = 1000/(20 x 10.7639) = 4.645; W/ft2 = 7.5/10.7639.
    office = space_types.find { |r| r['building_type'] == 'Space Function' && r['space_type'] == 'Office enclosed > 25 m2' }
    refute_nil office
    assert_in_delta 1000.0 / (20 * 10.7639), office['occupancy_per_area'].to_f, 0.05
    assert_in_delta 7.5 / 10.7639, office['electric_equipment_per_area'].to_f, 0.01
    assert_equal 'A', office['necb_schedule_type']

    # Computer/Server room: 100 m2/occupant, 200 W/m2 receptacle (per-schedule variants)
    server = space_types.find { |r| r['space_type'] == 'Computer/Server room-sch-A' && r['building_type'] == 'Space Function' }
    refute_nil server
    assert_in_delta 200 / 10.7639, server['electric_equipment_per_area'].to_f, 0.05
  end

  def test_2025_aliases_2020_with_renumbered_citations
    rules = OpenStudioLoads::NECB.rules('2025')
    assert_equal '2020', OpenStudioLoads::NECB.data_vintage('2025')
    assert_equal 'A-8.4.3.2.(1)(b)', rules['schedule_table_prefix']
    assert_equal 'A-8.4.3.2.(1)', OpenStudioLoads::NECB.rules('2020')['schedule_table_prefix']
    assert_match(/row-by-row/, rules['provenance']['method'])
    assert_equal OpenStudioLoads::NECB.table('2020', 'space_types').size,
                 OpenStudioLoads::NECB.table('2025', 'space_types').size
  end

  def test_coverage_manifest_lint
    %w[2020 2025].each do |vintage|
      coverage = OpenStudioLoads::NECB.rules(vintage)['article_coverage']['articles']
      # 5 core 8.4.3 entries + 8.4.2.7. internal loads (ffb58bc38) + 8.4.3.6.
      # outdoor air (f42f19533) — bump this pin when the manifest grows.
      assert_equal 7, coverage.size, "#{vintage}: subsection 8.4.3 + shared entries accounted"
      article = coverage.find { |a| a['article'] == '8.4.3.2.' }
      assert_equal 'partial', article['status'], 'honest: lighting + SHW excluded'
      assert_match(/openstudio-lighting/, article['gaps'])
      assert_match(/openstudio-shw/, article['gaps'])
      coverage.each do |a|
        assert %w[implemented partial not_implemented satisfied_by_clone host_scope].include?(a['status'])
        assert a['gaps'] || a['how'], "#{a['article']}: has how/gaps"
      end
    end
  end

  def test_space_type_lookup_api
    record = OpenStudioLoads::NECB::SpaceTypes.record(
      building_type: 'Space Function', space_type: 'Office enclosed > 25 m2')
    assert_equal 'A', record['necb_schedule_type']
    assert_raises(ArgumentError) do
      OpenStudioLoads::NECB::SpaceTypes.record(building_type: 'Nope', space_type: 'Nada')
    end
    assert_operator OpenStudioLoads::NECB::SpaceTypes.list.size, :==, 308
  end

  def test_structural_equality_vs_legacy_merged_tables
    legacy_root = File.expand_path('../../lib/openstudio-standards', __dir__)
    skip 'openstudio-standards not present' unless File.exist?("#{legacy_root}.rb")
    begin
      require legacy_root
    rescue LoadError => e
      skip "legacy not loadable: #{e.message[0, 60]}"
    end
    legacy = Standard.build('NECB2020').standards_data
    assert_equal legacy['tables']['space_types']['table'], space_types,
                 'vendored space types == legacy MERGED runtime table'
    assert_equal legacy['tables']['schedules']['table'], schedules,
                 'vendored schedules == legacy MERGED runtime table'
  end
end
