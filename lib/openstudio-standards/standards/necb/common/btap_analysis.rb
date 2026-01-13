require 'openstudio'

# BTAP Analysis:
#   Class to instantiate post-analysis mechanisms like costing or carbon 
#   calculation.
#   Can be done during a simulation or without one given an OSM file and its SQL 
#   file, along with a few other parameters. 

# Abstract class, only instantiate BTAPNoSimAnalysis or BTAPDatapointAnalysis.
class BTAPAnalysis
  def initialize(output_folder:, template:)
    @output_folder = output_folder
    @template      = template
    @cp            = CommonPaths.instance
  end

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
end

# For a no-simulation run, the SQL file, template, and datapoint ID must be provided.
class BTAPNoSimAnalysis < BTAPAnalysis
  def initialize(model_path:, sql_file_path:, output_folder:, template:, datapoint_id:, analysis_id: SecureRandom.uuid)
    super(output_folder: output_folder, template: template)
    @model        = BTAP::FileIO.load_osm(model_path)
    @template     = template
    @standard     = Standard.build(template)
    @datapoint_id = datapoint_id
    @analysis_id  = analysis_id
    @attributes   = BTAP::Attributes.new(@model, @standard)
    @model.setSqlFile(OpenStudio::SqlFile.new(sql_file_path))
    @qaqc = BTAPDatapoint.build_qaqc(@model, @standard, @datapoint_id, @analysis_id)             
  end
end

class BTAPDatapointAnalysis < BTAPAnalysis
  def initialize(model:, output_folder:, template:, standard:, qaqc:)
    super(output_folder: output_folder, template: template)
    @model      = model
    @standard   = standard
    @qaqc       = qaqc
    @attributes = BTAP::Attributes.new(@model, @standard)
  end
end
