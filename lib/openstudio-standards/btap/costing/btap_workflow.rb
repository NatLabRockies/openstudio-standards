require_relative '../../../../lib/openstudio-standards.rb'

class BTAPWorkflow
  attr_accessor :workflow

  def initialize(measures_folder: File.join(__dir__, '../../measures'))
    @model = nil
    @run_dir = nil
    @sql_path = nil
    @idf_name = 'in.idf'
    @osm_name = 'in.osm'
    @osw_name = 'out.osw'
    @epw_path = 'in.epw'
    @workflow = OpenStudio::WorkflowJSON.new
    @workflow.addMeasurePath(measures_folder)
    @run_cli_verbose = true
    @os_measures = []
    @ep_measures = []
    @report_measures = []
  end

  def set_run_dir(run_dir: "#{Dir.pwd}/Run")
    puts "set run folder to #{run_dir}"
    @run_dir = run_dir
    @sql_path = OpenStudio::Path.new("#{@run_dir}/run/eplusout.sql")
    return self
  end

  def add_os_measure(measure)
    @os_measures << measure
  end

  def add_ep_measure(measure)
    @ep_measures << measure
  end

  def add_reporting_measure(measure)
    @report_measures << measure
    return self
  end

  def add_measures_to_workflow
    unless @os_measures.empty?
      measure_type = OpenStudio::MeasureType.new("ModelMeasure")
      @workflow.setMeasureSteps(measure_type, @os_measures)
    end
    unless @ep_measures.empty?
      measure_type = OpenStudio::MeasureType.new("EnergyPlusMeasure")
      @workflow.setMeasureSteps(measure_type, @ep_measures)
    end
    unless @report_measures.empty?
      measure_type = OpenStudio::MeasureType.new("ReportingMeasure")
      @workflow.setMeasureSteps(measure_type, @report_measures)
    end
    @workflow
    return self
  end

  def add_btap_create_necb_prototype_building_measure(building_type:, epw_file:, template:, primary_heating_fuel:)
    os_measure_type = OpenStudio::MeasureType.new("ModelMeasure")
    create_prototype_measure = OpenStudio::MeasureStep.new("btap_create_necb_prototype_building")
    create_prototype_measure.setName("btap_create_necb_prototype_building")
    create_prototype_measure.setArgument('building_type', building_type)
    create_prototype_measure.setArgument('epw_file', epw_file)
    create_prototype_measure.setArgument('template', template)
    create_prototype_measure.setArgument('primary_heating_fuel', primary_heating_fuel)
    @os_measures << create_prototype_measure
  end


  def add_btap_results_measure
    reporting_measure_type = OpenStudio::MeasureType.new("ReportingMeasure")
    btap_results = OpenStudio::MeasureStep.new("btap_results")
    btap_results.setName("btap_results")
    btap_results.setArgument('generate_hourly_report', 'false')
    btap_results.setArgument('output_diet', false)
    btap_results.setArgument('envelope_costing', true)
    btap_results.setArgument('lighting_costing', true)
    btap_results.setArgument('boilers_costing', true)
    btap_results.setArgument('chillers_costing', true)
    btap_results.setArgument('cooling_towers_costing', true)
    btap_results.setArgument('shw_costing', true)
    btap_results.setArgument('ventilation_costing', true)
    btap_results.setArgument('zone_system_costing', true)
    @report_measures << btap_results
  end


  def run_command(command:)
    stdout_str, stderr_str, status = Open3.capture3({}, command)
    if status.success?
      puts "Command completed successfully"
      puts "stdout: #{stdout_str}"
      puts "stderr: #{stderr_str}"
      return true
    else
      puts "Error running command: '#{command}'"
      puts "stdout: #{stdout_str}"
      puts "stderr: #{stderr_str}"
      return false
    end
  end

  def run_workflow(postprocess_only: nil, osw_path:)
    #command to run workflow
    os_ruby_cli = "bundle exec ruby #{File.join(File.dirname(OpenStudio.getOpenStudioCLI.to_s), '..', 'Ruby', 'openstudio_cli.rb')}"
    extra_args = ' --postprocess_only ' if postprocess_only == true
    cmd = "#{os_ruby_cli} run #{extra_args} --debug --workflow \"#{osw_path}\""
    puts "running cli command: #{cmd}"
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "running cli command: #{cmd}")
    self.run_command(command: cmd)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished cli run.')
    #Ensure items are written to disk.
    sleep 3
    return true
  end
end
