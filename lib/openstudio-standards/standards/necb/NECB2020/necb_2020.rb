# This class holds methods that apply NECB2020 rules.

# Notes for adding new version of NECB:
#  Essentially all you need to do is copy this file to a new folder and update the class name (only the initialize and load_standards_database_new methods are required,
#  everything else will be inherited. Only add methods, json files and other rb files if the content/functionality has changed. Do not forget to update the class name in the rb files!
#  The spacetypes and led lighting json files are required (in the data folder) as they have the NECB version hardcoded (which requires updating).
#  However there are a few other files to update:
#  1) NECB2011/necb_2011.rb:determine_spacetype_vintage method has an array of available versions of NECB hardcoded. Add the new one.
#  2) common/space_type_upgrade_map.json needs all the space types for the new version defined (386 in NECB 2020).
#  3) Add references to the rb files in this folder to openstudio_standards.rb

# @ref [References::NECB2020]
class NECB2020 < NECB2017
  @template = self.new.class.name # rubocop:disable Style/ClassVars
  register_standard(@template)

  def initialize
    super()
    @template = self.class.name
    @standards_data = self.load_standards_database_new()
    self.corrupt_standards_database()
  end

  def load_standards_database_new
    # load NECB2020 data.
    super()

    if __dir__[0] == ':' # Running from OpenStudio CLI
      embedded_files_relative('data/', /.*\.json/).each do |file|
        data = JSON.parse(EmbeddedScripting.getFileAsString(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        elsif !data['constants'].nil?
          @standards_data['constants'] = [*@standards_data['constants'], *data['constants']].to_h
        elsif !data['constants'].nil?
          @standards_data['formulas'] = [*@standards_data['formulas'], *data['formulas']].to_h
        end
      end
    else
      files = Dir.glob("#{File.dirname(__FILE__)}/data/*.json").select { |e| File.file? e }
      files.each do |file|
        data = JSON.parse(File.read(file))
        if !data['tables'].nil?
          @standards_data['tables'] = [*@standards_data['tables'], *data['tables']].to_h
        elsif !data['constants'].nil?
          @standards_data['constants'] = [*@standards_data['constants'], *data['constants']].to_h
        elsif !data['formulas'].nil?
          @standards_data['formulas'] = [*@standards_data['formulas'], *data['formulas']].to_h
        end
      end
    end
    # Write test report file.
    # Write database to file.
    # File.open(File.join(File.dirname(__FILE__), '..', 'NECB2017.json'), 'w') {|f| f.write(JSON.pretty_generate(@standards_data))}
    return @standards_data
  end

  # Set the infiltration rate for this space to include
  # the impact of air leakage requirements in the standard.
  #
  # Note that this is significantly different for NECB 2020 compared to previous codes.
  #  The value is now specified at 75 Pa normalised by entire building surface area (previously 5 Pa
  #  and for above grade surfaces only). Need to convert to 5 Pa and for the different surface area.
  #
  # @return [Double] true if successful, false if not
  # @todo handle doors and vestibules
  def space_apply_infiltration_rate(space)

    # Remove infiltration rates set at the space type.
    infiltration_data = @standards_data['infiltration']
    unless space.spaceType.empty?
      space.spaceType.get.spaceInfiltrationDesignFlowRates.each(&:remove)
    end
    # Remove infiltration rates set at the space object.
    space.spaceInfiltrationDesignFlowRates.each(&:remove)

    # Don't create an object if there is no exterior wall area.
    exterior_wall_and_roof_and_subsurface_area = OpenstudioStandards::Geometry.space_get_exterior_wall_and_subsurface_and_roof_area(space)
    if exterior_wall_and_roof_and_subsurface_area <= 0.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.Model', "For #{template}, no exterior wall area was found in #{space.name}; no infiltration will be added.")
      return true
    end

    # Calculate total area of above and below grade envelope area in the entire model.
    totalAreaBuildingEnvelope = 0.0
    totalAboveGradeArea = 0.0

	space.model.getSpaces.each do |modelspace|
	  multiplier = modelspace.multiplier
	  modelspace.surfaces.each do |surface|
	    if surface.outsideBoundaryCondition == "Outdoors" then
		  area = surface.grossArea * multiplier
          totalAreaBuildingEnvelope += area
          totalAboveGradeArea += area
		elsif surface.outsideBoundaryCondition == "Ground" then
		  area = surface.grossArea * multiplier
          totalAreaBuildingEnvelope += area
		end
	  end
	end

	# Get infiltration rate from standards and convert to value at 5 Pa applied to all above grade surfaces.
    infil_75Pa_all_surf = self.get_standards_constant('infiltration_rate_m3_per_s_per_m2')
    infil_5Pa_above_grade = infil_75Pa_all_surf * ((5.0 / 75.0) ** (0.6)) * totalAreaBuildingEnvelope / totalAboveGradeArea
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.Standards.Space', "For #{space.name}, adj infil = #{infil_5Pa_above_grade.round(5)} m^3/s*m^2.")

    # Get any infiltration schedule already assigned to this space or its space type
    # If not, the always on schedule will be applied.
    infil_sch = nil
    unless space.spaceInfiltrationDesignFlowRates.empty?
      old_infil = space.spaceInfiltrationDesignFlowRates[0]
      if old_infil.schedule.is_initialized
        infil_sch = old_infil.schedule.get
      end
    end

    if infil_sch.nil? && space.spaceType.is_initialized
      space_type = space.spaceType.get
      unless space_type.spaceInfiltrationDesignFlowRates.empty?
        old_infil = space_type.spaceInfiltrationDesignFlowRates[0]
        if old_infil.schedule.is_initialized
          infil_sch = old_infil.schedule.get
        end
      end
    end

    if infil_sch.nil?
      infil_sch = space.model.alwaysOnDiscreteSchedule
    end

    # Create an infiltration rate object for this space.
    infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space.model)
    infiltration.setName("#{space.name} Infiltration")
    infiltration.setFlowperExteriorSurfaceArea(infil_5Pa_above_grade)
    infiltration.setSchedule(infil_sch)
    infiltration.setConstantTermCoefficient(self.get_standards_constant('infiltration_constant_term_coefficient'))
    infiltration.setTemperatureTermCoefficient(self.get_standards_constant('infiltration_constant_term_coefficient'))
    infiltration.setVelocityTermCoefficient(self.get_standards_constant('infiltration_velocity_term_coefficient'))
    infiltration.setVelocitySquaredTermCoefficient(self.get_standards_constant('infiltration_velocity_squared_term_coefficient'))
    infiltration.setSpace(space)
    return true
  end

  # Generate NECB 2020 Performance Path compliance models (proposed and reference)
  #
  # This method implements the NECB 2020 Section 8.4 Performance Path by:
  # 1. Documenting the proposed building characteristics per Section 8.4.3
  # 2. Generating a reference building with prescriptive requirements per Section 8.4.4
  # 3. Optionally running simulations and validating compliance per Section 8.4.1
  # 4. Generating detailed HTML compliance reports with before/after logging
  #
  # @param proposed_model [OpenStudio::Model::Model] The proposed building model (input, not modified)
  # @param epw_file [String] Path to EPW weather file
  # @param sizing_run_dir [String] Directory for sizing runs (default: current directory)
  # @param output_dir [String] Directory for output files (default: current directory)
  # @param run_simulations [Boolean] Whether to run EnergyPlus simulations (default: false)
  # @param html_report [Boolean] Whether to generate HTML report (default: true)
  # @return [Hash] Results hash containing:
  #   - :proposed_model - The input proposed building model (unmodified)
  #   - :reference_model - Generated reference building model
  #   - :compliance_log - Structured compliance logger with all changes
  #   - :proposed_model_path - Path to saved proposed model copy
  #   - :reference_model_path - Path to saved reference model
  #   - :html_report_path - Path to HTML compliance report (if html_report: true)
  #   - :compliance_result - Compliance validation results (if run_simulations: true)
  #   - :building_energy_target - Building energy target from reference (if run_simulations: true)
  #   - :climate_zone - Climate zone for the location
  #   - :hdd18 - Heating degree days (base 18°C)
  #
  # @example Basic usage without simulations
  #   standard = Standard.build('NECB2020')
  #   result = standard.model_create_necb_2020_performance_compliance(
  #     proposed_model: model,
  #     epw_file: 'path/to/weather.epw'
  #   )
  #   puts "Reference model: #{result[:reference_model_path]}"
  #   puts "HTML report: #{result[:html_report_path]}"
  #
  # @example With simulations and compliance validation
  #   result = standard.model_create_necb_2020_performance_compliance(
  #     proposed_model: model,
  #     epw_file: 'path/to/weather.epw',
  #     run_simulations: true
  #   )
  #   if result[:compliance_result][:compliant]
  #     puts "Building is compliant!"
  #   end
  #
  def model_create_necb_2020_performance_compliance(proposed_model:,
                                                     epw_file:,
                                                     sizing_run_dir: Dir.pwd,
                                                     output_dir: Dir.pwd,
                                                     run_simulations: false,
                                                     html_report: true)

    # Load required modules
    require_relative 'performance_compliance/compliance_logger'
    require_relative 'performance_compliance/proposed_builder'
    require_relative 'performance_compliance/reference_builder'
    require_relative 'performance_compliance/reference_hvac_selector'
    require_relative 'performance_compliance/compliance_validator'
    require_relative 'performance_compliance/compliance_report'

    # Initialize logger
    logger = OpenstudioStandards::NECB2020::ComplianceLogger.new

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                       'Starting NECB 2020 Performance Path compliance generation')

    # Get climate information
    hdd18 = get_necb_hdd18(model: proposed_model)
    climate_zone = get_climate_zone_name(hdd18)

    logger.log_article(
      article: '8.4.1.1',
      action: 'Initialized NECB 2020 Performance Path compliance',
      details: {
        climate_zone: climate_zone,
        hdd18: hdd18.round(0),
        epw_file: File.basename(epw_file)
      }
    )

    # Step 1: Document proposed building per Section 8.4.3
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                       'Documenting proposed building characteristics (Section 8.4.3)')

    proposed_builder = OpenstudioStandards::NECB2020::ProposedBuilder.new(proposed_model, logger)
    proposed_characteristics = proposed_builder.document_all_characteristics

    # Step 2: Generate reference building per Section 8.4.4
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                       'Generating reference building (Section 8.4.4)')

    reference_builder = OpenstudioStandards::NECB2020::ReferenceBuilder.new(
      self, proposed_model, logger, epw_file
    )
    reference_model = reference_builder.generate_reference_building(sizing_run_dir: sizing_run_dir)

    # Step 3: Save models
    proposed_model_path = File.join(output_dir, 'proposed_building.osm')
    reference_model_path = File.join(output_dir, 'reference_building.osm')

    BTAP::FileIO.save_osm(proposed_model, proposed_model_path)
    BTAP::FileIO.save_osm(reference_model, reference_model_path)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                       "Saved proposed model to: #{proposed_model_path}")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                       "Saved reference model to: #{reference_model_path}")

    # Prepare results
    results = {
      proposed_model: proposed_model,
      reference_model: reference_model,
      compliance_log: logger,
      proposed_model_path: proposed_model_path,
      reference_model_path: reference_model_path,
      climate_zone: climate_zone,
      hdd18: hdd18,
      epw_file: epw_file
    }

    # Step 4: Optional - Run simulations and validate compliance
    if run_simulations
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                         'Running simulations and validating compliance (Section 8.4.1)')

      # Run proposed building simulation
      proposed_sql_path = run_simulation_and_get_sql(
        proposed_model,
        epw_file,
        File.join(output_dir, 'proposed_sim')
      )

      # Run reference building simulation
      reference_sql_path = run_simulation_and_get_sql(
        reference_model,
        epw_file,
        File.join(output_dir, 'reference_sim')
      )

      if proposed_sql_path && reference_sql_path
        # Load SQL files
        proposed_sql = OpenStudio::SqlFile.new(proposed_sql_path)
        reference_sql = OpenStudio::SqlFile.new(reference_sql_path)

        # Validate compliance
        validator = OpenstudioStandards::NECB2020::ComplianceValidator.new(logger)
        compliance_result = validator.validate_compliance(proposed_sql, reference_sql)

        results[:compliance_result] = compliance_result
        results[:building_energy_target] = compliance_result[:annual_energy][:building_energy_target_gj]

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                           "Compliance: #{compliance_result[:compliant] ? 'PASS' : 'FAIL'}")
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.NECB2020',
                           'Simulations failed - compliance validation not performed')
      end
    end

    # Step 5: Generate HTML report
    if html_report
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                         'Generating HTML compliance report')

      report_data = {
        climate_zone: climate_zone,
        hdd18: hdd18,
        epw_file: epw_file,
        compliance_result: results[:compliance_result]
      }

      report_generator = OpenstudioStandards::NECB2020::ComplianceReportGenerator.new(logger, report_data)
      report_path = File.join(output_dir, 'necb_2020_performance_compliance_report.html')
      report_generator.save_report(report_path)

      results[:html_report_path] = report_path

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                         "Saved HTML report to: #{report_path}")
    end

    # Final summary
    summary = logger.get_summary
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.NECB2020',
                       "Compliance generation complete. Total entries: #{summary[:total_entries]}, " \
                       "Passed: #{summary[:passed]}, Failed: #{summary[:failed]}")

    results
  end

  private

  # Run EnergyPlus simulation and return SQL file path
  #
  # @param model [OpenStudio::Model::Model] Model to simulate
  # @param epw_file [String] Weather file path
  # @param run_dir [String] Directory for simulation files
  # @return [String, nil] Path to SQL file, or nil if simulation failed
  def run_simulation_and_get_sql(model, epw_file, run_dir)
    # Create run directory
    FileUtils.mkdir_p(run_dir)

    # Save model
    osm_path = File.join(run_dir, 'in.osm')
    BTAP::FileIO.save_osm(model, osm_path)

    # Run simulation
    sql_path = model_run_simulation_and_log_errors(model, run_dir)

    return sql_path if sql_path

    nil
  rescue StandardError => e
    OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.NECB2020',
                       "Simulation failed: #{e.message}")
    nil
  end
end
