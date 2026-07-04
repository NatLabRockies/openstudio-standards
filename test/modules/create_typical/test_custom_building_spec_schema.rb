require_relative '../../helpers/minitest_helper'

begin
  require 'json_schemer'
  JSON_SCHEMER_AVAILABLE = true
rescue LoadError
  JSON_SCHEMER_AVAILABLE = false
end

# Pins the shipped custom building spec JSON Schema to the hand-rolled runtime validator:
# the schema itself must be valid, the shipped examples must validate against both, and
# targeted invalid specs must fail both. Requires the json_schemer development dependency;
# tests are skipped when it is not installed.
class TestCustomBuildingSpecSchema < Minitest::Test
  def setup
    skip 'json_schemer gem is not installed (development dependency)' unless JSON_SCHEMER_AVAILABLE
    @schema_path = OpenstudioStandards::CreateTypical::CUSTOM_BUILDING_SPEC_SCHEMA_PATH
    @schema = JSON.parse(File.read(@schema_path))
    @schemer = JSONSchemer.schema(@schema)
    @examples_dir = File.expand_path('../../../lib/openstudio-standards/create_typical/data/examples', __dir__)
  end

  # a structurally valid base spec to mutate in the invalid-spec cases
  def base_spec
    {
      'template' => '90.1-2013',
      'climate_zone' => 'ASHRAE 169-2013-4A',
      'space_type_ratios' => [
        { 'building_type' => 'MediumOffice', 'space_type' => 'OpenOffice', 'ratio' => 0.7 },
        { 'building_type' => 'MediumOffice', 'space_type' => 'Conference', 'ratio' => 0.3 }
      ]
    }
  end

  def test_schema_is_valid_draft_2020_12
    if JSONSchemer.respond_to?(:valid_schema?)
      assert(JSONSchemer.valid_schema?(@schema), 'schema file is not a valid JSON Schema')
    else
      # older json_schemer: constructing the schemer and validating raises on schema errors
      assert(@schemer.valid?(base_spec))
    end
  end

  def test_example_specs_validate
    example_files = Dir.glob("#{@examples_dir}/*.json")
    refute_empty(example_files, 'no example specs found')
    example_files.each do |file|
      example = JSON.parse(File.read(file))
      schema_errors = @schemer.validate(example).to_a
      assert_empty(schema_errors, "#{File.basename(file)} fails schema validation: #{schema_errors.map { |e| e['error'] }}")

      # the runtime validator must accept the examples too (structural + live data)
      runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(File.read(file), symbolize_names: true))
      assert_empty(runtime_errors, "#{File.basename(file)} fails runtime validation: #{runtime_errors}")
    end
  end

  # each invalid spec must fail schema validation AND produce an error from the
  # runtime validator, pinning the hand-rolled validator to the schema
  def invalid_specs
    missing_ratio = base_spec
    missing_ratio['space_type_ratios'][0].delete('ratio')

    ratio_too_big = base_spec
    ratio_too_big['space_type_ratios'][0]['ratio'] = 1.5

    unknown_top_key = base_spec.merge('bogus_key' => 1)

    missing_template = base_spec.tap { |s| s.delete('template') }

    unkeyed_override = base_spec.merge('load_overrides' => [{ 'lighting' => { 'w_per_area' => 0.9 } }])

    misspelled_load_field = base_spec.merge('load_overrides' => [{ 'space_type' => '*', 'lighting' => { 'watts_per_area' => 0.9 } }])

    bad_form_key = base_spec.merge('form' => { 'total_floor_area' => 10000.0 })

    {
      'missing ratio' => missing_ratio,
      'ratio above 1' => ratio_too_big,
      'unknown top-level key' => unknown_top_key,
      'missing template' => missing_template,
      'override entry without match key' => unkeyed_override,
      'misspelled load override field' => misspelled_load_field,
      'unknown form key' => bad_form_key
    }
  end

  def test_invalid_specs_fail_both_validators
    invalid_specs.each do |label, spec|
      refute(@schemer.valid?(spec), "'#{label}' spec should fail schema validation")
      symbol_spec = JSON.parse(JSON.generate(spec), symbolize_names: true)
      runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(symbol_spec)
      refute_empty(runtime_errors, "'#{label}' spec should fail runtime validation")
    end
  end

  def test_runtime_validator_live_data_checks
    # the schema cannot express these; the runtime validator must catch them
    bad_template = base_spec.merge('template' => 'not-a-template')
    bad_sum = base_spec.tap { |s| s['space_type_ratios'][0]['ratio'] = 0.5 }
    bad_pair = base_spec.tap { |s| s['space_type_ratios'][0]['space_type'] = 'NotASpaceType' }
    bad_primary = base_spec.merge('primary_building_type' => 'MyCustomType')

    [bad_template, bad_sum, bad_pair, bad_primary].each do |spec|
      # all of these are structurally valid per the schema
      assert(@schemer.valid?(spec))
      symbol_spec = JSON.parse(JSON.generate(spec), symbolize_names: true)
      refute_empty(OpenstudioStandards::CreateTypical.validate_custom_building_spec(symbol_spec))
    end
  end
end
