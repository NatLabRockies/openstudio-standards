require 'openstudio'

module BTAP
  # BTAP Analysis
  #
  # Class to instantiate post-analysis mechanisms like costing or carbon
  # calculation. Can be done during a simulation or without one given an OSM file
  # and its SQL file, along with a few other parameters.
  #
  # Abstract class, only instantiate BTAPNoSimAnalysis or BTAPDatapointAnalysis.
  class Analysis
    attr_accessor :attributes

    # @param output_folder [String] 
    # @param template      [String] The standard as a string.
    def initialize(output_folder:, template:)
      @output_folder = output_folder
      @template      = template
      @cp            = CommonPaths.instance
    end

    # Run BTAP Costing.
    #
    # @param costs_csv [String] Path to a custom costing CSV file if custom 
    #   costing is desired.
    # @param costs_local_factors_path [String] Path to a custom costing
    #   localization factors CSV file if custom costing is desired.
    def run_costing(costs_csv: @cp.costs_path, factors_csv: @cp.costs_local_factors_path)
      costing = BTAPCosting.new(costs_csv: costs_csv, factors_csv: factors_csv, attributes: @attributes)

      cost_result, _ = costing.cost_audit_all(
        model: @model, 
        prototype_creator: @standard, 
        template_type: @template)

      if not @qaqc.nil?
        @qaqc[:costing_information] = cost_result
      end

      File.open(File.join(@output_folder, 'cost_results.json'), 'w') do |f| 
        f.write(JSON.pretty_generate(cost_result, allow_nan: true))
      end
      puts "Wrote File cost_results.json in #{@output_folder} "
    
      return cost_result
    end

    # Run BTAP Carbon.
    def run_carbon
      carbon = BTAPCarbon.new(attributes: @attributes, standards_data: @standard.standards_data)
      carbon_result = carbon.audit_embodied_carbon

      if not @qaqc.nil?
        @qaqc[:carbon_information] = carbon_result
      end
    
      File.open(File.join(@output_folder, 'carbon_results.json'), 'w') do |f| 
        f.write(JSON.pretty_generate(carbon_result, allow_nan: true))
      end
      puts "Wrote File carbon_results.json in #{@output_folder} "    

      return carbon_result
    end

    # Write the cache by interfacing with the BTAP::Cache attribute.
    #
    # @param file [String] File path to save to.
    def write_cache(path)
      BTAP::Cache.new(@standard).write_cache(path)
    end
  end

  # BTAP No Simulation Analysis
  # 
  # Instantiate this class and run `run_costing` and/or `run_carbon` to run one
  # of those modules without performing a full annual simulation or building a
  # standard. This requires a number of parameters to be passed, all of which are
  # provided from the simulation results of a full annual simulation. This
  # requires some parameters of the Standard class to be manually loaded
  # Therefore, a no-simulation analysis requires a full simulation to be run to
  # retrieve the files necessary. Those files and other parameters are listed
  # below:
  # 
  # @param model_path      [String] The path of the OSM file for a model.
  # @param sql_file_path   [String] SQL file of the model required for hourly 
  #                                 data.
  # @param cache_file_path [String] More attributes required for simulation. See 
  #                                 the `write_cache` function.
  # @param output_folder   [String]
  # @param template        [String]
  # @param datapoint_id    [String]
  # @param analysis_id     [String]
  class NoSimAnalysis < Analysis
    def initialize(
      model_path:,
      sql_file_path:,
      cache_file_path:,
      output_folder:,
      template:,
      datapoint_id:,
      analysis_id: SecureRandom.uuid)

      super(output_folder: output_folder, template: template)
      @model    = BTAP::FileIO.load_osm(model_path)
      @template = template
      @standard = Standard.build(template)
      @standard.assign_building_activity(model: @model)
      @standard.assign_building_structure(model: @model, activity: @standard.activity, massive: true)
      @datapoint_id = datapoint_id
      @analysis_id  = analysis_id
      @cache_data   = BTAP::Cache.load_cache(cache_file_path)
      @attributes   = BTAP::Attributes.new(
        @model, 
        @standard, 
        @cache_data["use_tbd"],
        @cache_data["building_performance"], 
        @cache_data["tbd_edge_tallies"])
      @model.setSqlFile(OpenStudio::SqlFile.new(sql_file_path))
      @qaqc = BTAPDatapoint.build_qaqc(@model, @standard, @datapoint_id, @analysis_id)             
    end
  end

  # BTAP Datapoint Analysis
  #
  # Helper function to run post-analysis mechanisms in `btap_datapoint.rb`.
  # @param model    [OpenStudio::Model::Model]
  # @param standard [Standard]
  # @param template [String]
  # @param qaqc     [Hash] Doesn't seem to be currently relevant but still
  #                        required.
  class DatapointAnalysis < Analysis
    def initialize(model:, output_folder:, template:, standard:, qaqc:)
      super(output_folder: output_folder, template: template)
      @model      = model
      @standard   = standard
      @qaqc       = qaqc
      @cache      = BTAP::Cache.new(@standard)
      @attributes = BTAP::Attributes.new(
        @model, 
        @standard, 
        @cache.data["use_tbd"],
        @cache.data["building_performance"], 
        @cache.data["tbd_edge_tallies"])
    end
  end

  # BTAP Cache
  #
  # Interface for storing and loading useful data members not found in either
  # the OSM or SQL file that are required for further analysis.
  class Cache
    attr_reader :data

    # @param standard [Standard]
    def initialize(standard)
      @data = {}
      data["use_tbd"] = !(standard.tbd.nil?)
      if data["use_tbd"]
        data["building_performance"] = standard.tbd.model[:perform] == :lp ? "low" : "high"

        # The "convex/concave" suffix on tally edges can be safely ignored since
        # they currently aren't relevant to any NECB standard, but they are to
        # ASHRAE 90.1.
        data["tbd_edge_tallies"] = standard.tbd.tally[:edges].transform_keys { |key|
          key.to_s.gsub(/concave|convex/, '') }
      end
    end

    # @param path [String]
    def write_cache(path)
      File.open(path, "w") do |file|
        file.write(JSON.pretty_generate(@data))
      end
    end

    # @param path [String]
    def self.load_cache(path)
      return File.open(path, "r") { |file| JSON.load(file) }
    end
  end
end
