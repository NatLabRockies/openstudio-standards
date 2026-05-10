# NECB Fixture Manager
# Manages pre-sized OpenStudio models to avoid repeated sizing runs in tests
#
# Key features:
# - Content-addressable storage: fixtures are keyed by their configuration hash
# - Automatic cache invalidation: fixtures include version info
# - Lazy creation: fixtures are created on first access if they don't exist
# - Git-friendly: fixtures can be checked into repository

require 'digest'
require 'json'
require 'fileutils'

module NecbFixtureManager

  # Root directory for all fixtures
  FIXTURES_ROOT = File.expand_path('../../test/necb/fixtures', __dir__)
  SIZED_MODELS_DIR = File.join(FIXTURES_ROOT, 'sized_models')
  MANIFEST_FILE = File.join(FIXTURES_ROOT, 'fixture_manifest.json')

  # Fixture format version (increment when fixture structure changes)
  FIXTURE_VERSION = '1.0'

  class << self

    # Get or create a sized model fixture
    #
    # @param template [String] NECB template (e.g., 'NECB2011', 'NECB2015')
    # @param building_type [String] Building type (e.g., 'MediumOffice', 'Retail')
    # @param epw_file [String] Weather file name (e.g., 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw')
    # @param system_type [Integer, nil] NECB system type (1-8) or nil for no HVAC
    # @param customize_block [Proc, nil] Optional block to customize model before sizing
    # @return [OpenStudio::Model::Model, nil] The sized model, or nil if creation failed
    #
    # @example
    #   model = NecbFixtureManager.get_or_create_sized_model(
    #     template: 'NECB2011',
    #     building_type: 'MediumOffice',
    #     epw_file: 'CAN_ON_Toronto.Intl.AP.716240_CWEC2020.epw',
    #     system_type: 2
    #   )
    def get_or_create_sized_model(template:, building_type:, epw_file:, system_type: nil, &customize_block)
      # Generate unique key for this configuration
      config = {
        template: template,
        building_type: building_type,
        epw_file: epw_file,
        system_type: system_type,
        openstudio_version: OpenStudio.openStudioVersion,
        fixture_version: FIXTURE_VERSION
      }

      fixture_key = generate_fixture_key(config)
      fixture_path = fixture_file_path(fixture_key)

      # Check if fixture exists and is valid
      if File.exist?(fixture_path)
        if fixture_valid?(fixture_path, config)
          puts "  [Fixture] Loading cached model: #{fixture_key}"
          return load_fixture(fixture_path)
        else
          puts "  [Fixture] Cached model invalid, regenerating: #{fixture_key}"
          File.delete(fixture_path)
        end
      end

      # Create new fixture
      puts "  [Fixture] Creating new sized model: #{fixture_key}"
      model = create_and_size_model(config, customize_block)

      if model
        save_fixture(model, fixture_path, config)
        update_manifest(fixture_key, config)
      end

      model
    end

    # Get path where a fixture would be stored (doesn't check if it exists)
    #
    # @param config [Hash] Configuration hash
    # @return [String] Path to fixture file
    def fixture_path(config)
      fixture_key = generate_fixture_key(config)
      fixture_file_path(fixture_key)
    end

    # Clear all fixtures matching a pattern
    #
    # @param pattern [String] Glob pattern (e.g., 'NECB2011_*', '*MediumOffice*')
    # @return [Integer] Number of fixtures cleared
    def clear_fixtures(pattern: '*')
      ensure_fixtures_directory

      matched_files = Dir.glob(File.join(SIZED_MODELS_DIR, "#{pattern}.osm"))

      matched_files.each do |file|
        File.delete(file)
        puts "  [Fixture] Deleted: #{File.basename(file)}"
      end

      # Update manifest
      load_manifest.delete_if { |key, _| matched_files.any? { |f| f.include?(key) } }
      save_manifest

      matched_files.length
    end

    # Clear all fixtures (use with caution!)
    #
    # @return [Integer] Number of fixtures cleared
    def clear_all_fixtures
      clear_fixtures(pattern: '*')
    end

    # Get list of all available fixtures
    #
    # @return [Array<Hash>] Array of fixture metadata
    def list_fixtures
      manifest = load_manifest
      manifest.values.sort_by { |f| f['created_at'] }.reverse
    end

    # Get fixture statistics
    #
    # @return [Hash] Statistics about fixtures
    def fixture_stats
      manifest = load_manifest

      {
        total_fixtures: manifest.length,
        total_size_mb: calculate_total_size,
        by_template: manifest.group_by { |_, v| v['config']['template'] }.transform_values(&:length),
        by_building_type: manifest.group_by { |_, v| v['config']['building_type'] }.transform_values(&:length),
        oldest: manifest.values.min_by { |f| f['created_at'] },
        newest: manifest.values.max_by { |f| f['created_at'] }
      }
    end

    private

    # Generate unique key for a configuration
    def generate_fixture_key(config)
      # Create deterministic hash from config (excluding version info for key)
      key_config = config.slice(:template, :building_type, :epw_file, :system_type)
      hash = Digest::SHA256.hexdigest(key_config.to_json)[0..15]

      # Create human-readable name with hash for uniqueness
      epw_name = File.basename(config[:epw_file], '.epw').split('.').first
      sys_part = config[:system_type] ? "_sys#{config[:system_type]}" : ""

      "#{config[:template]}_#{config[:building_type]}_#{epw_name}#{sys_part}_#{hash}"
    end

    # Get full file path for a fixture key
    def fixture_file_path(fixture_key)
      File.join(SIZED_MODELS_DIR, "#{fixture_key}.osm")
    end

    # Check if a fixture is valid (versions match, file not corrupted)
    def fixture_valid?(fixture_path, config)
      return false unless File.exist?(fixture_path)
      return false if File.zero?(fixture_path)

      # Check if version info matches
      manifest = load_manifest
      fixture_key = File.basename(fixture_path, '.osm')
      fixture_metadata = manifest[fixture_key]

      return false unless fixture_metadata

      # Verify OpenStudio version and fixture format version match
      fixture_metadata['config']['openstudio_version'] == config[:openstudio_version] &&
        fixture_metadata['config']['fixture_version'] == config[:fixture_version]
    end

    # Load a fixture from disk
    def load_fixture(fixture_path)
      translator = OpenStudio::OSVersion::VersionTranslator.new
      model = translator.loadModel(fixture_path)

      if model.empty?
        puts "  [Fixture] ERROR: Failed to load model from #{fixture_path}"
        return nil
      end

      model.get
    end

    # Create and size a model based on configuration
    def create_and_size_model(config, customize_block)
      require_relative '../helpers/necb_helper'

      template = config[:template]
      building_type = config[:building_type]
      epw_file = config[:epw_file]
      system_type = config[:system_type]

      # Create standard
      standard = Standard.build(template)

      # Create prototype model
      begin
        # Get weather file path
        weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(epw_file)

        # Create sizing run directory for this fixture
        sizing_run_dir = File.join(SIZED_MODELS_DIR, '.sizing_runs', generate_fixture_key(config))
        FileUtils.mkdir_p(sizing_run_dir)

        # Create prototype model
        model = standard.model_create_prototype_model(
          template: template,
          epw_file: epw_file,
          building_type: building_type,
          sizing_run_dir: sizing_run_dir
        )

        # Apply custom modifications if provided
        if customize_block
          customize_block.call(model, standard)
        end

        return model

      rescue StandardError => e
        puts "  [Fixture] ERROR: Failed to create model - #{e.message}"
        puts e.backtrace.first(5).join("\n")
        return nil
      end
    end

    # Save a fixture to disk
    def save_fixture(model, fixture_path, config)
      ensure_fixtures_directory

      # Save model
      model.save(fixture_path, true)

      puts "  [Fixture] Saved: #{File.basename(fixture_path)} (#{(File.size(fixture_path) / 1024.0 / 1024.0).round(2)} MB)"
    end

    # Ensure fixture directories exist
    def ensure_fixtures_directory
      FileUtils.mkdir_p(FIXTURES_ROOT)
      FileUtils.mkdir_p(SIZED_MODELS_DIR)
    end

    # Load fixture manifest
    def load_manifest
      return {} unless File.exist?(MANIFEST_FILE)

      JSON.parse(File.read(MANIFEST_FILE))
    rescue JSON::ParserError
      puts "  [Fixture] WARNING: Corrupt manifest file, starting fresh"
      {}
    end

    # Save fixture manifest
    def save_manifest
      ensure_fixtures_directory
      File.write(MANIFEST_FILE, JSON.pretty_generate(@manifest || load_manifest))
    end

    # Update manifest with new fixture
    def update_manifest(fixture_key, config)
      @manifest = load_manifest

      @manifest[fixture_key] = {
        'config' => config.transform_keys(&:to_s),
        'created_at' => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'file_size_mb' => (File.size(fixture_file_path(fixture_key)) / 1024.0 / 1024.0).round(2)
      }

      save_manifest
    end

    # Calculate total size of all fixtures
    def calculate_total_size
      return 0.0 unless Dir.exist?(SIZED_MODELS_DIR)

      total_bytes = Dir.glob(File.join(SIZED_MODELS_DIR, '*.osm')).sum { |f| File.size(f) }
      (total_bytes / 1024.0 / 1024.0).round(2)
    end

  end
end
