Gem::Specification.new do |spec|
  spec.name = 'openstudio-audit'
  spec.version = '0.1.0'
  spec.authors = ['NRCan / openstudio-standards contributors']
  spec.summary = 'Shared audit log + article-coverage emitter for the NECB gem family'
  spec.description = 'The one AuditLog class (entry schema, building stamping, article/ruling ' \
                     'citation axes, JSON + narrative rendering) and the one article-coverage ' \
                     'emitter shared by openstudio-hvac, -envelope, -loads, -lighting, -shw, ' \
                     '-geometry and the openstudio-necb umbrella. No domain knowledge, no ' \
                     'OpenStudio dependency — each family gem aliases the class into its own ' \
                     'namespace so existing call sites keep working.'
  spec.homepage = 'https://github.com/NREL/openstudio-standards'
  spec.license = 'LGPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir['lib/**/*', 'README.md', 'LICENSE*']
  spec.require_paths = ['lib']
end
