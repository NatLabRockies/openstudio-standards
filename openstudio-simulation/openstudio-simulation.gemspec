require_relative 'lib/openstudio_simulation/version'

Gem::Specification.new do |spec|
  spec.name = 'openstudio-simulation'
  spec.version = OpenStudioSimulation::VERSION
  spec.authors = ['NRCan / openstudio-standards contributors']
  spec.summary = 'Run EnergyPlus on an OpenStudio model and parse results — SDK+CLI, no compliance layer'
  spec.description = 'The lowest-level family gem: attach weather, run EnergyPlus (pluggable execution ' \
                     'backend — local `openstudio` CLI now, a documented remote/AWS seam for later), and ' \
                     'parse site energy / end-use / unmet-hours results from the SQL. Pure OpenStudio SDK; ' \
                     'no measures, no openstudio-standards, no NECB compliance.'
  spec.homepage = 'https://github.com/NREL/openstudio-standards'
  spec.license = 'LGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE*']
  spec.require_paths = ['lib']

  # The lowest-level gem: depends on nothing else in the family, only the
  # OpenStudio SDK (provided by the environment / openstudio.rb).
end
