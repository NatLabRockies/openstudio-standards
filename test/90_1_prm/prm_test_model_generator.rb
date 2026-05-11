require_relative './prm_test_decorators'

class AppendixGPRMTests < Minitest::Test
  # Set folder for JSON files related to tests and
  # parse individual JSON files used by all methods
  # in this class.
  @@json_dir = "#{File.dirname(__FILE__)}/data"
  @@prototype_list = JSON.parse(File.read("#{@@json_dir}/prototype_list.json"))
  @@wwr_building_types = JSON.parse(File.read("#{@@json_dir}/wwr_building_types.json"))
  @@hvac_building_types = JSON.parse(File.read("#{@@json_dir}/hvac_building_types.json"))
  @@swh_building_types = JSON.parse(File.read("#{@@json_dir}/swh_building_types.json"))
  @@wwr_values = JSON.parse(File.read("#{@@json_dir}/wwr_values.json"))
  @@hasres_values = JSON.parse(File.read("#{@@json_dir}/hasres_values.json"))
  # Global variable to ...
  # Make sure to turn it to false so CI will not fail for time out.
  GENERATE_PRM_LOG = false
  MAX_PATH_CHAR = 1800 # linux should set to a 1800, windows should set to 200, set to 1800 when push to the repo or open PR to pass CI.

  def prm_test_helper(test_string, require_prototype = true, require_baseline = true, require_proposed = false)
    # Get list of unique prototypes
    prototypes_to_generate = get_prototype_to_generate(test_string, @@prototype_list)
    # Generate all unique prototypes
    prototypes_generated = generate_prototypes(prototypes_to_generate, test_string)
    # Create all unique baseline
    prototypes_baseline_generated, prototypes_proposed_generated = generate_baseline(prototypes_generated, prototypes_to_generate, test_string)

    model_hash = {}
    if require_prototype
      prototypes = assign_prototypes(prototypes_generated, [test_string], prototypes_to_generate)
      # Here, prototype is the 'user model'
      model_hash['prototype'] = prototypes[test_string]
    end
    if require_baseline
      # Assign prototypes and baseline model to each test
      prototypes_base = assign_prototypes(prototypes_baseline_generated, [test_string], prototypes_to_generate)
      model_hash['baseline'] = prototypes_base[test_string]
    end
    if require_proposed
      # Assign prototypes and proposed model to each test
      prototypes_proposed = assign_prototypes(prototypes_proposed_generated, [test_string], prototypes_to_generate)
      model_hash['proposed'] = prototypes_proposed[test_string]
    end
    return model_hash
  end

  # Generate one of the ASHRAE 90.1 prototype model included in openstudio-standards.
  #
  # @param prototypes_to_generate [Array] List of prototypes to generate, see prototype_list.json to see the structure of the list
  # @param test_string [String] test string
  # @return [Hash] Hash of OpenStudio Model of the prototypes
  def generate_prototypes(prototypes_to_generate, test_string)
    prototypes = {}
    @lpd_space_types_alt = {}
    @bldg_type_alt = {}
    @bldg_type_alt_now = nil

    prototypes_to_generate.each do |id, prototype|
      # mod is an array of method intended to modify the model
      building_type, template, climate_zone, user_data_dir, mod = prototype

      climate_zone_code = climate_zone.split('-')[-1]
      assert(building_type != 'LargeOffice' || ['0A', '0B', '1A', '1B', '2A', '2B'].include?(climate_zone_code), "Baseline model cannot be generated for #{building_type} in climate zone: #{climate_zone}. Due to a known problem with sizing of heating system for data center (which has zero heating load), the large office model fails in mild to cold climates (CZ 3 and higher). Use climate zone 0, 1 or 2 instead")

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      # Initialize weather file, necessary but not used
      epw_file = 'USA_FL_Miami.Intl.AP.722020_TMY3.epw'

      # Create output folder if it doesn't already exist
      @test_dir = "#{File.dirname(__FILE__)}/output"
      if !Dir.exist?(@test_dir)
        Dir.mkdir(@test_dir)
      end

      # Define model name and run folder if it doesn't already exist,
      # if it does, remove it and re-create it.
      model_name = mod.empty? ? "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}" : "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}-#{mod_str}"
      run_dir = "#{@test_dir}/#{model_name}"
      run_dir = run_dir.length > MAX_PATH_CHAR ? (run_dir[0...MAX_PATH_CHAR]).to_s : run_dir
      if !Dir.exist?(run_dir)
        Dir.mkdir(run_dir)
      else
        FileUtils.rm_rf(run_dir)
        Dir.mkdir(run_dir)
      end

      # Create the prototype
      @prototype_creator = Standard.build("#{template}_#{building_type}")
      model = @prototype_creator.model_create_prototype_model(climate_zone, epw_file, run_dir)

      # Make modification if requested
      @bldg_type_alt_now = nil
      if !mod.empty?
        mod.each do |method_mod|
          mthd, arguments = method_mod
          model = public_send(mthd, model, arguments)
        end
      end

      # Store alternate building type into hash
      if !@bldg_type_alt_now.nil?
        @bldg_type_alt[prototype] = @bldg_type_alt_now
      else
        @bldg_type_alt[prototype] = nil?
      end

      # Save prototype OSM file
      osm_path = OpenStudio::Path.new("#{run_dir}/#{model_name}.osm")
      model.save(osm_path, true)

      # Translate prototype model to an IDF file
      forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      idf_path = OpenStudio::Path.new("#{run_dir}/#{model_name}.idf")
      idf = forward_translator.translateModel(model)
      idf.save(idf_path, true)

      # Save OpenStudio model object
      prototypes[id] = model
    end
    return prototypes
  end

  # Generate the 90.1 Appendix G baseline for a model following the 90.1-2019 PRM rules
  #
  # @param prototypes_generated [Array] List of all unique prototypes for which baseline models will be created
  # @param id_prototype_mapping [Hash] Mapping of prototypes to their identifiers generated by prototypes_to_generate()
  # @param test_string [String] test string
  # @return [Array] Array of hashes of OpenStudio Model of the prototypes
  def generate_baseline(prototypes_generated, id_prototype_mapping, test_string)
    baseline_prototypes = {}
    proposed_prototypes = {}
    prototypes_generated.each do |id, proposed_model|
      building_type, template, climate_zone, user_data_dir, mod = id_prototype_mapping[id]

      # Concatenate modifier functions and arguments
      mod_str = mod.flatten.join('_') unless mod.empty?

      # Create a deep copy of the proposed model
      model = BTAP::FileIO.deep_copy(proposed_model)

      # Initialize Standard class
      @prototype_creator = Standard.build('90.1-PRM-2019')

      # user data CSV files are in @user_data_dir, if appicable
      # user data JSON files will be created in sub-folder inside @test_dir
      model_name = mod.empty? ? "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}" : "#{building_type}-#{template}-#{climate_zone}-#{test_string}-#{user_data_dir}-#{mod_str}"
      proto_run_dir = "#{@test_dir}/#{model_name}"
      proto_run_dir = proto_run_dir.length > MAX_PATH_CHAR ? (proto_run_dir[0...MAX_PATH_CHAR]).to_s : proto_run_dir

      if user_data_dir != 'no_user_data'
        json_path = @prototype_creator.convert_userdata_csv_to_json("#{@@json_dir}/#{user_data_dir}", proto_run_dir)
        @prototype_creator.load_userdata_to_standards_database(json_path)
      end

      # Convert standardSpaceType string for each space to values expected for prm creation
      lpd_space_types = JSON.parse(File.read("#{@@json_dir}/lpd_space_types.json"))
      model.getSpaceTypes.sort.each do |space_type|
        next if space_type.floorArea == 0

        standards_space_type = if space_type.standardsSpaceType.is_initialized
                                 space_type.standardsSpaceType.get
                               end
        std_bldg_type = space_type.standardsBuildingType.get
        bldg_type_space_type = std_bldg_type + space_type.standardsSpaceType.get
        new_space_type = lpd_space_types[bldg_type_space_type]
        alt_space_type_was_found = false
        unless @lpd_space_types_alt.nil?
          # Check alternate hash of LPD space types before replacing from JSON list
          @lpd_space_types_alt.each do |alt_bldg_space_type, n_spc_t|
            if bldg_type_space_type == alt_bldg_space_type
              alt_space_type_was_found = true
              space_type.setStandardsSpaceType(n_spc_t)
              break
            end
          end
        end
        if alt_space_type_was_found == false
          if lpd_space_types.key? bldg_type_space_type
            space_type.setStandardsSpaceType(lpd_space_types[bldg_type_space_type])
          else
            puts 'key not found in lpd_space_types.json'
          end
        end
      end

      # Disable Under Case HVAC Return Air Fraction for refrigerated cases
      # Since current tests result in ZoneHVAC systems for zones with refrigeration for large hotel
      # TODO: remove this when we have multiple HVAC building types available
      # since PSZ will be the typical baseline system for those zones with that in place
      model.getRefrigerationCases.sort.each do |refg_case|
        if !refg_case.isUnderCaseHVACReturnAirFractionDefaulted
          refg_case.setUnderCaseHVACReturnAirFraction(0)
        end
      end

      # Define run directory and run name, delete existing folder if it exists
      run_dir_baseline = "#{proto_run_dir}-Baseline"
      if Dir.exist?(run_dir_baseline)
        FileUtils.rm_rf(run_dir_baseline)
      end

      if @bldg_type_alt[id_prototype_mapping[id]] == false
        hvac_building_type = building_type
      else
        hvac_building_type = @bldg_type_alt[id_prototype_mapping[id]]
      end

      unmet_load_hours = mod_str == 'unmet_load_hours'

      # Create baseline model
      model_baseline = @prototype_creator.model_create_prm_any_baseline_building(model, '',
                                                                                 climate_zone,
                                                                                 @@hvac_building_types[hvac_building_type],
                                                                                 @@wwr_building_types[building_type],
                                                                                 @@swh_building_types[building_type],
                                                                                 model_deep_copy = true,
                                                                                 create_proposed_model = true,
                                                                                 custom = nil,
                                                                                 sizing_run_dir = run_dir_baseline,
                                                                                 run_all_orients = true,
                                                                                 unmet_load_hours_check = false,
                                                                                 debug = GENERATE_PRM_LOG,
                                                                                 use_parallel = false)

      # Check if baseline model could be created
      assert(model_baseline, "Baseline model could not be generated for #{building_type}, #{template}, #{climate_zone}.")

      # Check if proposed model was also generated
      model_proposed_file_name = "#{run_dir_baseline}/proposed_final.osm"
      assert(File.exist?(model_proposed_file_name.to_s), "Proposed model could not be generate for #{building_type}, #{template}, #{climate_zone}.")

      # Load newly generated baseline and proposed model
      @test_dir = "#{File.dirname(__FILE__)}/output"
      model_baseline_file_name = "#{run_dir_baseline}/baseline_final.osm"
      model_baseline = OpenStudio::Model::Model.load(model_baseline_file_name)
      model_baseline = model_baseline.get
      model_proposed = OpenStudio::Model::Model.load(model_proposed_file_name)
      model_proposed = model_proposed.get

      # Do sizing run for baseline and proposed model
      [[model_baseline, 'baseline'], [model_proposed, 'proposed']].each do |model, model_name|
        sim_control = model.getSimulationControl
        sim_control.setRunSimulationforSizingPeriods(true)
        sim_control.setRunSimulationforWeatherFileRunPeriods(false)
        model_run = @prototype_creator.model_run_simulation_and_log_errors(model, "#{run_dir_baseline}/#{model_name}-SR")
      end

      # Add models to the hash of baseline and proposed models
      baseline_prototypes[id] = model_baseline
      proposed_prototypes[id] = model_proposed
    end
    return baseline_prototypes, proposed_prototypes
  end

  # Identify individual prototypes to be created
  #
  # @param tests [Array] Names of the tests to be performed
  # @param prototype_list [Hash] List of prototypes needed for each test
  #
  # @return [Hash] Prototypes to be generated
  def get_prototype_to_generate(tests, prototype_list)
    # Initialize prototype identifier
    id = 0
    # Associate model description to identifiers
    prototypes_to_generate = {}

    # Note: tests is always a string?
    # prototypes = prototype_list[tests]
    # prototypes.each_with_index do |prototype, index|
    #   prototypes_to_generate[index] = prototype
    # end
    prototype_list.each do |utest, prototypes|
      prototypes.each do |prototype|
        if !prototypes_to_generate.values.include?(prototype) && tests.include?(utest)
          prototypes_to_generate[id] = prototype
          id += 1
        end
      end
    end
    return prototypes_to_generate
  end

  # Assign prototypes to each individual tests
  #
  # @param prototypes_generated [Hash] Hash containing all the OpenStudio model objects of the prototypes that have been created
  # @param tests [Array] List of tests to be performed
  # @param id_prototype_mapping [Hash] Mapping of prototypes to their respective ids
  #
  # @return [Hash] Association of OpenStudio model object to model description for each test
  def assign_prototypes(prototypes_generated, tests, id_prototype_mapping)
    test_prototypes = {}
    tests.each do |test|
      test_prototypes[test] = {}
      @@prototype_list[test].each do |prototype|
        # Find prototype id in mapping
        prototype_id = -9999.0
        id_prototype_mapping.each do |id, prototype_description|
          if prototype_description == prototype
            prototype_id = id
          end
        end
        test_prototypes[test][prototype] = prototypes_generated[prototype_id]
      end
    end
    return test_prototypes
  end
end
