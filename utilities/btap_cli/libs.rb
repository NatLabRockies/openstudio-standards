require 'minitest/autorun'
require 'openstudio'

require_relative '../../lib/openstudio-standards'

resource_folder = File.join(__dir__, '../../lib/openstudio-standards/btap/costing/')

puts('Loading Costing libs')
require_relative File.join(resource_folder, 'btap_measure_helper')
require_relative File.join(resource_folder, 'btap_costing.rb')
require_relative File.join(resource_folder, 'ventilation_costing.rb')
require_relative File.join(resource_folder, 'envelope_costing.rb')
require_relative File.join(resource_folder, 'lighting_costing.rb')
require_relative File.join(resource_folder, 'heating_cooling_costing.rb')
require_relative File.join(resource_folder, 'shw_costing.rb')
require_relative File.join(resource_folder, 'dcv_costing.rb')
require_relative File.join(resource_folder, 'daylighting_sensor_control_costing.rb')
require_relative File.join(resource_folder, 'led_lighting_costing.rb')
require_relative File.join(resource_folder, 'pv_ground_costing.rb')
require_relative File.join(resource_folder, 'nv_costing.rb')
