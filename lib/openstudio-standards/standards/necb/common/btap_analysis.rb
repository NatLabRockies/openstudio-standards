require 'openstudio'

# BTAP Analysis:
#   Class to instantiate post-analysis mechanisms like costing or carbon
#   calculation.
#   Can be done during a simulation or without one given an OSM file and its SQL
#   file, along with a few other parameters.

# Abstract class, only instantiate BTAPNoSimAnalysis or BTAPDatapointAnalysis.
class BTAPAnalysis
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

    cost_result, btap_items = costing.cost_audit_all(
      model: @model,
      prototype_creator: @standard,
      template_type: @template)

    if not @qaqc.nil?
      @qaqc[:costing_information] = cost_result
    end

    cost_result["openstudio-version"] = OpenstudioStandards::VERSION
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

  # Write the cache by interfacing with the BTAPStandardCache attribute.
  #
  # @param file [String] File path to save to.
  def write_cache(path)
    @standard.tbd.shorten_instance_variables
    cache = BTAPStandardCache.new(@standard.tbd, @standard.structure)
    cache.write_cache(path)
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
class BTAPNoSimAnalysis < BTAPAnalysis
  def initialize(
    model_path:,
    sql_file_path:,
    cache_file_path:,
    output_folder:,
    template:,
    datapoint_id:,
    analysis_id: SecureRandom.uuid)

    super(output_folder: output_folder, template: template)
    @model              = BTAP::FileIO.load_osm(model_path)
    @template           = template
    @standard           = Standard.build(template)
    @standard.load_standard_cache(self.load_cache(cache_file_path, @model))
    @datapoint_id       = datapoint_id
    @analysis_id        = analysis_id
    @attributes         = BTAP::Attributes.new(@model, @standard)
    @model.setSqlFile(OpenStudio::SqlFile.new(sql_file_path))
    @qaqc = BTAPDatapoint.build_qaqc(@model, @standard, @datapoint_id, @analysis_id)
  end

  # Load the cache by interfacing with the BTAPStandardCache attribute.
  #
  # @param file [String] File path to load from.
  def load_cache(path, model)
    return BTAPStandardCache.load_cache(path, model)
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
class BTAPDatapointAnalysis < BTAPAnalysis
  def initialize(model:, output_folder:, template:, standard:, qaqc:)
    super(output_folder: output_folder, template: template)
    @model      = model
    @standard   = standard
    @qaqc       = qaqc
    @attributes = BTAP::Attributes.new(@model, @standard)
  end
end

# BTAP Standard Cache
#
# Wrapper class that contains useful instance variables of the `Standard`
# object.
# These attributes are:
# tbd:       Thermal bridging edges and material takeoffs.
# structure: Defines building category dictating kinds of materials to be 
#            used.
class BTAPStandardCache
  attr_reader :tbd
  attr_reader :structure

  # @param tbd      [BTAP::Bridging]
  # @param standard [BTAP::Structure]
  def initialize(tbd, structure)
    @tbd       = tbd
    @structure = structure
  end

  # Write useful attributes to a binary file using Marshal. 
  #
  # @param file [String] File path to save to.
  def write_cache(path)
    File.open(path, "w") do |file|
      file.write(Marshal.dump(self))
    end
  end

  # Load the binary cache file.
  #
  # @param file  [String] File path to load from.
  # @param model [OpenStudio::Model::Model] Required to match surfaces.
  def self.load_cache(path, model)
    return File.open(path, "r") { |file| Marshal.load(file) }
  end
end
