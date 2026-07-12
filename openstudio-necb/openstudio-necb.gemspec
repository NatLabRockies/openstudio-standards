require_relative 'lib/openstudio_necb/version'

Gem::Specification.new do |spec|
  spec.name = 'openstudio-necb'
  spec.version = OpenStudioNECB::VERSION
  spec.authors = ['NRCan / openstudio-standards contributors']
  spec.summary = 'NECB performance-path compliance pipeline composing openstudio-hvac and openstudio-envelope'
  spec.description = 'Umbrella gem: proposed -> reference building generation (HVAC + envelope, one ' \
                     'clone, one audit), SDK+CLI sizing/annual simulation, NECB 8.4.1.2 building-energy-target ' \
                     'comparison, and unified compliance + costing reporting.'
  spec.homepage = 'https://github.com/NREL/openstudio-standards'
  spec.license = 'LGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'openstudio-envelope'
  spec.add_dependency 'openstudio-hvac'
end
