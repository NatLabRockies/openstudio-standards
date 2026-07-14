require 'minitest/autorun'
require 'fileutils'
require 'json'
require_relative '../lib/openstudio_simulation'

module FixtureHelper
  # Fixtures are shared with the sibling family gems (monorepo incubation) —
  # no extra copy of the bare fixture or the weather trio.
  HVAC_FIXTURES = File.expand_path('../../openstudio-hvac/test/fixtures', __dir__)
  FIXTURE = File.join(HVAC_FIXTURES, '5ZoneNoHVAC.osm')
  EPW = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
  DDY = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.ddy')

  def load_fixture
    OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
  end

  def openstudio_cli?
    OpenStudioSimulation::Runner.openstudio_cli?
  end
end
