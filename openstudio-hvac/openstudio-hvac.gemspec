require_relative 'lib/openstudio_hvac/version'

Gem::Specification.new do |spec|
  spec.name          = 'openstudio-hvac'
  spec.version       = OpenStudioHVAC::VERSION
  spec.authors       = ['Phylroy Lopez']
  spec.email         = ['phylroy.lopez@gmail.com']

  spec.summary       = 'Build HVAC system topologies on OpenStudio thermal zones by descriptive name.'
  spec.description   = 'A standards-agnostic library that applies complete HVAC system ' \
                       'topologies (packaged single-zone, VAV reheat, fan coils, MAU+PTAC, ' \
                       'baseboards and their plant loops) to a set of OpenStudio thermal zones ' \
                       'using descriptive, fuel-encoding system names. Topology only: sizing ' \
                       'runs and code efficiency application are left to the host application ' \
                       '(e.g. openstudio-standards).'
  spec.homepage      = 'https://github.com/NatLabRockies/openstudio-standards'
  spec.license       = 'BSD-3-Clause'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files         = Dir['lib/**/*', 'README.md', 'LICENSE*']
  spec.require_paths = ['lib']

  # The OpenStudio SDK ruby bindings are the ONLY runtime dependency. They are typically
  # provided by an OpenStudio installation rather than rubygems, so they are not declared
  # as a gem dependency here; `require 'openstudio'` must succeed in the host environment.

  # openstudio-audit: the shared AuditLog + article-coverage emitter.
  spec.add_dependency 'openstudio-audit'

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 13.0'
end
