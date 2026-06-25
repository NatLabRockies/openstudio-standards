#!/usr/bin/env ruby

# Generate pre-sized integration test fixtures
# Run once to create fixtures that integration tests can load
# Supports parallel execution to speed up generation

require 'bundler/setup'
require 'openstudio'
require 'openstudio-standards'
require 'fileutils'
require 'thread'
require 'optparse'

FIXTURE_DIR = File.join(__dir__, 'sized_models')
FileUtils.mkdir_p(FIXTURE_DIR)

# Parse command line options
options = {
  parallel: true,
  workers: 4,
  force: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: generate_integration_fixtures.rb [options]"

  opts.on("--parallel", "Run in parallel (default)") do
    options[:parallel] = true
  end

  opts.on("--sequential", "Run sequentially") do
    options[:parallel] = false
  end

  opts.on("--workers N", Integer, "Number of parallel workers (default: 4)") do |n|
    options[:workers] = n
  end

  opts.on("--force", "Regenerate existing fixtures") do
    options[:force] = true
  end

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

puts "Generating integration test fixtures with sizing..."
if options[:parallel]
  puts "Running in PARALLEL with #{options[:workers]} workers"
  puts "Estimated time: ~#{(45.0 / options[:workers]).round} minutes (vs 45 min sequential)"
else
  puts "Running SEQUENTIALLY"
  puts "Estimated time: ~45 minutes"
end
puts ""

# Define fixture configurations
fixtures = [
  # System 4 fixtures
  { name: 'system_4_hw_toronto', system: 4, heating: 'Hot Water', climate: 'Toronto', building: 'SmallOffice' },
  { name: 'system_4_electric_toronto', system: 4, heating: 'Electric', climate: 'Toronto', building: 'SmallOffice' },

  # System 5 fixtures
  { name: 'system_5_tpfc_toronto', system: 5, chiller: 'Scroll', climate: 'Toronto', building: 'SmallOffice' },

  # System 6 fixtures
  { name: 'system_6_vav_hw_toronto', system: 6, heating: 'Hot Water', chiller: 'Scroll', climate: 'Toronto', building: 'MediumOffice' },
  { name: 'system_6_vav_electric_toronto', system: 6, heating: 'Electric', chiller: 'Centrifugal', climate: 'Toronto', building: 'MediumOffice' },

  # Full system fixtures for other system types
  { name: 'system_1_toronto', system: 1, climate: 'Toronto', building: 'SmallOffice' },
  { name: 'system_2_toronto', system: 2, heating: 'Electric', climate: 'Toronto', building: 'MediumOffice' },
  { name: 'system_3_toronto', system: 3, heating: 'Gas', climate: 'Toronto', building: 'SmallOffice' },

  # Multi-climate fixtures
  { name: 'system_1_vancouver', system: 1, climate: 'Vancouver', building: 'SmallOffice' },
  { name: 'system_1_edmonton', system: 1, climate: 'Edmonton', building: 'SmallOffice' },
  { name: 'system_1_yellowknife', system: 1, climate: 'Yellowknife', building: 'SmallOffice' }
]

# Climate zone to weather file mapping
WEATHER_FILES = {
  'Toronto'     => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
  'Vancouver'   => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
  'Edmonton'    => 'CAN_AB_Edmonton.Intl.AP.711230_CWEC2020.epw',
  'Yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
}

# Building geometry configurations
BUILDING_CONFIGS = {
  'SmallOffice'  => { length: 20.0, width: 15.0, floors: 1, height: 3.0 },
  'MediumOffice' => { length: 40.0, width: 30.0, floors: 2, height: 3.8 }
}

def create_base_model(building_type)
  model = OpenStudio::Model::Model.new
  config = BUILDING_CONFIGS[building_type]

  OpenstudioStandards::Geometry.create_shape_rectangle(
    model,
    config[:length],           # length
    config[:width],            # width
    config[:floors],           # above_ground_storys
    0,                         # under_ground_storys
    config[:height],           # floor_to_floor_height
    0.0,                       # plenum_height
    4.57,                      # perimeter_zone_depth
    0.0                        # initial_height
  )

  model
end

def apply_loads(model, standard, building_type)
  # Create office space types
  open_office_type = OpenStudio::Model::SpaceType.new(model)
  open_office_type.setStandardsBuildingType('Space Function')
  open_office_type.setStandardsSpaceType('Office - open plan')
  open_office_type.setName('Office - open plan')
  standard.space_type_apply_internal_loads(space_type: open_office_type)

  enclosed_office_type = OpenStudio::Model::SpaceType.new(model)
  enclosed_office_type.setStandardsBuildingType('Space Function')
  enclosed_office_type.setStandardsSpaceType('Office - enclosed')
  enclosed_office_type.setName('Office - enclosed')
  standard.space_type_apply_internal_loads(space_type: enclosed_office_type)

  # Apply space types to spaces
  model.getSpaces.each do |space|
    if space.name.get.include?('Core')
      space.setSpaceType(open_office_type)
    else
      space.setSpaceType(enclosed_office_type)
    end
  end
end

def add_weather(model, climate)
  epw_file = WEATHER_FILES[climate]
  epw_path = File.join(Dir.pwd, 'data', 'weather', epw_file)

  if File.exist?(epw_path)
    epw = OpenStudio::EpwFile.new(epw_path)
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw)
    true
  else
    puts "    Warning: Weather file not found: #{epw_path}"
    false
  end
end

