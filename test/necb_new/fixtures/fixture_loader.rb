# Fixture Loader Helper for Integration Tests
#
# This module provides methods to load pre-sized fixture models for integration tests.
# Fixtures are generated once using generate_integration_fixtures.rb and then loaded
# instantly in tests, avoiding the need for repeated EnergyPlus sizing runs.
#
# Usage:
#   include FixtureLoader
#   model = load_sized_fixture('system_4_hw_toronto')
#
# Fixture files are located in test/necb_new/fixtures/sized_models/

module FixtureLoader
  FIXTURE_DIR = File.expand_path('../sized_models', __FILE__)

  # Load a pre-sized fixture model
  #
  # @param fixture_name [String] Name of the fixture (without .osm extension)
  # @return [OpenStudio::Model::Model] The loaded model
  # @raise [RuntimeError] If fixture file doesn't exist
  def load_sized_fixture(fixture_name)
    fixture_path = File.join(FIXTURE_DIR, "#{fixture_name}.osm")

    unless File.exist?(fixture_path)
      raise "Fixture '#{fixture_name}' not found at #{fixture_path}. " \
            "Run 'bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb' to generate fixtures."
    end

    # Load the OSM file
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(fixture_path)

    if model.empty?
      raise "Failed to load fixture '#{fixture_name}' from #{fixture_path}"
    end

    model.get
  end

  # Check if a fixture exists
  #
  # @param fixture_name [String] Name of the fixture (without .osm extension)
  # @return [Boolean] True if fixture file exists
  def fixture_exists?(fixture_name)
    fixture_path = File.join(FIXTURE_DIR, "#{fixture_name}.osm")
    File.exist?(fixture_path)
  end

  # Get list of available fixtures
  #
  # @return [Array<String>] List of fixture names (without .osm extension)
  def available_fixtures
    return [] unless Dir.exist?(FIXTURE_DIR)

    Dir.glob(File.join(FIXTURE_DIR, '*.osm')).map do |path|
      File.basename(path, '.osm')
    end.sort
  end

  # Create a simple test model with minimal geometry for testing
  # Use this when you need to test a configuration not covered by pre-sized fixtures
  #
  # @param length [Float] Building length in meters (default: 20.0)
  # @param width [Float] Building width in meters (default: 15.0)
  # @param floors [Integer] Number of above-ground floors (default: 1)
  # @param height [Float] Floor-to-floor height in meters (default: 3.0)
  # @return [OpenStudio::Model::Model] The created model
  def create_simple_box(length: 20.0, width: 15.0, floors: 1, height: 3.0)
    model = OpenStudio::Model::Model.new

    OpenstudioStandards::Geometry.create_shape_rectangle(
      model,
      length,           # length
      width,            # width
      floors,           # above_ground_storys
      0,                # under_ground_storys
      height,           # floor_to_floor_height
      0.0,              # plenum_height
      4.57,             # perimeter_zone_depth
      0.0               # initial_height
    )

    # Set weather file (Toronto as default)
    epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path('CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)

    # Apply basic space types to avoid warnings
    standard = Standard.build('NECB2011')
    model.getSpaces.each do |space|
      space_function = space.name.get.include?('Core') ? 'Office - open plan' : 'Office - enclosed'
      space_type = standard.model_add_space_type(model, 'Office', space_function)
      space.setSpaceType(space_type)
    end

    model
  end
end
