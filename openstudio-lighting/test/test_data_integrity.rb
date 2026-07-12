require_relative 'test_helper'

# P1 gate: vendored lighting data is sound and the 2025 verification holds.
class TestDataIntegrity < Minitest::Test
  def test_led_table_matches_legacy_shape
    led = OpenStudioLighting::NECB.table('led_lighting_2020')
    assert_equal 308, led.size
    record = OpenStudioLighting::NECB.led_record(building_type: 'Space Function',
                                                 space_type: 'Office enclosed > 25 m2')
    refute_nil record
    assert_operator record['lighting_per_area'].to_f, :>, 0
    assert record.key?('lighting_fraction_radiant')
  end

  def test_2025_space_function_table
    rows = OpenStudioLighting::NECB.table('lpd_space_functions_2025')
    assert_operator rows.size, :>=, 90
    atrium = rows.select { |r| r['space_category'] == 'Atrium' }.map { |r| r['lpd_w_per_m2'] }
    assert_equal [4.2, 5.2, 6.5], atrium.sort, '2025 atrium bins == 2020 legacy values'
    office = rows.find { |r| r['space_category'] == 'Office' || r['space_type'].to_s.include?('enclosed') }
    refute_nil office
    with_controls = rows.count { |r| !r['controls_4_2_2_1'].empty? }
    assert_operator with_controls, :>, 80, 'the 2025 4.2.2.1 control matrix is vendored'
  end

  def test_2025_building_type_table
    rows = OpenStudioLighting::NECB.table('lpd_building_types_2025')
    assert_equal 32, rows.size
    office = rows.find { |r| r['building_type'] == 'Office' }
    assert_in_delta 6.9, office['lpd_w_per_m2'], 1e-9
    assert_in_delta 1.9, rows.find { |r| r['building_type'] == 'Storage garage' }['lpd_w_per_m2'], 1e-9
  end

  def test_2020_lpds_spot_verified_vs_space_types
    # atrium bins in the loads-gem space-type records equal the code values
    %w[A].each do |letter|
      { "Atrium (height < 6m)-sch-#{letter}" => 4.2,
        "Atrium (6 =< height <= 12m)-sch-#{letter}" => 5.2,
        "Atrium (height > 12m)-sch-#{letter}" => 6.5 }.each do |name, si|
        record = OpenStudioLoads::NECB::SpaceTypes.record(building_type: 'Space Function', space_type: name)
        assert_in_delta si, record['lighting_per_area'].to_f * 10.7639, 0.05, name
      end
    end
  end

  def test_rules_and_coverage_lint
    %w[2020 2025].each do |vintage|
      rules = OpenStudioLighting::NECB.rules(vintage)
      assert_in_delta 0.799256505, rules['sensor_schedule_lpd_threshold_w_per_ft2'], 1e-9
      assert_equal 5.0, rules['dwelling_unit_lpd_w_per_m2']
      assert rules['atrium_led']['below_12m']['slope']
      coverage = rules['article_coverage']['articles']
      assert_operator coverage.size, :>=, 7
      coverage.each do |article|
        assert %w[implemented partial not_implemented satisfied_by_clone host_scope].include?(article['status'])
        assert article['how'] || article['gaps']
      end
    end
    assert_equal '2020', OpenStudioLighting::NECB.data_vintage('2025')
    assert_match(/zero LPD differences|ZERO value differences/i,
                 OpenStudioLighting::NECB.rules('2025')['provenance']['method'])
  end
end
