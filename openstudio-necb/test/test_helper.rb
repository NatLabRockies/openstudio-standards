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
    model = OpenStudio::Model::Model.load(OpenStudio::Path.new(FIXTURE)).get
    # The shared fixture is ASHRAE-tagged with no standardsSpaceType, which the
    # performance-path pre-flight now (correctly) rejects: unresolvable space
    # types silently keep the proposed's lighting/loads in the reference. Tag
    # the one space type the five floor-area spaces use with a real NECB
    # catalog name — 'Office - enclosed' and friends are NOT catalog names
    # (the catalog has 'Office enclosed > 25 m2' / '<= 25 m2').
    model.getSpaceTypes.select { |st| st.spaces.any? }.each do |st|
      st.setStandardsBuildingType('Space Function')
      st.setStandardsSpaceType('Office enclosed > 25 m2')
    end
    model
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
