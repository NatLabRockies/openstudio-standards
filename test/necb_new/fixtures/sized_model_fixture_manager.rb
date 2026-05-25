#!/usr/bin/env ruby

require 'digest'
require 'fileutils'
require 'json'

# Manages pre-sized model fixtures with SQL files for testing.
# Uses the proven model setup pattern from test_system_sizing.rb:
#   - Load 5ZoneNoHVAC.osm resource model
#   - Set weather via OpenstudioStandards::Weather
#   - Apply NECB space types (Space Function / Office - open plan)
#   - Add HVAC system via standard.add_sysN_* methods
#   - Run sizing via try_sizing_run
class SizedModelFixtureManager
  FIXTURE_DIR = File.join(__dir__, 'sized_models')
  MANIFEST_FILE = File.join(FIXTURE_DIR, 'manifest.json')

  RESOURCE_MODEL_PATH = File.join(__dir__, '..', '..', 'necb', 'unit_tests', 'resources', '5ZoneNoHVAC.osm')

  EPW_FILES = {
    'toronto'    => 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    'vancouver'  => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
    'montreal'   => 'CAN_QC_Montreal.Intl.AP.716270_CWEC2020.epw',
    'calgary'    => 'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw',
    'yellowknife' => 'CAN_NT_Yellowknife.AP.719360_CWEC2020.epw'
  }.freeze

  class << self
    # Get or create a sized model fixture using a proven NECB pattern.
    # Returns: { osm_path:, sql_path:, epw_path:, config: }
    def get_or_create_sized_model(template: 'NECB2011', system_type: 'System1', climate: 'toronto')
      FileUtils.mkdir_p(FIXTURE_DIR)

      config = {
        template: template,
        system_type: system_type,
        climate: climate,
        openstudio_version: OpenStudio.openStudioVersion
      }
      cache_key = generate_cache_key(config)

      manifest = load_manifest
      if manifest[cache_key]
        cached = lookup_cached_fixture(manifest[cache_key])
        if cached
          puts "✓ Using cached sized fixture: #{template}/#{system_type}/#{climate} [#{cache_key[0..7]}]"
          return cached.merge(config: config)
        end
      end

      puts "⚙ Creating sized fixture: #{template}/#{system_type}/#{climate}"
      fixture = build_sized_model(template: template, system_type: system_type,
                                  climate: climate, cache_key: cache_key)

      manifest[cache_key] = {
        'osm_file' => File.basename(fixture[:osm_path]),
        'sql_file' => File.basename(fixture[:sql_path]),
        'epw_name' => EPW_FILES[climate],
        'config' => config,
        'created_at' => Time.now.iso8601
      }
      save_manifest(manifest)

      fixture.merge(config: config)
    end

    def clean_all_fixtures
      FileUtils.rm_rf(FIXTURE_DIR)
      FileUtils.mkdir_p(FIXTURE_DIR)
    end

    private

    def lookup_cached_fixture(entry)
      osm = File.join(FIXTURE_DIR, entry['osm_file'])
      sql = File.join(FIXTURE_DIR, entry['sql_file'])
      epw = OpenstudioStandards::Weather.get_standards_weather_file_path(entry['epw_name'])
      return nil unless File.exist?(osm) && File.exist?(sql) && File.exist?(epw)
      { osm_path: osm, sql_path: sql, epw_path: epw }
    end

    def build_sized_model(template:, system_type:, climate:, cache_key:)
      model, standard = load_baseline_model(template)
      apply_weather(model, climate)
      add_hvac_system(model, standard, system_type)

      run_dir = File.join(FIXTURE_DIR, "run_#{cache_key[0..8]}")
      FileUtils.rm_rf(run_dir)
      FileUtils.mkdir_p(run_dir)

      standard.try_sizing_run(model: model, sizing_run_dir: run_dir,
                              sizing_run_subdir: cache_key[0..8])

      sized_sql = find_sql(run_dir)
      unless sized_sql && File.exist?(sized_sql)
        raise "Sizing run failed: no SQL file produced in #{run_dir}"
      end

      final_osm = File.join(FIXTURE_DIR, "#{cache_key[0..8]}_sized.osm")
      final_sql = File.join(FIXTURE_DIR, "#{cache_key[0..8]}_sized.sql")
      model.save(OpenStudio::Path.new(final_osm), true)
      FileUtils.cp(sized_sql, final_sql)
      FileUtils.rm_rf(run_dir)

      epw = OpenstudioStandards::Weather.get_standards_weather_file_path(EPW_FILES[climate])
      { osm_path: final_osm, sql_path: final_sql, epw_path: epw }
    end

    def find_sql(run_dir)
      Dir.glob(File.join(run_dir, '**', 'eplusout.sql')).first
    end

    def load_baseline_model(template)
      standard = Standard.build(template)
      translator = OpenStudio::OSVersion::VersionTranslator.new
      model = translator.loadModel(RESOURCE_MODEL_PATH).get

      # NECB QAQC pipeline (necb_space_compliance) parses
      # space.spaceType.get.name expecting 'Space Function <type>'. Replace
      # all default SpaceTypes with a single shared one named exactly that,
      # so every space resolves and OpenStudio doesn't uniquify the name
      # ("...6") when multiple SpaceType objects share a label.
      model.getSpaceTypes.each(&:remove)
      shared_space_type = OpenStudio::Model::SpaceType.new(model)
      shared_space_type.setName('Space Function Office - open plan')
      shared_space_type.setStandardsBuildingType('Space Function')
      shared_space_type.setStandardsSpaceType('Office - open plan')
      model.getSpaces.each { |sp| sp.setSpaceType(shared_space_type) }

      building = model.getBuilding
      building.setStandardsNumberOfStories(1)
      building.setStandardsNumberOfAboveGroundStories(1)

      [model, standard]
    end

    def apply_weather(model, climate)
      epw_name = EPW_FILES.fetch(climate) { raise "Unknown climate: #{climate}" }
      epw_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_name)
      OpenstudioStandards::Weather.model_set_building_location(model, weather_file_path: epw_path)
    end

    def add_hvac_system(model, standard, system_type)
      zones = model.getThermalZones.sort
      case system_type
      when 'System1'
        standard.add_sys1_unitary_ac_baseboard_heating(
          model: model, zones: zones, mau_type: true,
          mau_heating_coil_type: 'Electric', baseboard_type: 'Electric', hw_loop: nil
        )
      when 'System3'
        standard.add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating(
          model: model, zones: zones, heating_coil_type: 'Gas',
          baseboard_type: 'Electric', hw_loop: nil
        )
      when 'System4'
        standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
          model: model, zones: zones, heating_coil_type: 'Gas',
          baseboard_type: 'Electric', hw_loop: nil
        )
      when 'System6'
        standard.add_sys6_multi_zone_built_up_system_with_baseboard_heating(
          model: model, zones: zones, heating_coil_type: 'Electric',
          baseboard_type: 'Electric', chiller_type: 'Scroll',
          fan_type: 'AF_or_BI_rdg_fancurve', hw_loop: nil
        )
      else
        raise "Unsupported system_type: #{system_type}"
      end
    end

    def generate_cache_key(config)
      Digest::SHA256.hexdigest(config.to_json)
    end

    def load_manifest
      File.exist?(MANIFEST_FILE) ? JSON.parse(File.read(MANIFEST_FILE)) : {}
    end

    def save_manifest(manifest)
      File.write(MANIFEST_FILE, JSON.pretty_generate(manifest))
    end
  end
end
