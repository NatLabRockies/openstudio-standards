require_relative 'lib/openstudio_geometry/version'

Gem::Specification.new do |spec|
  spec.name = 'openstudio-geometry'
  spec.version = OpenStudioGeometry::VERSION
  spec.authors = ['NRCan / openstudio-standards contributors']
  spec.summary = 'Parametric building geometry wizards for OpenStudio models (SDK-only)'
  spec.description = 'Footprint wizards (rectangle, aspect-ratio, courtyard, H, L, T, U) with ' \
                     'perimeter/core zoning, below-grade storeys and matched surfaces — the ' \
                     'authoring on-ramp for the openstudio-* NECB gem family.'
  spec.homepage = 'https://github.com/NREL/openstudio-standards'
  spec.license = 'LGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE*']
  spec.require_paths = ['lib']

  spec.add_dependency 'openstudio-audit'
end
