require_relative '../../helpers/minitest_helper'

class TestExteriorLightingBuildingTypes < Minitest::Test
  DATA_DIR = File.expand_path('../../../lib/openstudio-standards/exterior_lighting/data', __dir__)

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
                 "building types with no parking.json row: #{missing.join(', ')}")
  end

  def test_entryway_data_covers_every_form_default_building_type
    missing = form_default_building_types - data_building_types('entryways.json', 'entryways')
    assert_empty(missing,
                 "building types with no entryways.json row: #{missing.join(', ')}")
  end

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

end
