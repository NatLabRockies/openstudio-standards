require_relative 'lib/openstudio_loads/version'

Gem::Specification.new do |spec|
  spec.name = 'openstudio-loads'
  spec.version = OpenStudioLoads::VERSION
  spec.authors = ['NRCan / openstudio-standards contributors']
  spec.summary = 'NECB space-use loads and schedules for OpenStudio models (SDK-only)'
  spec.description = 'Applies NECB space-type internal loads (people, plug/gas equipment), ' \
                     'ventilation outdoor air, modelling infiltration, NECB schedule sets and ' \
                     'thermostat set-points to OpenStudio models from vendored, article-tagged ' \
                     'NECB data (8.4.3.2) — with an audit log and article-coverage accounting. ' \
                     'Lighting (Part 4) and service water heating (Part 6) are deliberately ' \
                     'out of scope (sibling gems).'
  spec.homepage = 'https://github.com/NREL/openstudio-standards'
  spec.license = 'LGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'openstudio-audit'
end
