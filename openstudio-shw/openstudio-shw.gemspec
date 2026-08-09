require_relative 'lib/openstudio_shw/version'

Gem::Specification.new do |spec|
  spec.name = 'openstudio-shw'
  spec.version = OpenStudioSHW::VERSION
  spec.authors = ['NRCan / openstudio-standards contributors']
  spec.summary = 'NECB Part 6 service water heating for OpenStudio models (SDK-only)'
  spec.description = 'Applies NECB service water heating: per-space demand from space-type data, ' \
                     'legacy-parity auto-sized SHW plant, Table 6.2.2.1 water-heater performance ' \
                     '(NECB2020 UEF procedure), and the 8.4.4.20 reference treatment — with an ' \
                     'audit log and article-coverage accounting.'
  spec.homepage = 'https://github.com/NREL/openstudio-standards'
  spec.license = 'LGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE*']
  spec.require_paths = ['lib']

  # openstudio-hvac: the costing engine (Database/Ledger/Geometry) costing.rb
  # builds on — required at load time, not just in the monorepo.
  spec.add_dependency 'openstudio-audit'
  spec.add_dependency 'openstudio-hvac'
  spec.add_dependency 'openstudio-loads'
end
