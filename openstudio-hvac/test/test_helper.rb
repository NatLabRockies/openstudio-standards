require 'minitest/autorun'
require_relative '../lib/openstudio_hvac'

module FixtureHelper
  FIXTURE = File.expand_path('fixtures/5ZoneNoHVAC.osm', __dir__)

  # A 5-zone model with thermostats and NO standardsSpaceType tags and NO HVAC —
  # proving the gem needs neither standards metadata nor pre-existing systems.
  def load_fixture
    OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
  end
end
