require 'openstudio'

module BTAP

  # BTAP Analysis
  #
  # Class to instantiate post-analysis mechanisms like costing or carbon
  # calculation. Can be done during a simulation or without one given an OSM file
  # and its SQL file, along with a few other parameters.
  #
  # Abstract class, only instantiate BTAP::NoSimAnalysis or BTAP::DatapointAnalysis.
  class Analysis
    attr_accessor :attributes

    # @param output_folder [String]
    def initialize(output_folder:)
      @output_folder = output_folder
    end

    # Run BTAP Costing.
    #
    # @param costs_csv [String] Path to a custom costing CSV file if custom
    #                           costing is desired.
    # @param factors_csv [String] Path to a custom costing localization factors
    #                             CSV file if custom costing is desired.
    def run_costing(costs_csv: Paths.costs_path, factors_csv: Paths.costs_local_factors_path)
      costing = Costing.new(costs_csv: costs_csv, factors_csv: factors_csv, attributes: @attributes)

      cost_result, _ = costing.cost_audit_all(
        model: @model,
        prototype_creator: @standard,
        template_type: @model.getBuilding.standardsTemplate.get)

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
      carbon = Carbon.new(attributes: @attributes, standards_data: @standard.standards_data)
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

    # @param model [OpenStudio::Model::Model]
    def self.get_tbd_attributes(model:)

      # The "psi_quality" additional property is only initialized when TBD
      # is run, used as a marker here to determine the "use_tbd" attribute.
      use_tbd = model.getBuilding.additionalProperties.hasFeature("psi_quality")
      building_performance = use_tbd ?
        model.getBuilding.additionalProperties.getFeatureAsString("psi_quality").get : nil

      tbd_edge_tallies = {}

      # Process the thermal bridging edge tallies out of the building's
      # additional properties and format them into a hash.
      if use_tbd
        ["fenestration", "grade", "parapet", "corner", "rimjoist"].each do |edge_type|
          edge_key = "PSI#{edge_type}1"
          if model.getBuilding.additionalProperties.hasFeature(edge_key)
            tbd_edge_tallies[edge_type] = {}
            wall_reference, quantity =
              model.getBuilding.additionalProperties.getFeatureAsString(edge_key).get.split(/\s(?=\d)/)

            tbd_edge_tallies[edge_type][wall_reference] = quantity.to_f
          end
        end
      end

      return use_tbd, building_performance, tbd_edge_tallies
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
  # @param output_folder   [String]
  # @param template        [String]
  # @param datapoint_id    [String]
  # @param analysis_id     [String]
  class NoSimAnalysis < Analysis
    def initialize(
      model_path:,
      sql_file_path:,
      output_folder:,
      datapoint_id:,
      analysis_id: SecureRandom.uuid)

      super(output_folder: output_folder)
      @model    = BTAP::FileIO.load_osm(model_path)
      @standard = Standard.build(@model.getBuilding.standardsTemplate.get)
      @standard.assign_building_activity(model: @model)
      @standard.assign_building_structure(model: @model, activity: @standard.activity)
      @datapoint_id = datapoint_id
      @analysis_id  = analysis_id

      use_tbd, building_performance, tbd_edge_tallies = Analysis.get_tbd_attributes(model: @model)
      @attributes   = BTAP::Attributes.new(
        model: @model,
        standard: @standard,
        use_tbd: use_tbd,
        building_performance: building_performance,
        tbd_edge_tallies: tbd_edge_tallies)
      @model.setSqlFile(OpenStudio::SqlFile.new(sql_file_path))
      @qaqc = BTAP::Datapoint.build_qaqc(@model, @standard, @datapoint_id, @analysis_id)
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
    def initialize(model:, output_folder:, standard:, qaqc:)
      super(output_folder: output_folder)
      @model    = model
      @standard = standard
      @qaqc     = qaqc

      use_tbd, building_performance, tbd_edge_tallies = Analysis.get_tbd_attributes(model: @model)
      @attributes   = BTAP::Attributes.new(
        model: @model,
        standard: @standard,
        use_tbd: use_tbd,
        building_performance: building_performance,
        tbd_edge_tallies: tbd_edge_tallies)
    end
  end
end
