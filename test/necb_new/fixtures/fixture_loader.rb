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
end
