require_relative '../helpers/minitest_helper'

# Tests for the on-demand loading of standards data tables
class TestLazyStandardsData < Minitest::Test
  STANDARDS_DIR = File.expand_path('../../lib/openstudio-standards/standards', __dir__)

  # Directories that supply the ComStock 90.1-2013 data, most generic first
  COMSTOCK_2013_DIRS = [
    "#{STANDARDS_DIR}/ashrae_90_1",
    "#{STANDARDS_DIR}/ashrae_90_1/ashrae_90_1_2013",
    "#{STANDARDS_DIR}/ashrae_90_1/ashrae_90_1_2013/comstock_ashrae_90_1_2013"
  ].freeze

  # Loads every table from a list of directories up front, the way the
  # library did before tables were parsed on demand
  def eager_load(template, data_directories)
    data = {}
    data_directories.each do |data_dir|
      Dir.glob("#{data_dir}/data/*.json").sort.each do |file|
        JSON.parse(File.read(file)).each_pair do |key, objs|
          objs.each { |obj| obj['template'] = template if obj.key?('template') }
          data[key] = objs
        end
      end
    end
    data
  end

  def test_build_does_not_parse_any_table
    std = Standard.build('90.1-2013')
    data = std.standards_data
    assert_kind_of Standard::LazyStandardsData, data
    assert_empty data.loaded_tables
    refute_empty data.keys
    assert data.key?('space_types')
    assert data.include?('boilers')
    refute data.empty?
  end

  def test_table_is_parsed_on_first_access_and_reused
    std = Standard.build('90.1-2013')
    data = std.standards_data
    space_types = data['space_types']
    assert_kind_of Array, space_types
    refute_empty space_types
    assert_equal ['space_types'], data.loaded_tables
    assert_same space_types, data['space_types']
    assert data.loaded?('space_types')
    refute data.loaded?('boilers')
  end

  def test_lazy_tables_match_eager_load
    std = Standard.build('ComStock 90.1-2013')
    eager = eager_load('ComStock 90.1-2013', COMSTOCK_2013_DIRS)
    lazy = std.standards_data
    assert_equal eager.keys.sort, lazy.keys.sort
    eager.each_pair do |table_name, objs|
      assert(objs == lazy[table_name], "table '#{table_name}' differs from the eagerly loaded table")
    end
    assert_equal eager.keys.sort, lazy.loaded_tables.sort
  end

  def test_most_specific_directory_supplies_the_table
    data = Standard.build('ComStock 90.1-2013').standards_data
    assert_equal COMSTOCK_2013_DIRS[2], File.dirname(File.dirname(data.file_for('space_types')))
    assert_equal COMSTOCK_2013_DIRS[1], File.dirname(File.dirname(data.file_for('boilers')))
    assert_equal COMSTOCK_2013_DIRS[0], File.dirname(File.dirname(data.file_for('schedules')))
  end

  def test_template_is_written_into_inherited_tables
    data = Standard.build('ComStock 90.1-2013').standards_data
    # construction_sets is inherited from the 90.1-2013 directory and stamped with the parent's template on disk
    templates = data['construction_sets'].select { |obj| obj.key?('template') }.map { |obj| obj['template'] }.uniq
    assert_equal ['ComStock 90.1-2013'], templates
  end

  def test_unknown_table_is_absent
    std = Standard.build('90.1-2013')
    data = std.standards_data
    assert_nil data['no_such_table']
    refute data.key?('no_such_table')
    assert_equal 'fallback', data.fetch('no_such_table', 'fallback')
    assert_raises(KeyError) { data.fetch('no_such_table') }
    assert_empty std.standards_lookup_table_many(table_name: 'no_such_table')
  end

  def test_tables_can_be_stored_directly
    data = Standard.build('90.1-2013').standards_data
    user_buildings = [{ 'name' => 'Building 1', 'building_type_for_wwr' => 'Office' }]
    data['userdata_building'] = user_buildings
    assert data.key?('userdata_building')
    assert_includes data.keys, 'userdata_building'
    assert_same user_buildings, data['userdata_building']
    assert_nil data.file_for('userdata_building')
  end

  def test_lookup_methods_read_lazy_tables
    std = Standard.build('90.1-2013')
    boilers = std.standards_lookup_table_many(table_name: 'boilers')
    refute_empty boilers
    assert_equal boilers.size, std.model_find_objects(std.standards_data['boilers'], {}).size
  end

  def test_hash_style_iteration_loads_every_table
    data = Standard.build('90.1-2013').standards_data
    as_hash = data.to_h
    assert_kind_of Hash, as_hash
    assert_equal data.keys.sort, as_hash.keys.sort
    assert_equal data.keys.sort, data.loaded_tables.sort
    assert_equal data.size, data.each_pair.count
  end

  # Every data file read by Standard#load_standards_database must hold exactly
  # the table its file name promises, otherwise the table could not be found
  # on demand. NECB data is loaded by its own code and has a different layout.
  def test_every_data_file_holds_the_table_named_by_its_file_name
    files = Dir.glob("#{STANDARDS_DIR}/**/data/*.json").reject { |file| file.include?('/necb/') }
    assert_operator files.size, :>, 100, 'expected to find the data files of every non-NECB standard'

    problems = []
    files.each do |file|
      table_name = Standard::LazyStandardsData.table_name_for(file)
      keys = JSON.parse(File.read(file)).keys
      problems << "#{file} holds #{keys.inspect} but its name promises '#{table_name}'" unless keys == [table_name]
    end
    assert_empty problems, problems.join("\n")
  end
end
