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
    # includes specs in subdirectories, e.g. examples/doe_prototypes
    example_files = Dir.glob("#{@examples_dir}/**/*.json")
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

    misspelled_exhaust_field = base_spec.merge('exhaust_overrides' => [{ 'space_type' => 'imaging', 'exhaust' => { 'cfm_per_area' => 0.0 } }])

    exhaust_override_without_a_rate = base_spec.merge('exhaust_overrides' => [{ 'space_type' => 'imaging', 'exhaust' => {} }])

    # the constructions section reaches the validators through oneOf; a validator that
    # skipped the keyword would let every one of these through
    constructions_unknown_surface = base_spec.merge('constructions' => { 'surfaces' => { 'exterior_parapet' => 'x' } })
    constructions_slots_key = base_spec.merge('constructions' => { 'slots' => { 'interior_walls' => 'Typical Interior Wall' } })
    constructions_pin_and_type = base_spec.merge('constructions' => {
                                                   'surfaces' => { 'exterior_wall' => { 'construction' => 'Typical Insulated Exterior Mass Wall',
                                                                                        'construction_type' => 'Mass' } }
                                                 })
    constructions_wrong_field = base_spec.merge('constructions' => { 'wall_type' => 'Mass' })
    constructions_bad_enum = base_spec.merge('constructions' => { 'exterior_wall_type' => 'Steel Framed' })
    constructions_bad_residential = base_spec.merge('constructions' => { 'is_residential' => 'yes' })
    constructions_set_without_selector = base_spec.merge('constructions' => {
                                                           'sets' => [{ 'name' => 'orphan', 'exterior_wall_type' => 'Mass' }]
                                                         })

    {
      'missing ratio' => missing_ratio,
      'ratio above 1' => ratio_too_big,
      'unknown top-level key' => unknown_top_key,
      'missing template' => missing_template,
      'override entry without match key' => unkeyed_override,
      'misspelled load override field' => misspelled_load_field,
      'unknown form key' => bad_form_key,
      'misspelled exhaust override field' => misspelled_exhaust_field,
      'exhaust override with no rate' => exhaust_override_without_a_rate,
      'unknown construction surface' => constructions_unknown_surface,
      'slots is not a constructions key' => constructions_slots_key,
      'surface pinning a construction and naming a type' => constructions_pin_and_type,
      'misspelled construction field' => constructions_wrong_field,
      'construction type not in the enum' => constructions_bad_enum,
      'is_residential as a string' => constructions_bad_residential,
      'construction set entry without a selector' => constructions_set_without_selector
    }
  end

  def test_exhaust_overrides_validate
    spec = base_spec.merge('exhaust_overrides' => [
                             { 'space_type' => 'imaging', 'exhaust' => { 'exhaust_per_area' => 0.0 } },
                             { 'space_type' => '*', 'exhaust' => { 'exhaust_per_area' => 0.25 } }
                           ])
    assert(@schemer.valid?(spec), "exhaust override spec should pass schema validation: #{@schemer.validate(spec).to_a}")
    runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(spec), symbolize_names: true))
    assert_empty(runtime_errors, "exhaust override spec fails runtime validation: #{runtime_errors}")
  end

  def test_constructions_section_validates
    spec = base_spec.merge('constructions' => {
                             'building_category' => 'Nonresidential',
                             'is_residential' => false,
                             'exterior_wall_type' => 'Mass',
                             'exterior_roof_type' => 'IEAD',
                             'exterior_floor_type' => 'Mass',
                             'surfaces' => {
                               'ground_contact_floor' => { 'construction_type' => 'Unheated' },
                               'interior_walls' => 'Typical Interior Wall',
                               'interior_partitions' => { 'construction' => 'Typical Interior Partition' }
                             }
                           })
    assert(@schemer.valid?(spec), "construction spec should pass schema validation: #{@schemer.validate(spec).to_a}")
    runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(spec), symbolize_names: true))
    assert_empty(runtime_errors, "construction spec fails runtime validation: #{runtime_errors}")

    # naming a single surface and inheriting the rest is a legitimate spec
    partial = base_spec.merge('constructions' => { 'exterior_wall_type' => 'SteelFramed' })
    assert(@schemer.valid?(partial), "partial construction spec should validate: #{@schemer.validate(partial).to_a}")

    # an unknown slot or field is a typo, not an extension point
    refute_both_validators(base_spec.merge('constructions' => { 'slots' => { 'interior_walls' => 'Typical Interior Wall' } }), 'slots is not a key')
    refute_both_validators(base_spec.merge('constructions' => { 'wall_type' => 'Mass' }), 'misspelled field')
    refute_both_validators(base_spec.merge('constructions' => { 'is_residential' => 'yes' }), 'is_residential as a string')
  end

  # an invalid spec has to fail the shipped schema and the runtime validator alike --
  # asserting only one of them is how the two drift apart
  def refute_both_validators(spec, label)
    refute(@schemer.valid?(spec), "'#{label}' spec should fail schema validation")
    runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(spec), symbolize_names: true))
    refute_empty(runtime_errors, "'#{label}' spec should fail runtime validation")
  end

  def test_construction_sets_collection_validates
    spec = base_spec.merge('constructions' => {
                             'default' => { 'building_category' => 'Nonresidential', 'exterior_wall_type' => 'Mass' },
                             'sets' => [
                               { 'name' => 'residential tower',
                                 'space_types' => ['apartment', 'guest room'],
                                 'is_residential' => true,
                                 'building_category' => 'Residential',
                                 'exterior_wall_type' => 'SteelFramed' },
                               { 'name' => 'apartments by building type',
                                 'building_types' => ['MidriseApartment'],
                                 'surfaces' => { 'exterior_skylight' => { 'construction_type' => 'Glass with Curb' } } }
                             ]
                           })
    assert(@schemer.valid?(spec), "construction set collection should validate: #{@schemer.validate(spec).to_a}")
    runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(spec), symbolize_names: true))
    assert_empty(runtime_errors, "construction set collection fails runtime validation: #{runtime_errors}")

    # an entry has to say which space types it governs
    refute_both_validators(base_spec.merge('constructions' => {
                                             'sets' => [{ 'name' => 'orphan', 'exterior_wall_type' => 'Mass' }]
                                           }), 'set entry with no selector')

    # sets without entries is a typo, not an empty configuration
    refute_both_validators(base_spec.merge('constructions' => { 'sets' => [] }), 'empty sets')
  end

  # The construction type and category strings are enumerated so a typo fails validation instead
  # of being logged at runtime and silently leaving the surface on an OpenStudio default.
  def test_construction_strings_are_enumerated
    valid = base_spec.merge('constructions' => {
                              'exterior_wall_type' => 'Metal Building',
                              'exterior_roof_type' => 'Attic and Other',
                              'exterior_floor_type' => 'SteelFramed',
                              'building_category' => 'Semiheated',
                              'surfaces' => {
                                'ground_contact_floor' => { 'construction_type' => 'Unheated', 'building_category' => 'Any' },
                                'exterior_glass_door' => { 'construction_type' => 'Metal framing, entrance door' },
                                'exterior_overhead_door' => { 'construction_type' => 'NonSwinging' },
                                'exterior_skylight' => { 'construction_type' => 'Plastic with Curb' }
                              }
                            })
    assert(@schemer.valid?(valid), "enumerated values should validate: #{@schemer.validate(valid).to_a}")

    # a wall type that is only valid for roofs
    refute_both_validators(base_spec.merge('constructions' => { 'exterior_wall_type' => 'IEAD' }), 'roof type on a wall')
    # a roof type that is only valid for walls
    refute_both_validators(base_spec.merge('constructions' => { 'exterior_roof_type' => 'SteelFramed' }), 'wall type on a roof')
    # a door type in a window slot
    refute_both_validators(base_spec.merge('constructions' => {
                                             'surfaces' => { 'exterior_fixed_window' => { 'construction_type' => 'Swinging' } }
                                           }), 'door type in a window slot')
    # a category that is not one of the six
    refute_both_validators(base_spec.merge('constructions' => { 'building_category' => 'Commercial' }), 'unknown category')
    # a plain typo
    refute_both_validators(base_spec.merge('constructions' => { 'exterior_wall_type' => 'Steel Framed' }), 'misspelled construction type')
  end

  # Every enumerated value has to exist in the shipped construction_properties data, or the schema
  # would be advertising strings that resolve to nothing.
  def test_enumerated_values_exist_in_the_standards_data
    slot_surface = {
      'exterior_floor' => 'ExteriorFloor', 'exterior_wall' => 'ExteriorWall', 'exterior_roof' => 'ExteriorRoof',
      'ground_contact_floor' => 'GroundContactFloor', 'ground_contact_wall' => 'GroundContactWall',
      'exterior_fixed_window' => 'ExteriorWindow', 'exterior_operable_window' => 'ExteriorWindow',
      'exterior_door' => 'ExteriorDoor', 'exterior_overhead_door' => 'ExteriorDoor',
      'exterior_glass_door' => 'GlassDoor', 'exterior_skylight' => 'Skylight'
    }
    rows = Dir.glob("#{File.expand_path('../../../lib/openstudio-standards/standards', __dir__)}/**/*.construction_properties.json")
              .flat_map { |f| JSON.parse(File.read(f))['construction_properties'] || [] }
    by_surface = Hash.new { |h, k| h[k] = [] }
    rows.each { |r| by_surface[r['intended_surface_type']] << r['standards_construction_type'] }
    by_surface.each_value(&:uniq!)
    categories = rows.map { |r| r['building_category'] }.compact.uniq

    slot_surface.each do |slot, surface|
      lookup_form = @schema['$defs']["construction_surface_#{slot}"]['oneOf'].find { |branch| branch['properties']&.key?('construction_type') }
      refute_nil(lookup_form, "#{slot} has no assembly-lookup form")
      enum = lookup_form['properties']['construction_type']['enum']
      refute_nil(enum, "#{slot} has no enumerated construction types")
      enum.each { |value| assert_includes(by_surface[surface], value, "#{slot}: '#{value}' is not a #{surface} construction type in the standards data") }
      assert_equal(by_surface[surface].compact.sort, enum.sort, "#{slot}: the enum has drifted from the #{surface} rows in the standards data")
    end

    schema_categories = @schema['$defs']['construction_spec']['properties']['building_category']['enum']
    assert_equal(categories.sort, schema_categories.sort, 'the building_category enum has drifted from the standards data')
  end

  def test_invalid_specs_fail_both_validators
    invalid_specs.each do |label, spec|
      refute(@schemer.valid?(spec), "'#{label}' spec should fail schema validation")
      symbol_spec = JSON.parse(JSON.generate(spec), symbolize_names: true)
      runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(symbol_spec)
      refute_empty(runtime_errors, "'#{label}' spec should fail runtime validation")
    end
  end

  # a structurally valid spec using typical (level-1) space type entries
  def typical_base_spec
    {
      'template' => '90.1-2013',
      'climate_zone' => 'ASHRAE 169-2013-4A',
      'primary_building_type' => 'MediumOffice',
      'space_type_ratios' => [
        { 'space_type' => 'office', 'ratio' => 0.7 },
        { 'space_type' => 'conference/meeting/multipurpose', 'ratio' => 0.3 }
      ]
    }
  end

  def test_typical_space_type_entries
    # valid typical spec passes both validators
    spec = typical_base_spec
    assert(@schemer.valid?(spec), 'typical entry spec should pass schema validation')
    runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(spec), symbolize_names: true))
    assert_empty(runtime_errors, "typical entry spec fails runtime validation: #{runtime_errors}")

    # these are structurally valid per the schema; the runtime validator must catch them
    mixed = typical_base_spec
    mixed['space_type_ratios'][0] = { 'building_type' => 'MediumOffice', 'space_type' => 'OpenOffice', 'ratio' => 0.7 }

    bad_name = typical_base_spec
    bad_name['space_type_ratios'][0]['space_type'] = 'not a typical space type'

    no_primary = typical_base_spec.tap { |s| s.delete('primary_building_type') }

    managed_load_method = typical_base_spec.merge('typical_options' => { 'space_type_load_method' => 'typical' })

    { 'mixed entry forms' => mixed,
      'unknown typical space type' => bad_name,
      'typical entries without primary_building_type' => no_primary,
      'space_type_load_method in typical_options' => managed_load_method }.each do |label, bad_spec|
      assert(@schemer.valid?(bad_spec), "'#{label}' spec should pass schema validation")
      runtime_errors = OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(bad_spec), symbolize_names: true))
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

