require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/spec/'
  
  # Focus on NECB folder
  add_group "NECB Standards", "lib/openstudio-standards/standards/necb"
  add_group "ECMS", "lib/openstudio-standards/standards/necb/ECMS"
  
  track_files "lib/openstudio-standards/standards/necb/**/*.rb"
end

require 'minitest/autorun'

# Load all system test files using require_relative
Dir.glob(File.join(File.dirname(__FILE__), 'test_system_*.rb')).each do |f|
  require_relative File.basename(f, '.rb')
end
