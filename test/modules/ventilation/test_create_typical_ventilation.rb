require_relative '../../helpers/minitest_helper'

class TestVentilationCreateTypical < Minitest::Test
  def setup
    @vent = OpenstudioStandards::Ventilation
  end

  # a model whose space types carry the all-level vocabulary, which is what resolves the
  # ventilation_space_type additional property the lookup keys off
  def model_with(*space_type_names)
    model = OpenStudio::Model::Model.new
    space_type_names.each do |name|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName(name)
      space_type.setStandardsSpaceType(name)
    end
    OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(model)
    model
  end

  def space_type(model, name)
    model.getSpaceTypes.find { |st| st.name.get == name }
  end

  def cfm_per_person(dsoa)
    OpenStudio.convert(dsoa.outdoorAirFlowperPerson, 'm^3/s*person', 'ft^3/min*person').get
  end

  def cfm_per_area(dsoa)
    OpenStudio.convert(dsoa.outdoorAirFlowperFloorArea, 'm^3/s*m^2', 'ft^3/min*ft^2').get
  end

  def test_create_typical_ventilation
    model = model_with('office', 'classroom/lecture/training', 'patient room')
    # added after the properties are resolved, so it carries no ventilation_space_type at all
    outside_vocabulary = OpenStudio::Model::SpaceType.new(model)
    outside_vocabulary.setName('no ventilation property')

    result = @vent.create_typical_ventilation(model)
    assert_equal(3, result.size)

    # office: ASHRAE 62.1 office space rates
    dsoa = space_type(model, 'office').designSpecificationOutdoorAir.get
    assert_equal('Sum', dsoa.outdoorAirMethod)
    assert_in_delta(5.0, cfm_per_person(dsoa), 0.001)
    assert_in_delta(0.06, cfm_per_area(dsoa), 0.0001)
    assert_in_delta(0.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
    assert_equal('office_ventilation', dsoa.additionalProperties.getFeatureAsString('ventilation_source').get)

    # classroom: 10 cfm/person + 0.12 cfm/ft^2
    dsoa = space_type(model, 'classroom/lecture/training').designSpecificationOutdoorAir.get
    assert_in_delta(10.0, cfm_per_person(dsoa), 0.001)
    assert_in_delta(0.12, cfm_per_area(dsoa), 0.0001)

    # patient room: the curated ASHRAE 170 air-change rate, not a 62.1 Table 6-1 row
    dsoa = space_type(model, 'patient room').designSpecificationOutdoorAir.get
    assert_in_delta(0.0, cfm_per_person(dsoa), 0.0001)
    assert_in_delta(2.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
    assert_equal('curated | ASHRAE 170-2021', dsoa.additionalProperties.getFeatureAsString('ventilation_standard').get)

    # a space type with no ventilation space type is skipped
    assert_equal(false, outside_vocabulary.designSpecificationOutdoorAir.is_initialized)
  end

  def test_create_typical_ventilation_overwrites_existing
    model = model_with('office')
    office = space_type(model, 'office')
    existing = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
    existing.setOutdoorAirFlowAirChangesperHour(9.0)
    office.setDesignSpecificationOutdoorAir(existing)

    @vent.create_typical_ventilation(model)
    dsoa = office.designSpecificationOutdoorAir.get
    assert_in_delta(0.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001, 'stale ACH value should be overwritten')
    assert_in_delta(5.0, cfm_per_person(dsoa), 0.001)
  end

  # The template string and the ventilation space type are the whole lookup: no standards space
  # type mapping is consulted, so a space type the standards vocabulary has no equivalent for
  # still gets rates.
  def test_create_typical_ventilation_from_template
    model = model_with('office', 'patient room', 'banking', 'laboratory')

    result = @vent.create_typical_ventilation(model, template: '90.1-2013')
    assert_equal(4, result.size)

    dsoa = space_type(model, 'office').designSpecificationOutdoorAir.get
    assert_in_delta(5.0, cfm_per_person(dsoa), 0.001)
    assert_in_delta(0.06, cfm_per_area(dsoa), 0.0001)
    assert_equal('ASHRAE 62.1 | Office Buildings | Office space',
                 dsoa.additionalProperties.getFeatureAsString('ventilation_standard').get)

    dsoa = space_type(model, 'patient room').designSpecificationOutdoorAir.get
    assert_in_delta(2.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
    assert_in_delta(0.0, cfm_per_person(dsoa), 0.0001)

    # banking has no standards space type equivalent and still resolves, from 62.1
    dsoa = space_type(model, 'banking').designSpecificationOutdoorAir.get
    assert_in_delta(7.5, cfm_per_person(dsoa), 0.001)
    assert_equal('banking_ventilation', dsoa.additionalProperties.getFeatureAsString('ventilation_source').get)

    # laboratory reached a standards row with no ventilation of any kind on the old lookup, and
    # so was silently given zero outdoor air
    dsoa = space_type(model, 'laboratory').designSpecificationOutdoorAir.get
    assert_in_delta(10.0, cfm_per_person(dsoa), 0.001, 'laboratory must not resolve to zero ventilation')
    assert_in_delta(0.18, cfm_per_area(dsoa), 0.0001)
  end

  def test_create_typical_ventilation_from_deer_template
    model = model_with('office', 'patient room')
    result = @vent.create_typical_ventilation(model, template: 'ComStock DEER 2014')
    assert_equal(2, result.size)

    # DEER takes the greatest of the rates rather than summing them
    dsoa = space_type(model, 'office').designSpecificationOutdoorAir.get
    assert_equal('Maximum', dsoa.outdoorAirMethod)
    assert_in_delta(15.0, cfm_per_person(dsoa), 0.001)
    assert_in_delta(0.15, cfm_per_area(dsoa), 0.0001)
    assert_equal('spc_typ | OfL | OfficeOpen', dsoa.additionalProperties.getFeatureAsString('ventilation_standard').get)

    # the curated health care rates apply under every template, not just the 90.1 family
    dsoa = space_type(model, 'patient room').designSpecificationOutdoorAir.get
    assert_in_delta(2.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
  end

  # core and ComStock are separate template labels carrying their own values
  def test_core_and_comstock_deer_are_distinct
    core = model_with('office')
    @vent.create_typical_ventilation(core, template: 'DEER 2014')
    assert_in_delta(0.13, cfm_per_area(space_type(core, 'office').designSpecificationOutdoorAir.get), 0.0001)

    comstock = model_with('office')
    @vent.create_typical_ventilation(comstock, template: 'ComStock DEER 2014')
    assert_in_delta(0.15, cfm_per_area(space_type(comstock, 'office').designSpecificationOutdoorAir.get), 0.0001)
  end

  def test_template_entry
    entries = [
      { templates: ['90.1-2004', '90.1-2007'], value: 'a' },
      { templates: ['90.1-2013', 'ComStock 90.1-2013'], value: 'b' },
      { templates: ['90.1-2019'], value: 'c' },
      { templates: ['DEER 2011'], value: 'd' },
      { templates: ['DEER 2020'], value: 'e' },
      { templates: ['DOE Ref 1980-2004'], value: 'f' }
    ]
    # exact label, then the label with the ComStock prefix dropped
    assert_equal('b', @vent.template_entry(entries, '90.1-2013')[:value])
    assert_equal('b', @vent.template_entry(entries, 'ComStock 90.1-2013')[:value])
    assert_equal('a', @vent.template_entry(entries, 'ComStock 90.1-2007')[:value])
    # a year between entries takes the newest at or before it
    assert_equal('a', @vent.template_entry(entries, '90.1-2010')[:value])
    assert_equal('c', @vent.template_entry(entries, '90.1-2022')[:value])
    # older than every entry in the family takes the nearest after it
    assert_equal('a', @vent.template_entry(entries, '90.1-2001')[:value])
    # candidates narrow to the requested template's family
    assert_equal('e', @vent.template_entry(entries, 'ComStock DEER 2025')[:value])
    assert_equal('d', @vent.template_entry(entries, 'DEER 2014')[:value])
    assert_equal('f', @vent.template_entry(entries, 'DOE Ref Pre-1980')[:value])
    # nil or year-less templates take the newest 90.1 entry
    assert_equal('c', @vent.template_entry(entries, nil)[:value])
    assert_nil(@vent.template_entry([], '90.1-2013'))
    assert_nil(@vent.template_entry(nil, '90.1-2013'))
  end

  def test_ventilation_overrides
    # matched by ventilation space type, which is what the data is keyed by
    model = model_with('office', 'laboratory')
    @vent.create_typical_ventilation(
      model, template: '90.1-2013',
      ventilation_overrides: [{ space_type: 'laboratory_ventilation',
                                ventilation: { cfm_per_person: 0.0, cfm_per_area: 1.25, ach: 6.0 } }]
    )
    dsoa = space_type(model, 'laboratory').designSpecificationOutdoorAir.get
    assert_in_delta(0.0, cfm_per_person(dsoa), 0.0001)
    assert_in_delta(1.25, cfm_per_area(dsoa), 0.0001)
    assert_in_delta(6.0, dsoa.outdoorAirFlowAirChangesperHour, 0.0001)
    assert_includes(dsoa.additionalProperties.getFeatureAsString('ventilation_standard').get, 'override',
                    'the source should record that an override applied')
    # an unmatched space type keeps its data values
    assert_in_delta(5.0, cfm_per_person(space_type(model, 'office').designSpecificationOutdoorAir.get), 0.001)
  end

  def test_ventilation_overrides_match_standards_space_type_and_wildcard
    model = model_with('office', 'laboratory')
    @vent.create_typical_ventilation(
      model, template: '90.1-2013',
      ventilation_overrides: [{ space_type: '*', ventilation: { cfm_per_area: 0.99 } },
                              { space_type: 'office', ventilation: { cfm_per_area: 0.11 } }]
    )
    # a specific entry, here keyed by standards space type, wins over the wildcard
    assert_in_delta(0.11, cfm_per_area(space_type(model, 'office').designSpecificationOutdoorAir.get), 0.0001)
    assert_in_delta(0.99, cfm_per_area(space_type(model, 'laboratory').designSpecificationOutdoorAir.get), 0.0001)
    # fields the override does not name keep their data values
    assert_in_delta(10.0, cfm_per_person(space_type(model, 'laboratory').designSpecificationOutdoorAir.get), 0.001)
  end

  # Entries built by a measure naturally carry string keys; only CreateTypical.parse_overrides_
  # argument symbolizes them, so the matcher has to read either form or the entry matches and
  # its fields are then silently ignored.
  def test_ventilation_overrides_accept_string_keys
    model = model_with('office')
    @vent.create_typical_ventilation(
      model, template: '90.1-2013',
      ventilation_overrides: [{ 'space_type' => 'office_ventilation', 'ventilation' => { 'cfm_per_area' => 0.42 } }]
    )
    assert_in_delta(0.42, cfm_per_area(space_type(model, 'office').designSpecificationOutdoorAir.get), 0.0001)
  end

  # an override is the only way to give a space type ventilation the data does not cover
  def test_ventilation_override_applies_without_data
    model = model_with('office')
    office = space_type(model, 'office')
    office.additionalProperties.setFeature('ventilation_space_type', 'na')

    @vent.create_typical_ventilation(
      model, template: '90.1-2013',
      ventilation_overrides: [{ space_type: 'office', ventilation: { cfm_per_area: 0.25 } }]
    )
    dsoa = office.designSpecificationOutdoorAir
    assert(dsoa.is_initialized, 'an override should apply even where the lookup found nothing')
    assert_in_delta(0.25, cfm_per_area(dsoa.get), 0.0001)
  end

  def test_every_all_level_ventilation_space_type_has_data
    all_level_path = File.expand_path('../../../lib/openstudio-standards/space_type/data/all_level_space_types.json', __dir__)
    data_path = File.expand_path('../../../lib/openstudio-standards/ventilation/data/ventilation_space_type_data.json', __dir__)
    names = JSON.parse(File.read(all_level_path)).map { |r| r['ventilation_space_type_name'] }.compact.uniq - ['na']
    data = JSON.parse(File.read(data_path))
    missing = names - data.keys
    assert_empty(missing, "all-level ventilation space types missing from the ventilation data: #{missing}")
    empty = names.select { |n| data[n].empty? }
    assert_empty(empty, "ventilation space types with no entries: #{empty}")
  end

  # An entry carrying no rate at all describes nothing, but create_typical_ventilation cannot
  # tell it apart from a real one: the entry is found, so no warning is logged and no fallback
  # runs, and nil.to_f turns every rate into 0.0. A ComStock DOE Ref hospital lost all of its
  # laboratory ventilation this way. The generator now refuses to emit such an entry, and the
  # spaces that genuinely get no outdoor air - attics, plenums, shafts - say so with an
  # explicit 0.0 rather than a nil, so nil in this data always means "no data".
  def test_no_ventilation_entry_is_entirely_without_rates
    data_path = File.expand_path('../../../lib/openstudio-standards/ventilation/data/ventilation_space_type_data.json', __dir__)
    data = JSON.parse(File.read(data_path))
    fields = %w[ventilation_per_person ventilation_per_area ventilation_air_changes]

    rateless = data.flat_map do |name, entries|
      entries.select { |entry| fields.all? { |field| entry[field].nil? } }
             .map { |entry| "#{name} (#{entry['source']}) covering #{entry['templates'].first}" }
    end
    assert_empty(rateless, "ventilation entries with no rate on any field, which resolve to zero ventilation: #{rateless}")
  end

  # The laboratory rates the ComStock DOE Ref hospital regression was found through. The
  # generic laboratory takes the hospital lab row, which is the only host ComStock gives the
  # space type; the educational sub-space type keeps the college row.
  def test_laboratory_ventilation_rates_are_not_zero
    ['ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004', 'ComStock 90.1-2013', 'ComStock DEER 2014'].each do |template|
      %w[laboratory_ventilation educational_facilities_science_laboratories_ventilation].each do |name|
        entries = JSON.parse(File.read(File.expand_path('../../../lib/openstudio-standards/ventilation/data/ventilation_space_type_data.json', __dir__)),
                             symbolize_names: true)[name.to_sym]
        entry = @vent.template_entry(entries, template)
        refute_nil(entry, "no #{name} entry for #{template}")
        rates = [entry[:ventilation_per_person].to_f, entry[:ventilation_per_area].to_f, entry[:ventilation_air_changes].to_f]
        assert(rates.any?(&:positive?), "#{name} resolves to zero ventilation for #{template}: #{rates}")
      end
    end
  end

  def test_ventilation_data_covers_the_templates_it_claims
    data_path = File.expand_path('../../../lib/openstudio-standards/ventilation/data/ventilation_space_type_data.json', __dir__)
    data = JSON.parse(File.read(data_path))
    data.each do |name, entries|
      templates = entries.flat_map { |e| e['templates'] }
      assert_equal(templates.uniq.length, templates.length, "#{name} lists a template in more than one entry")
      entries.each do |entry|
        refute_empty(entry['templates'].to_s, "#{name} has an entry covering no template")
        refute_nil(entry['source'], "#{name} has an entry with no source")
      end
    end
  end
end
