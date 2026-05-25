require_relative '../../test_helper'

# Test chiller efficiency lookups and conversions
# Tests the chiller efficiency lookup methods with properly configured chiller objects
#
# KNOWN ISSUE: The NECB chiller JSON data uses 'minimum_full_load_efficiency' as the field name,
# but Standards.ChillerElectricEIR.rb expects one of these fields:
# - 'minimum_coefficient_of_performance' (COP)
# - 'minimum_energy_efficiency_ratio' (EER)
# - 'minimum_kilowatts_per_tons' (kW/ton)
#
# This causes chiller_electric_eir_standard_minimum_full_load_efficiency() to return nil
# for NECB vintages when called directly. The method works in practice because NECB
# uses chiller_electric_eir_apply_efficiency_and_curves() which has different logic.
#
# Methods tested:
# - Standard#chiller_electric_eir_find_search_criteria
# - OpenstudioStandards::HVAC.cop_to_kw_per_ton
# - OpenstudioStandards::HVAC.kw_per_ton_to_cop
# - OpenstudioStandards::HVAC.eer_to_cop
# - OpenstudioStandards::HVAC.cop_to_eer
#
# References:
# - NECB 2011 Table 5.2.12.1 (Chiller Efficiency Requirements)
# - NECB 2020 Table 5.2.12.1-K (Chiller Efficiency Requirements)
# - CSA-C743-09 (Performance Standard for Rating Water-Chilling and Heat Pump Water-Heating Packages)
class TestChillerEfficiency < Minitest::Test

  # Helper method to create a water-cooled chiller with proper plant loop connections
  def create_water_cooled_chiller(model, name, capacity_watts, compressor_type)
    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    # Ensure name includes compressor type for lookup
    full_name = name.include?(compressor_type) ? name : "#{compressor_type} #{name}"
    chiller.setName(full_name)
    chiller.setReferenceCapacity(capacity_watts)

    # Connect to chilled water loop (supply side)
    chilled_water_loop = OpenStudio::Model::PlantLoop.new(model)
    chilled_water_loop.setName("#{full_name} CHW Loop")
    chilled_water_loop.addSupplyBranchForComponent(chiller)

    # Connect to condenser water loop (demand side) - this makes it WaterCooled
    condenser_water_loop = OpenStudio::Model::PlantLoop.new(model)
    condenser_water_loop.setName("#{full_name} CW Loop")
    condenser_water_loop.addDemandBranchForComponent(chiller)

    return chiller
  end

  # Helper method to create an air-cooled chiller
  def create_air_cooled_chiller(model, name, capacity_watts)
    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller.setName(name)
    chiller.setReferenceCapacity(capacity_watts)

    # Connect only to chilled water loop (supply side) - no condenser loop makes it AirCooled
    chilled_water_loop = OpenStudio::Model::PlantLoop.new(model)
    chilled_water_loop.setName("#{name} CHW Loop")
    chilled_water_loop.addSupplyBranchForComponent(chiller)

    return chiller
  end

  # ============================================================================
  # Efficiency Conversion Tests
  # ============================================================================

  def test_cop_to_kw_per_ton_conversion
    # Test COP to kW/ton conversion
    # COP of 5.0 should convert to approximately 0.7 kW/ton
    # Formula: kW/ton = 3.517 / COP
    cop = 5.0
    kw_per_ton = OpenstudioStandards::HVAC.cop_to_kw_per_ton(cop)

    assert_in_delta 0.703, kw_per_ton, 0.01,
      "COP 5.0 should convert to approximately 0.703 kW/ton"
  end

  def test_kw_per_ton_to_cop_conversion
    # Test kW/ton to COP conversion (reverse)
    # Formula: COP = 3.517 / kW_per_ton
    kw_per_ton = 0.703
    cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)

    assert_in_delta 5.0, cop, 0.1,
      "0.703 kW/ton should convert to approximately COP 5.0"
  end

  def test_round_trip_cop_conversion
    # Test round-trip conversion: COP -> kW/ton -> COP
    original_cop = 4.8

    kw_per_ton = OpenstudioStandards::HVAC.cop_to_kw_per_ton(original_cop)
    recovered_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)

    assert_in_delta original_cop, recovered_cop, 0.01,
      "Round-trip conversion should recover original COP value"
  end

  def test_eer_to_cop_conversion
    # Test EER to COP conversion
    # EER (Btu/W-h) to COP (dimensionless) conversion
    # Formula: COP = EER / 3.412
    eer = 12.0
    cop = OpenstudioStandards::HVAC.eer_to_cop(eer)

    assert_in_delta 3.517, cop, 0.01,
      "EER 12.0 should convert to approximately COP 3.517"
  end

  def test_cop_to_eer_conversion
    # Test COP to EER conversion (reverse)
    # Formula: EER = COP * 3.412
    cop = 3.5
    eer = OpenstudioStandards::HVAC.cop_to_eer(cop)

    assert_in_delta 11.942, eer, 0.01,
      "COP 3.5 should convert to approximately EER 11.942"
  end

  def test_necb2011_expected_cop_values
    # Document the expected COP values from NECB 2011 Table 5.2.12.1
    # These values are calculated from kW/ton in the JSON data
    # Formula: COP = 3.517 / kW_per_ton

    # Scroll chiller < 75 tons: 0.80001 kW/ton
    kw_per_ton = 0.80001
    expected_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
    assert_in_delta 4.40, expected_cop, 0.1,
      "NECB 2011 Scroll < 75 tons should have COP ~4.4 (from 0.80001 kW/ton)"

    # Scroll chiller 75-150 tons: 0.78995 kW/ton
    kw_per_ton = 0.78995
    expected_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
    assert_in_delta 4.45, expected_cop, 0.1,
      "NECB 2011 Scroll 75-150 tons should have COP ~4.45 (from 0.78995 kW/ton)"

    # Centrifugal chiller > 600 tons: 0.58998 kW/ton
    kw_per_ton = 0.58998
    expected_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
    assert_in_delta 5.96, expected_cop, 0.1,
      "NECB 2011 Centrifugal > 600 tons should have COP ~5.96 (from 0.58998 kW/ton)"
  end

  def test_necb2020_expected_cop_values
    # Document the expected COP values from NECB 2020 Table 5.2.12.1-K
    # These values are calculated from kW/ton in the JSON data

    # Scroll chiller < 75 tons: 0.77927 kW/ton
    kw_per_ton = 0.77927
    expected_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
    assert_in_delta 4.51, expected_cop, 0.1,
      "NECB 2020 Scroll < 75 tons should have COP ~4.51 (from 0.77927 kW/ton)"

    # Air-cooled chiller: 1.22709 kW/ton
    kw_per_ton = 1.22709
    expected_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
    assert_in_delta 2.87, expected_cop, 0.1,
      "NECB 2020 Air-cooled should have COP ~2.87 (from 1.22709 kW/ton)"

    # Centrifugal chiller > 400 tons: 0.58439 kW/ton
    kw_per_ton = 0.58439
    expected_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(kw_per_ton)
    assert_in_delta 6.02, expected_cop, 0.1,
      "NECB 2020 Centrifugal > 400 tons should have COP ~6.02 (from 0.58439 kW/ton)"
  end

  # ============================================================================
  # Search Criteria Tests
  # ============================================================================

  def test_find_search_criteria_water_cooled_scroll
    # Test that search criteria are correctly determined for water-cooled scroll chiller
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = create_water_cooled_chiller(model, 'Scroll Chiller', 351680.0, 'Scroll')

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'NECB2011', search_criteria['template'],
      "Search criteria should include template"
    assert_equal 'WaterCooled', search_criteria['cooling_type'],
      "Search criteria should identify cooling type as WaterCooled"
    assert_equal 'Scroll', search_criteria['compressor_type'],
      "Search criteria should identify compressor type from name"
    assert_equal 'Path A', search_criteria['compliance_path'],
      "Search criteria should include default compliance path"
  end

  def test_find_search_criteria_water_cooled_reciprocating
    # Test search criteria for reciprocating chiller
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = create_water_cooled_chiller(model, 'Reciprocating Chiller', 351680.0, 'Reciprocating')

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'WaterCooled', search_criteria['cooling_type'],
      "Search criteria should identify cooling type as WaterCooled"
    assert_equal 'Reciprocating', search_criteria['compressor_type'],
      "Search criteria should identify Reciprocating compressor type from name"
  end

  def test_find_search_criteria_water_cooled_rotary_screw
    # Test search criteria for rotary screw chiller
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = create_water_cooled_chiller(model, 'Rotary Screw Chiller', 632976.0, 'Rotary Screw')

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'WaterCooled', search_criteria['cooling_type'],
      "Search criteria should identify cooling type as WaterCooled"
    assert_equal 'Rotary Screw', search_criteria['compressor_type'],
      "Search criteria should identify Rotary Screw compressor type from name"
  end

  def test_find_search_criteria_water_cooled_centrifugal
    # Test search criteria for centrifugal chiller
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = create_water_cooled_chiller(model, 'Centrifugal Chiller', 2813440.0, 'Centrifugal')

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'WaterCooled', search_criteria['cooling_type'],
      "Search criteria should identify cooling type as WaterCooled"
    assert_equal 'Centrifugal', search_criteria['compressor_type'],
      "Search criteria should identify Centrifugal compressor type from name"
  end

  def test_find_search_criteria_air_cooled
    # Test that search criteria are correctly determined for air-cooled chiller
    standard = Standard.build('NECB2020')
    model = OpenStudio::Model::Model.new

    chiller = create_air_cooled_chiller(model, 'WithCondenser Chiller', 351680.0)

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'NECB2020', search_criteria['template'],
      "Search criteria should include template"
    assert_equal 'AirCooled', search_criteria['cooling_type'],
      "Search criteria should identify cooling type as AirCooled"
    assert_equal 'WithCondenser', search_criteria['condenser_type'],
      "Search criteria should identify condenser type from name"
  end

  def test_find_search_criteria_with_additional_properties
    # Test that compressor type can be set via additional properties
    standard = Standard.build('NECB2011')
    model = OpenStudio::Model::Model.new

    chiller = create_water_cooled_chiller(model, 'Test Chiller', 351680.0, 'Generic')

    # Set compressor type via additional properties
    chiller.additionalProperties.setFeature('compressor_type', 'Scroll')

    search_criteria = standard.chiller_electric_eir_find_search_criteria(chiller)

    assert_equal 'Scroll', search_criteria['compressor_type'],
      "Search criteria should use compressor_type from additional properties"
  end

  # ============================================================================
  # Capacity Conversion Tests
  # ============================================================================

  def test_capacity_tons_to_watts_conversion
    # Test conversion between tons and watts
    # 1 ton = 3.517 kW = 3517 W
    tons = 100.0
    watts = OpenStudio.convert(tons, 'ton', 'W').get

    assert_in_delta 351680.0, watts, 10.0,
      "100 tons should equal approximately 351,680 W"
  end

  def test_capacity_watts_to_tons_conversion
    # Test reverse conversion
    watts = 351680.0
    tons = OpenStudio.convert(watts, 'W', 'ton').get

    assert_in_delta 100.0, tons, 0.1,
      "351,680 W should equal approximately 100 tons"
  end

  def test_small_capacity_boundary
    # Test 75 ton boundary (263,760 W)
    tons = 75.0
    watts = OpenStudio.convert(tons, 'ton', 'W').get

    assert_in_delta 263760.0, watts, 10.0,
      "75 tons should equal approximately 263,760 W"
  end

  def test_large_capacity_boundary
    # Test 600 ton boundary (2,110,080 W)
    tons = 600.0
    watts = OpenStudio.convert(tons, 'ton', 'W').get

    assert_in_delta 2110080.0, watts, 100.0,
      "600 tons should equal approximately 2,110,080 W"
  end

  # ============================================================================
  # Chiller Type Detection Tests
  # ============================================================================

  def test_chiller_condenser_type_detection_water_cooled
    # Test that connecting to condenser loop makes chiller WaterCooled
    model = OpenStudio::Model::Model.new
    chiller = create_water_cooled_chiller(model, 'Test Chiller', 351680.0, 'Scroll')

    condenser_type = chiller.condenserType

    assert_equal 'WaterCooled', condenser_type,
      "Chiller connected to condenser loop should be WaterCooled"
  end

  def test_chiller_condenser_type_detection_air_cooled
    # Test that NOT connecting to condenser loop makes chiller AirCooled
    model = OpenStudio::Model::Model.new
    chiller = create_air_cooled_chiller(model, 'Test Chiller', 351680.0)

    condenser_type = chiller.condenserType

    assert_equal 'AirCooled', condenser_type,
      "Chiller not connected to condenser loop should be AirCooled"
  end

  # ============================================================================
  # NECB Vintage Tests
  # ============================================================================

  def test_necb_vintages_exist
    # Test that all NECB vintages can be instantiated
    vintages = ['NECB2011', 'NECB2015', 'NECB2017', 'NECB2020']

    vintages.each do |vintage|
      standard = Standard.build(vintage)
      refute_nil standard, "Should be able to create #{vintage} standard"
      assert_equal vintage, standard.template, "Template name should match #{vintage}"
    end
  end

  def test_necb2015_inherits_from_necb2011
    # NECB2015 inherits from NECB2011 for chiller data (no separate chillers.json)
    necb2015_standard = Standard.build('NECB2015')

    # Check that the class hierarchy is correct
    assert necb2015_standard.is_a?(NECB2011),
      "NECB2015 should inherit from NECB2011"
  end

  def test_necb2017_inherits_from_necb2015
    # NECB2017 inherits from NECB2015
    necb2017_standard = Standard.build('NECB2017')

    # Check that the class hierarchy is correct
    assert necb2017_standard.is_a?(NECB2015),
      "NECB2017 should inherit from NECB2015"
  end

  def test_necb2020_has_own_chiller_data
    # NECB2020 has its own chillers.json file with different efficiency values
    necb2020_standard = Standard.build('NECB2020')

    # Verify NECB2020 is a NECB2017 subclass
    assert necb2020_standard.is_a?(NECB2017),
      "NECB2020 should inherit from NECB2017"

    # NECB2020 loads its own chiller data which overrides NECB2011 data
    # The data file exists at: lib/openstudio-standards/standards/necb/NECB2020/data/chillers.json
    assert File.exist?(File.join(__dir__, '../../../../lib/openstudio-standards/standards/necb/NECB2020/data/chillers.json')),
      "NECB2020 should have its own chillers.json data file"
  end

end
