require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/openstudio_necb'

module FixtureHelper
  # Fixtures are shared with the sibling domain gems (monorepo incubation) —
  # no third copy of the weather trio.
  HVAC_FIXTURES = File.expand_path('../../openstudio-hvac/test/fixtures', __dir__)
  FIXTURE = File.join(HVAC_FIXTURES, '5ZoneNoHVAC.osm')
  EPW = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
  DDY = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.ddy')
  STAT = File.join(HVAC_FIXTURES, 'weather/CAN_ON_Toronto.Intl.AP.716240_CWEC2020.stat')

  def load_fixture
    OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
  end

  # A proposed building: the fixture + a gem-built HVAC system.
  def proposed_with_hvac(system = 'Baseboard gas boiler')
    model = load_fixture
    zones = model.getThermalZones.sort_by(&:nameString)
    OpenStudioHVAC.build_system(model, system, zones)
    model
  end

  def zone_types_for(model)
    model.getThermalZones.to_h { |z| [z.nameString, 'Office - enclosed'] }
  end

  def openstudio_cli?
    OpenStudioNECB::Runner.openstudio_cli?
  end
end
