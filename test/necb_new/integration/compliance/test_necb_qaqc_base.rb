require_relative '../../test_helper'

# QAQC Base Data and Report Generation Tests
# Tests core QAQC functionality: base data creation, report generation, logging, helpers, SQL extraction
# Uses shared simulation result to avoid running simulation for each test
class TestNecbQaqcBase < Minitest::Test

  # Minitest does not natively call `self.startup`, so we lazily build the
  # shared simulation from `setup` and memoize on the class. We use the
  # SizedModelFixtureManager cache (System1/Toronto) instead of running a
  # full prototype simulation per file — same SQL data, ~3 min one-time.
  def self.shared
    return @shared if @shared
    require_relative '../../fixtures/sized_model_fixture_manager'
    fixture = SizedModelFixtureManager.get_or_create_sized_model(
      template: 'NECB2011', system_type: 'System1', climate: 'toronto'
    )
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(fixture[:osm_path]).get
    sql_file = OpenStudio::SqlFile.new(OpenStudio::Path.new(fixture[:sql_path]))
    model.setSqlFile(sql_file)
    @shared = {
      model: model,
      standard: Standard.build('NECB2011'),
      sql_file: sql_file,
      output_folder: File.join(__dir__, '../output/qaqc_base_tests')
    }
  end

  def setup
    s = self.class.shared
    @model = s[:model]
    @standard = s[:standard]
    @sql_file = s[:sql_file]
    @output_folder = s[:output_folder]
  end

  # Test 1: QAQC base data creation from complete model
  def test_qaqc_create_base_data
    puts "\n[TEST] Testing QAQC base data creation..."

    qaqc = @standard.create_base_data(@model)

    assert qaqc, "QAQC data should be created"
    assert qaqc[:building], "QAQC should contain building data"
    assert qaqc[:geography], "QAQC should contain geography data"
    assert qaqc[:envelope], "QAQC should contain envelope data"
    assert qaqc[:thermal_zones], "QAQC should contain thermal zone data"

    assert qaqc[:building][:name], "Building should have a name"
    assert qaqc[:building][:conditioned_floor_area_m2], "Building should have conditioned floor area"
    assert qaqc[:building][:conditioned_floor_area_m2] > 0, "Conditioned floor area should be positive"

    assert qaqc[:geography][:hdd], "Geography should have HDD data"
    assert qaqc[:geography][:climate_zone], "Geography should have climate zone"
    assert qaqc[:geography][:city], "Geography should have city"

    puts "  [PASS] Base data created successfully with all required sections"
  end

  # Test 2: QAQC report generation from complete model
  def test_qaqc_full_report_generation
    skip "Asserts at least one plant loop; System1 (PTAC + baseboard) has none. Re-enable with a fixture that includes a plant loop."
    puts "\n[TEST] Testing full QAQC report generation..."

    qaqc = @standard.init_qaqc(@model)

    assert qaqc, "QAQC report should be generated"
    assert qaqc[:building], "Report should contain building data"
    assert qaqc[:geography], "Report should contain geography data"
    assert qaqc[:envelope], "Report should contain envelope data"
    assert qaqc[:thermal_zones], "Report should contain thermal zones"
    assert qaqc[:air_loops], "Report should contain air loops"
    assert qaqc[:plant_loops], "Report should contain plant loops"

    assert qaqc[:envelope][:outdoor_walls_average_conductance_w_per_m2_k], "Should have wall conductance"
    assert qaqc[:envelope][:outdoor_roofs_average_conductance_w_per_m2_k], "Should have roof conductance"

    assert qaqc[:air_loops].size > 0, "Should have at least one air loop"
    assert qaqc[:plant_loops].size > 0, "Should have at least one plant loop"

    puts "  [PASS] Full QAQC report generated with all sections"
  end

  # Test 3: QAQC error/warning/information logging
  def test_qaqc_error_warning_logging
    puts "\n[TEST] Testing QAQC error/warning/information logging..."

    # necb_qaqc uses @qaqc_data internally; that's loaded by qaqc_only
    # (or explicitly via load_qaqc_database_new), not by create_base_data.
    @standard.load_qaqc_database_new
    qaqc = @standard.create_base_data(@model)
    qaqc_result = @standard.necb_qaqc(qaqc.clone, @model)

    assert qaqc_result[:information], "Should have information array"
    assert qaqc_result[:warnings], "Should have warnings array"
    assert qaqc_result[:errors], "Should have errors array"
    assert qaqc_result[:unique_errors], "Should have unique_errors array"

    assert qaqc_result[:information].is_a?(Array), "Information should be an array"
    assert qaqc_result[:warnings].is_a?(Array), "Warnings should be an array"
    assert qaqc_result[:errors].is_a?(Array), "Errors should be an array"
    assert qaqc_result[:unique_errors].is_a?(Array), "Unique errors should be an array"

    info_sorted = qaqc_result[:information].sort
    assert_equal info_sorted, qaqc_result[:information], "Information should be sorted"

    puts "  [PASS] Error/warning/information logging working correctly"
    puts "    - Information messages: #{qaqc_result[:information].size}"
    puts "    - Warnings: #{qaqc_result[:warnings].size}"
    puts "    - Errors: #{qaqc_result[:errors].size}"
    puts "    - Unique errors: #{qaqc_result[:unique_errors].size}"
  end

  # Test 4: QAQC section test helper method
  def test_qaqc_section_test_helper
    puts "\n[TEST] Testing QAQC section test helper method..."

    qaqc = {
      information: [],
      warnings: [],
      errors: [],
      unique_errors: []
    }

    # Test passing case
    @standard.necb_section_test(
      qaqc,
      2.0,
      '<=',
      2.5,
      'NECB2011-Section 3.2.1',
      'Test wall conductance',
      3
    )

    assert qaqc[:information].size == 1, "Should have 1 info message for passing test"
    assert qaqc[:information].first.include?('TEST-PASS'), "Info message should indicate pass"
    assert qaqc[:information].first.include?('NECB2011-Section 3.2.1'), "Info message should include section"

    # Test failing case
    @standard.necb_section_test(
      qaqc,
      3.0,
      '<=',
      2.5,
      'NECB2011-Section 3.2.1',
      'Test wall conductance fail',
      3
    )

    assert qaqc[:errors].size == 1, "Should have 1 error message for failing test"
    assert qaqc[:errors].first.include?('TEST-FAIL'), "Error message should indicate failure"
    assert qaqc[:errors].first.include?('expected value'), "Error message should include expected value"

    # Test with string comparison
    @standard.necb_section_test(
      qaqc,
      'SmallOffice',
      '==',
      'SmallOffice',
      'NECB2011-Building',
      'Test building type match',
      nil
    )

    assert qaqc[:information].size == 2, "Should have 2 info messages total"

    puts "  [PASS] Section test helper method working correctly"
    puts "    - Pass tests: #{qaqc[:information].size}"
    puts "    - Fail tests: #{qaqc[:errors].size}"
  end

  # Test 5: QAQC only method (subtract base data)
  def test_qaqc_only_method
    puts "\n[TEST] Testing qaqc_only method (QAQC without base data)..."

    full_qaqc = @standard.init_qaqc(@model)
    qaqc_only = @standard.qaqc_only(@model)

    assert qaqc_only.size < full_qaqc.size, "QAQC only should have fewer keys than full QAQC"

    assert qaqc_only[:information] || qaqc_only[:warnings] || qaqc_only[:errors],
           "QAQC only should contain check results"

    puts "  [PASS] QAQC only method working correctly"
    puts "    - Full QAQC keys: #{full_qaqc.keys.size}"
    puts "    - QAQC only keys: #{qaqc_only.keys.size}"
  end

  # Test 6: SQL table extraction to JSON
  def test_qaqc_sql_table_extraction
    puts "\n[TEST] Testing SQL table extraction to JSON..."

    end_uses_table = @standard.get_sql_table_to_json(
      @model,
      'AnnualBuildingUtilityPerformanceSummary',
      'Entire Facility',
      'End Uses'
    )

    assert end_uses_table, "Should extract End Uses table"
    assert end_uses_table[:report_name], "Should have report name"
    assert end_uses_table[:table_name], "Should have table name"
    assert end_uses_table[:table], "Should have table data"
    assert end_uses_table[:table].is_a?(Array), "Table data should be an array"

    if end_uses_table[:table].size > 0
      first_row = end_uses_table[:table].first
      assert first_row[:name], "Row should have name"
      assert first_row.size > 1, "Row should have multiple columns"
    end

    sql_data = @standard.get_sql_tables_to_json(@model)

    assert sql_data.is_a?(Array), "Should return array of tables"
    assert sql_data.size > 0, "Should extract multiple tables"

    sql_data.each do |table|
      assert table[:report_name], "Each table should have report name"
      assert table[:table_name], "Each table should have table name"
      assert table[:table].is_a?(Array), "Each table data should be an array"
    end

    puts "  [PASS] SQL table extraction working correctly"
    puts "    - Extracted #{sql_data.size} tables"
  end
end