def add_hvac_system(model, standard, config)
  zones = model.getThermalZones.sort

  case config[:system]
  when 1
    standard.add_sys1_unitary_ac_baseboard_heating(
      model: model,
      zones: zones,
      mau_type: true,
      mau_heating_coil_type: 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: nil
    )
  when 2
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: 'Scroll',
      fan_coil_type: 'FourPipe',
      mau_cooling_type: 'Hydronic',
      hw_loop: nil
    )
  when 3
    standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: config[:heating] || 'Hot Water',
      baseboard_type: 'Hot Water',
      hw_loop: nil
    )
  when 4
    standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: config[:heating] || 'Hot Water',
      baseboard_type: config[:heating] || 'Hot Water',
      hw_loop: nil
    )
  when 5
    standard.add_sys2_FPFC_sys5_TPFC(
      model: model,
      zones: zones,
      chiller_type: config[:chiller] || 'Scroll',
      fan_coil_type: 'TwoPipe',
      mau_cooling_type: 'Hydronic',
      hw_loop: nil
    )
  when 6
    standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
      model: model,
      zones: zones,
      heating_coil_type: config[:heating] || 'Hot Water',
      baseboard_type: config[:heating] || 'Hot Water',
      chiller_type: config[:chiller] || 'Scroll',
      fan_type: 'AF_or_BI_rdg_fancurve',
      hw_loop: nil
    )
  end
end

# Generate fixture (thread-safe)
def generate_fixture(config, idx, total, force)
  fixture_path = File.join(FIXTURE_DIR, "#{config[:name]}.osm")

  # Skip if exists and not forcing
  if File.exist?(fixture_path) && !force
    size_mb = (File.size(fixture_path) / 1024.0 / 1024.0).round(2)
    puts "[#{idx}/#{total}] Skipping #{config[:name]} (already exists, #{size_mb} MB)"
    return { name: config[:name], status: :skipped, size_mb: size_mb }
  end

  puts "[#{idx}/#{total}] → Starting #{config[:name]}..."

  begin
    standard = Standard.build('NECB2011')

    # Create model
    model = create_base_model(config[:building])

    # Add loads
    apply_loads(model, standard, config[:building])

    # Add weather
    weather_ok = add_weather(model, config[:climate])
    unless weather_ok
      return { name: config[:name], status: :failed, error: 'Weather file not found' }
    end

    # Add HVAC system
    add_hvac_system(model, standard, config)

    # Run sizing
    run_dir = File.join(Dir.pwd, 'output', 'fixture_generation', config[:name])
    FileUtils.mkdir_p(run_dir)

    success = standard.model_run_sizing_run(model, run_dir)

    if success
      # Save sized model
      model.save(fixture_path, true)
      size_mb = (File.size(fixture_path) / 1024.0 / 1024.0).round(2)
      puts "[#{idx}/#{total}] Completed #{config[:name]} (#{size_mb} MB)"
      { name: config[:name], status: :success, size_mb: size_mb }
    else
      puts "[#{idx}/#{total}] Sizing failed: #{config[:name]}"
      { name: config[:name], status: :failed, error: 'Sizing failed' }
    end

  rescue => e
    puts "[#{idx}/#{total}] Error in #{config[:name]}: #{e.message}"
    puts "    #{e.backtrace.first}" if ENV['DEBUG']
    { name: config[:name], status: :error, error: e.full_message }
  end
end

start_time = Time.now

# Generate fixtures
results = if options[:parallel]
  # Parallel execution with thread pool

  # Create work queue
  queue = Queue.new
  fixtures.each_with_index { |config, idx| queue << [config, idx + 1, fixtures.size] }

  # Create result storage
  results = []
  results_mutex = Mutex.new

  # Create worker threads
  workers = (1..options[:workers]).map do |worker_id|
    Thread.new do
      while !queue.empty?
        begin
          config, idx, total = queue.pop(true)
          result = generate_fixture(config, idx, total, options[:force])
          results_mutex.synchronize { results << result }
        rescue ThreadError
          # Queue is empty, thread can exit
          break
        end
      end
    end
  end

  # Wait for all workers to complete
  workers.each(&:join)

  results
else
  # Sequential execution
  fixtures.each_with_index.map do |config, idx|
    generate_fixture(config, idx + 1, fixtures.size, options[:force])
  end
end

elapsed_time = Time.now - start_time
elapsed_min = (elapsed_time / 60.0).round(1)

# Print summary
puts ""
puts "="*80
puts "Fixture generation complete!"
puts "="*80
puts "Time elapsed: #{elapsed_min} minutes"
puts "Location: #{FIXTURE_DIR}"
puts ""

# Summarize results
success_count = results.count { |r| r[:status] == :success }
failed_count = results.count { |r| r[:status] == :failed }
error_count = results.count { |r| r[:status] == :error }
skipped_count = results.count { |r| r[:status] == :skipped }

puts "Results:"
puts "  Success: #{success_count}"
puts "  Skipped: #{skipped_count}" if skipped_count > 0
puts "  Failed:  #{failed_count}" if failed_count > 0
puts "  Errors:  #{error_count}" if error_count > 0
puts ""

if failed_count > 0 || error_count > 0
  puts "Failed/Error fixtures:"
  results.select { |r| r[:status] == :failed || r[:status] == :error }.each do |r|
    puts "  - #{r[:name]}: #{r[:error]}"
  end
  puts ""
end

total_size_mb = results.select { |r| r[:size_mb] }.sum { |r| r[:size_mb] }
puts "Total fixture size: #{total_size_mb.round(1)} MB" if total_size_mb > 0
puts ""

puts "Usage in tests:"
puts "  model = BTAP::FileIO.load_osm('#{FIXTURE_DIR}/system_4_hw_toronto.osm')"
puts ""
puts "To regenerate all fixtures:"
puts "  ruby generate_integration_fixtures.rb --force"
puts ""
puts "To run sequentially:"
puts "  ruby generate_integration_fixtures.rb --sequential"
puts "="*80