# Runtime-validator-only cases for the constructions section, in their own class so they run
# where json_schemer is not installed. The section reaches the validator through oneOf, which
# it has to interpret rather than skip: an ignored keyword would let every typo below through
# to be silently dropped at apply time.
class TestCustomBuildingSpecConstructionsValidation < Minitest::Test
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

  def validate(spec)
    OpenstudioStandards::CreateTypical.validate_custom_building_spec(JSON.parse(JSON.generate(spec), symbolize_names: true))
  end

  def test_valid_construction_specs_pass
    bare = base_spec.merge('constructions' => {
                             'building_category' => 'Nonresidential',
                             'is_residential' => false,
                             'exterior_wall_type' => 'Mass',
                             'exterior_roof_type' => 'IEAD',
                             'surfaces' => {
                               'ground_contact_floor' => { 'construction_type' => 'Unheated' },
                               'interior_walls' => 'Typical Interior Wall',
                               'interior_partitions' => { 'construction' => 'Typical Interior Partition' }
                             }
                           })
    assert_empty(validate(bare), 'a bare construction spec should pass')

    partial = base_spec.merge('constructions' => { 'exterior_wall_type' => 'SteelFramed' })
    assert_empty(validate(partial), 'a spec naming one surface should pass')

    collection = base_spec.merge('constructions' => {
                                   'default' => { 'building_category' => 'Nonresidential', 'exterior_wall_type' => 'Mass' },
                                   'sets' => [
                                     { 'name' => 'residential tower',
                                       'space_types' => ['apartment', 'guest room'],
                                       'is_residential' => true,
                                       'exterior_wall_type' => 'SteelFramed' }
                                   ]
                                 })
    assert_empty(validate(collection), 'a default-plus-sets collection should pass')
  end

  def test_invalid_construction_specs_fail
    {
      'unknown surface' => { 'surfaces' => { 'exterior_parapet' => 'x' } },
      'slots is not a constructions key' => { 'slots' => { 'interior_walls' => 'Typical Interior Wall' } },
      'misspelled field' => { 'wall_type' => 'Mass' },
      'construction type not in the enum' => { 'exterior_wall_type' => 'Steel Framed' },
      'roof type on a wall' => { 'exterior_wall_type' => 'IEAD' },
      'is_residential as a string' => { 'is_residential' => 'yes' },
      'unknown category' => { 'building_category' => 'Commercial' },
      'door type in a window surface' => { 'surfaces' => { 'exterior_fixed_window' => { 'construction_type' => 'Swinging' } } },
      'surface pinning a construction and naming a type' => { 'surfaces' => { 'exterior_wall' => { 'construction' => 'X', 'construction_type' => 'Mass' } } },
      'set entry without a selector' => { 'sets' => [{ 'name' => 'orphan', 'exterior_wall_type' => 'Mass' }] },
      'empty sets' => { 'sets' => [] }
    }.each do |label, constructions|
      errors = validate(base_spec.merge('constructions' => constructions))
      refute_empty(errors, "'#{label}' should fail runtime validation")
    end
  end

  # the closest-branch rule: a typo inside a construction spec reports as itself, not as a
  # generic mismatch against the collection form
  def test_errors_name_the_intended_form
    errors = validate(base_spec.merge('constructions' => { 'surfaces' => { 'exterior_parapet' => 'x' } }))
    assert(errors.any? { |e| e.include?('exterior_parapet') },
           "expected the unknown surface to be named in: #{errors}")
  end

  # a construction pinned on an assembly-lookup surface is a valid spec
  def test_pinned_construction_validates
    pinned = base_spec.merge('constructions' => {
                               'surfaces' => { 'exterior_roof' => { 'construction' => 'Typical Built Up Roof' } }
                             })
    assert_empty(validate(pinned), 'a pinned construction on an exterior surface should validate')
  end
end
