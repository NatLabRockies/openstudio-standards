require_relative '../../helpers/minitest_helper'

# The exterior lighting data is keyed on the standards building type stamped on the Building,
# and create_typical stamps the UNcollapsed primary_building_type there -- not the
# model_get_lookup_name collapsed form the rest of the standards data uses. A building type
# whose name is missing from parking.json or entryways.json gets no parking lighting and no
# entryway lighting at all, silently, behind a single Info-level log line.
#
# That is how every ComStock RetailStandalone and RetailStripmall came to have exactly zero
# exterior lighting: the data knows them as Retail and StripMall.
class TestExteriorLightingBuildingTypes < Minitest::Test
  DATA_DIR = File.expand_path('../../../lib/openstudio-standards/exterior_lighting/data', __dir__)

  # Building types create_typical can be given as primary_building_type. Anything
  # building_form_defaults recognizes can reach the exterior lighting lookups.
  def form_default_building_types
    source = File.read(File.expand_path('../../../lib/openstudio-standards/geometry/create_bar.rb', __dir__))
    body = source[/def self\.building_form_defaults.*?\n    end\n/m]
    refute_nil(body, 'could not read building_form_defaults')
    body.scan(/hash\['([^']+)'\]/).flatten.uniq
  end

  def data_building_types(file, key)
    JSON.parse(File.read(File.join(DATA_DIR, file)))[key].map { |row| row['building_type'] }
  end

  def test_parking_data_covers_every_form_default_building_type
    missing = form_default_building_types - data_building_types('parking.json', 'parking')
    assert_empty(missing,
                 "building types with no parking.json row, which silently get no exterior parking lighting: #{missing.join(', ')}")
  end

  def test_entryway_data_covers_every_form_default_building_type
    missing = form_default_building_types - data_building_types('entryways.json', 'entryways')
    assert_empty(missing,
                 "building types with no entryways.json row, which silently get no entryway lighting: #{missing.join(', ')}")
  end

  # The two names the bug was found on, pinned explicitly so a regeneration that drops them
  # fails here rather than in a stock run.
  def test_the_comstock_retail_names_are_present_and_match_their_counterparts
    parking = JSON.parse(File.read(File.join(DATA_DIR, 'parking.json')))['parking']
    entryways = JSON.parse(File.read(File.join(DATA_DIR, 'entryways.json')))['entryways']

    { 'RetailStandalone' => 'Retail', 'RetailStripmall' => 'StripMall' }.each do |comstock, standards|
      [[parking, 'building_area_per_spot'], [entryways, 'entrance_doors_per_10000_ft2']].each do |rows, field|
        new_row = rows.find { |r| r['building_type'] == comstock }
        old_row = rows.find { |r| r['building_type'] == standards }
        refute_nil(new_row, "#{comstock} is missing")
        refute_nil(old_row, "#{standards} is missing")
        assert_equal(old_row[field], new_row[field],
                     "#{comstock} should carry the same #{field} as #{standards}")
      end
    end
  end

  # The CSVs are the editable source; the JSONs are generated from them. They have to agree,
  # or an edit to the CSV silently does nothing.
  def test_the_csv_and_json_building_type_lists_agree
    require 'csv'
    { 'parking' => 'parking', 'entryways' => 'entryways' }.each do |base, key|
      csv = CSV.read(File.join(DATA_DIR, "#{base}.csv"), headers: true).map { |r| r['building_type'] }
      json = data_building_types("#{base}.json", key)
      assert_equal(csv, json, "#{base}.csv and #{base}.json list different building types")
    end
  end
end
