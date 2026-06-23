# rubocop:disable Metrics/ClassLength
class ACM179dASHRAE9012007
  def __model_get_primary_building_type(model)
    building_types = {}

    building = model.getBuilding
    building_level_bt = nil
    if building.standardsBuildingType.is_initialized
      building_level_bt = building.standardsBuildingType.get
      # Turns "SmallOffice" in "Office"
      building_level_bt = model_get_lookup_name(building_level_bt)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "found Building level standardsBuildingType = '#{building_level_bt}'")
    end

    model.getSpaceTypes.sort.each do |space_type|
      # populate hash of building types
      if !space_type.standardsBuildingType.is_initialized
        next
      end

      bldg_type_ori = space_type.standardsBuildingType.get
      # Turns "SmallOffice" in "Office". To ensure we aggregate properly
      bldg_type = model_get_lookup_name(bldg_type_ori)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "found building type for Space Type '#{space_type.name}' = '#{bldg_type}'")
      if bldg_type_ori != bldg_type
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Space Type '#{space_type.name}' has actual Building Type '#{bldg_type_ori}' but sanitizing as '#{bldg_type}' for aggregation")
      end
      if building_types.key?(bldg_type)
        building_types[bldg_type] += space_type.floorArea
      else
        building_types[bldg_type] = space_type.floorArea
      end
    end

    if building_types.empty?
      if building_level_bt.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot identify a single building type in model, none of your #{model.getSpaceTypes.size} SpaceTypes have a standardsBuildingType assigned and neither does the Building")
        raise 'No Primary Building Type found'
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "No area determination based on space types found, using Building level standardsBuildingType = '#{building_level_bt}'")
        return building_level_bt
      end
    end

    space_type_level_bt = building_types.max_by { |_, v| v }.first
    if !building_level_bt.nil?
      if building_level_bt != space_type_level_bt
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "The Building has standardsBuildingType '#{building_level_bt}' while the area determination based on space types has '#{space_type_level_bt}'. Preferring the Space Type one")
      end
      return space_type_level_bt
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Building doesn't have a standardsBuildingType, using the area determination based on space types = '#{space_type_level_bt}'")
    return space_type_level_bt
  end

  # This starts by always using model_get_lookup_name to sanitize the names
  # Meaning 'RetailStripmall' is changed to 'StripMall' for eg
  # If remap_office is false, even if you have 'SmallOffice' it returns
  # 'Office'
  # It remap_office is true, it returns 'SmallOffice', 'MediumOffice' or 'LargeOffice'
  def model_get_primary_building_type(model, remap_office: false, remap_retail: false)
    # Maybe this is a premature optimization, but memoize the computation
    @primary_building_types_memoized ||= {}
    # TODO: this will work if you pass the same model. But if you do sp.model
    # then it changes everytime. Need to figure out a way to check if it points
    # to the same model or not, or remove the memoization
    @primary_building_types_memoized[model] ||= __model_get_primary_building_type(model)

    building_type = @primary_building_types_memoized[model]
    if remap_office && building_type == 'Office'
      floor_area_m2 = model.getBuilding.floorArea
      building_type = model_remap_office(model, floor_area_m2)
    end
    if remap_retail
      if building_type == 'StripMall'
        return 'RetailStripmall'
      elsif building_type == 'Retail'
        return 'RetailStandalone'
      end
    end
    return building_type
  end

  # **NOTE**: Patched to check also number of floors
  # remap office to one of the prototype buildings
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param floor_area [Double] floor area (m^2)
  # @return [String] SmallOffice, MediumOffice, LargeOffice
  def model_remap_office(model, floor_area)
    floor_area_sqft = OpenStudio.convert(floor_area, 'm^2', 'ft^2').get
    num_floors = model.getBuilding.buildingStories.size
    if floor_area_sqft < 25_000
      return 'SmallOffice' if num_floors <= 3

      return 'MediumOffice'

    elsif floor_area_sqft < 150_000
      return 'MediumOffice' if num_floors <= 5

      return 'LargeOffice'

    else
      return 'LargeOffice'
    end
  end

  # Patched to prefer the space area method above instead of just relying on
  # Building object
  def model_get_building_properties(model, remap_office: true)
    # get climate zone from model
    climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)

    # get building type from model
    building_type = model_get_primary_building_type(model, remap_office: remap_office)

    # get standards template
    if model.getBuilding.standardsTemplate.is_initialized
      standards_template = model.getBuilding.standardsTemplate.get
    end

    results = {}
    results['climate_zone'] = climate_zone
    results['building_type'] = building_type
    results['standards_template'] = standards_template

    return results
  end

  def model_prm_baseline_system_number(_model, _climate_zone, area_type, _fuel_type, area_ft2, num_stories, custom)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.prm', '179d: Heat Storage area applied as 90.1-2007 with addenda dn')
    sys_num = nil

    # Set the area limit
    limit_ft2 = 25_000

    # Customization for Xcel EDA.
    # No special retail category
    # for regular 90.1-2010.
    if custom != 'Xcel Energy CO EDA' && (area_type == 'retail')
      area_type = 'nonresidential'
    end

    case area_type
    when 'residential'
      sys_num = '1_or_2'
    when 'nonresidential'
      # nonresidential and 3 floors or less and <25,000 ft2
      if num_stories <= 3 && area_ft2 < limit_ft2
        sys_num = '3_or_4'
      # nonresidential and 4 or 5 floors or 5 floors or less and 25,000 ft2 to 150,000 ft2
      elsif ((num_stories == 4 || num_stories == 5) && area_ft2 < limit_ft2) || (num_stories <= 5 && (area_ft2 >= limit_ft2 && area_ft2 <= 150_000))
        sys_num = '5_or_6'
      # nonresidential and more than 5 floors or >150,000 ft2
      elsif num_stories >= 5 || area_ft2 > 150_000
        sys_num = '7_or_8'
      end
    when 'heatedonly'
      sys_num = '9_or_10'
    when 'retail'
      # Should only be hit by Xcel EDA
      sys_num = '3_or_4'
    end

    return sys_num
  end

  # Returns standards data for selected model
  # This will check the building primary type instead
  #
  # @param model [OpenStudio::Model::Model] the model
  # @return [hash] hash of internal loads for different load types
  def model_get_standards_data(model, throw_if_not_found: false)
    # This returns 'Office' for eg
    standards_building_type = model_get_primary_building_type(model, remap_office: false)

    # populate search hash
    search_criteria = {
      'template' => template,
      'building_type' => standards_building_type,
      'space_type' => whole_building_space_type_name(model, standards_building_type)
    }

    # lookup space type properties
    space_type_properties = model_find_object(standards_data['space_types'], search_criteria)

    if space_type_properties.nil?
      msg = "Space type properties lookup failed: #{search_criteria}."
      if throw_if_not_found
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SpaceType', msg)
        raise msg
      end
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', msg)
      space_type_properties = {}
    end

    return space_type_properties
  end

  HVAC_AVAILABILITY_SCHEDULE_MAP = {
    # This is a map of HVAC Type to An array of methods
    # Type => [[:getter, :setter], [:getter, :setter]]
    'AirLoopHVAC' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardConvectiveElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardRadiantConvectiveElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACBaseboardRadiantConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACCoolingPanelRadiantConvectiveWater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACDehumidifierDX' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACEnergyRecoveryVentilator' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACFourPipeFanCoil' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACHighTemperatureRadiant' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACIdealLoadsAirSystem' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTemperatureRadiantElectric' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTempRadiantConstFlow' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACLowTempRadiantVarFlow' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACPackagedTerminalAirConditioner' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACPackagedTerminalHeatPump' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACUnitHeater' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACUnitVentilator' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'ZoneHVACWaterToAirHeatPump' => [[:availabilitySchedule, :setAvailabilitySchedule]],
    'AirLoopHVACUnitarySystem' => [
      # TODO
      # [:availabilitySchedule, :setAvailabilitySchedule],
      [:supplyAirFanOperatingModeSchedule, :setSupplyAirFanOperatingModeSchedule]
    ]
  }.freeze

  def model_apply_acm_hvac_availability_schedule(model)
    data = model_get_standards_data(model, throw_if_not_found: true)
    acm_fan_sch_name = data['hvac_operation_schedule']
    acm_fan_sch = nil

    count_availability = 0
    HVAC_AVAILABILITY_SCHEDULE_MAP.each do |hvac_type, methods|
      objects = model.send("get#{hvac_type}s")
      next if objects.empty?

      if acm_fan_sch.nil?
        acm_fan_sch = model_add_schedule(model, acm_fan_sch_name)
        model.getBuilding.additionalProperties.setFeature('acm_fan_sch', acm_fan_sch_name)
      end

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model_apply_acm_hvac_availability_schedule', "HVAC - found #{objects.size} #{hvac_type} object(s)")
      objects.each do |obj|
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model_apply_acm_hvac_availability_schedule', "HVAC - overriding availability schedule in '#{obj.nameString}' to #{acm_fan_sch.nameString}")
        methods.each do |_getter, setter|
          raise "HVAC_AVAILABILITY_SCHEDULE_MAP is out of date, #{obj.briefDescription} does not respond to #{setter}" unless obj.respond_to?(setter)

          ret = obj.send(setter, acm_fan_sch)
          if !ret
            OpenStudio.logFree(OpenStudio::Warning, 'openstudio.model_apply_acm_hvac_availability_schedule', "Failed to apply availability schedule via #{setter} for #{obj.briefDescription}")
          end
        end
        count_availability += 1
      end
    end

    # Also sync the occupied schedule to the heated-only zone " Ventilation"
    # ZoneVentilationDesignFlowRate objects. These are created before this
    # method runs (during HVAC setup), so they initially inherit
    # alwaysOnDiscreteSchedule from the unit heater. Keep the sync limited to
    # standalone zones so it does not disturb zone ventilation used by other
    # prototypes.
    ventilation_zvs = model.getZoneVentilationDesignFlowRates.select do |zv|
      next false unless zv.nameString.end_with?(' Ventilation')
      next false unless zv.thermalZone.is_initialized

      zv.thermalZone.get.airLoopHVAC.empty?
    end
    unless ventilation_zvs.empty?
      if acm_fan_sch.nil?
        acm_fan_sch = model_add_schedule(model, acm_fan_sch_name)
        model.getBuilding.additionalProperties.setFeature('acm_fan_sch', acm_fan_sch_name)
      end
      ventilation_zvs.each do |zv|
        zv.setSchedule(acm_fan_sch)
        count_availability += 1
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model_apply_acm_hvac_availability_schedule', "Applied availablity schedule '#{acm_fan_sch_name}' to #{count_availability} objects.")
    return count_availability > 0
  end

  # This function checks whether it is required to adjust the window to wall ratio based on the model WWR and wwr limit.
  # @param wwr_limit [Float] return wwr_limit
  # @param wwr_list [Array] list of wwr of zone conditioning category in a building area type category - residential, nonresidential and semiheated
  # @return require_adjustment [Boolean] True, require adjustment, false not require adjustment.
  # NOTE: 179D override so that we adjust the WWR DOWN TO 40%, which is the opposite of the base method (ashrae_90_1_prm.Model.rb does both, returns always true)
  def model_does_require_wwr_adjustment?(wwr_limit, wwr_list)
    require_adjustment = false
    wwr_list.each do |wwr|
      require_adjustment = true if wwr > wwr_limit
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "WWR check:#{wwr} - wwr_limit#{wwr_limit} - require_adjustment: #{require_adjustment}")
    end
    return require_adjustment
  end

  # Creates a Performance Rating Method (aka Appendix G aka LEED) baseline building model
  # Method used for 90.1-2013 and prior
  # @param model [OpenStudio::Model::Model] User specified OpenStudio model
  # @param building_type [String] the building type
  # @param climate_zone [String] the climate zone
  # @param custom [String] the custom logic that will be applied during baseline creation.  Valid choices are 'Xcel Energy CO EDA' or '90.1-2007 with addenda dn'.
  #   If nothing is specified, no custom logic will be applied; the process will follow the template logic explicitly.
  # @param sizing_run_dir [String] the directory where the sizing runs will be performed
  # @param debug [Boolean] if true, will report out more detailed debugging output
  # @param baseline_179d [Boolean] NOTE: 179D addition, True for the baseline, false for the proposed
  # rubocop:disable Metrics/ParameterLists, Style/OptionalBooleanParameter
  def model_create_prm_baseline_building(model, building_type, climate_zone, custom = nil, sizing_run_dir = Dir.pwd, debug = false, baseline_179d = true, unmet_load_hours_check = false)
    model_create_prm_any_baseline_building(model, building_type, climate_zone, 'All others', 'All others', 'All others', false, false, custom, sizing_run_dir, false, unmet_load_hours_check, debug, baseline_179d)
  end
  # rubocop:enable Metrics/ParameterLists, Style/OptionalBooleanParameter

  # Creates a Performance Rating Method (aka Appendix G aka LEED) baseline building model
  # based on the inputs currently in the model.
  #
  # @note Per 90.1, the Performance Rating Method "does NOT offer an alternative compliance path for minimum standard compliance."
  # This means you can't use this method for code compliance to get a permit.
  # @param user_model [OpenStudio::Model::Model] User specified OpenStudio model
  # @param building_type [String] the building type
  # @param climate_zone [String] the climate zone
  # @param hvac_building_type [String] the building type for baseline HVAC system determination (90.1-2016 and onward)
  # @param wwr_building_type [String] the building type for baseline WWR determination (90.1-2016 and onward)
  # @param swh_building_type [String] the building type for baseline SWH determination (90.1-2016 and onward)
  # @param model_deep_copy [Boolean] indicate if the baseline model is created based on a deep copy of the user specified model
  # @param custom [String] the custom logic that will be applied during baseline creation.  Valid choices are 'Xcel Energy CO EDA' or '90.1-2007 with addenda dn'.
  #   If nothing is specified, no custom logic will be applied; the process will follow the template logic explicitly.
  # @param sizing_run_dir [String] the directory where the sizing runs will be performed
  # @param run_all_orients [Boolean] indicate weather a baseline model should be created for all 4 orientations: same as user model, +90 deg, +180 deg, +270 deg
  # @param debug [Boolean] If true, will report out more detailed debugging output
  # @return [Boolean] returns true if successful, false if not
  # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity, Style/OptionalBooleanParameter
  def model_create_prm_any_baseline_building(user_model, building_type, climate_zone, hvac_building_type = 'All others', wwr_building_type = 'All others', swh_building_type = 'All others', model_deep_copy = false, create_proposed_model = false, custom = nil, sizing_run_dir = Dir.pwd, run_all_orients = false, unmet_load_hours_check = true, debug = false, baseline_179d = true)
    args = {
      # "user_model"   => user_model,
      'building_type' => building_type,
      'climate_zone' => climate_zone,
      'hvac_building_type' => hvac_building_type,
      'wwr_building_type' => wwr_building_type,
      'swh_building_type' => swh_building_type,
      'model_deep_copy' => model_deep_copy,
      'create_proposed_model' => create_proposed_model,
      'custom' => custom,
      'sizing_run_dir' => sizing_run_dir,
      'run_all_orients' => run_all_orients,
      'unmet_load_hours_check' => unmet_load_hours_check,
      'debug' => debug,
      'baseline_179d' => baseline_179d
    }
    if debug
      args.each { |k, v| OpenStudio.logFree(OpenStudio::Info, 'openstudio.prm.179d', "179d - model_create_prm_any_baseline_building inputs: #{k} - #{v}") }
    end

    # User data process
    # bldg_type_hvac_zone_hash could be an empty hash if all zones in the models are unconditioned
    # TODO - move this portion to the top of the function
    bldg_type_hvac_zone_hash = {}
    handle_user_input_data(user_model, climate_zone, sizing_run_dir, hvac_building_type, wwr_building_type, swh_building_type, bldg_type_hvac_zone_hash)

    # enforce the user model to be a non-leap year, defaulting to 2009 if the model year is a leap year
    if user_model.yearDescription.is_initialized
      year_description = user_model.yearDescription.get
      if year_description.isLeapYear
        OpenStudio.logFree(OpenStudio::Warn, 'prm.log',
                           "The user model year #{year_description.assumedYear} is a leap year. Changing to 2009, a non-leap year, as required by PRM guidelines.")
        year_description.setCalendarYear(2009)
      end
    end

    if create_proposed_model
      # Perform a user model design day run only to make sure
      # that the user model is valid, i.e. can run without major
      # errors
      if !model_run_sizing_run(user_model, "#{sizing_run_dir}/USER-SR")
        OpenStudio.logFree(OpenStudio::Warn, 'prm.log',
                           "The user model is not a valid OpenStudio model. Baseline and proposed model(s) won't be created.")
        prm_raise(false,
                  sizing_run_dir,
                  "The user model is not a valid OpenStudio model. Baseline and proposed model(s) won't be created.")
      end

      # Check if proposed HVAC system is autosized
      if model_is_hvac_autosized(user_model)
        OpenStudio.logFree(OpenStudio::Warn, 'prm.log',
                           "The user model's HVAC system is partly autosized.")
      end

      # Generate proposed model from the user-provided model
      proposed_model = model_create_prm_proposed_building(user_model)
    end

    # Check proposed model unmet load hours
    if unmet_load_hours_check
      # Set proposed model export data in json format
      OpenStudioStandards::RulesetChecking.export_json_output(proposed_model)

      # Run user model; need annual simulation to get unmet load hours
      if model_run_simulation_and_log_errors(proposed_model, run_dir = "#{sizing_run_dir}/PROP")
        umlh = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(proposed_model)
        if umlh > 300
          OpenStudio.logFree(OpenStudio::Warn, 'prm.log',
                             "Proposed model unmet load hours (#{umlh}) exceed 300. Baseline model(s) won't be created.")
          prm_raise(false,
                    sizing_run_dir,
                    "Proposed model unmet load hours exceed 300. Baseline model(s) won't be created.")
        end
      else
        OpenStudio.logFree(OpenStudio::Error, 'prm.log',
                           'Simulation failed. Check the model to make sure no severe errors.')
        prm_raise(false,
                  sizing_run_dir,
                  'Simulation on proposed model failed. Baseline generation is stopped.')
      end
    end
    if create_proposed_model
      # Make the run directory if it doesn't exist
      FileUtils.mkdir_p(sizing_run_dir)

      # Save proposed model
      proposed_model.save(OpenStudio::Path.new("#{sizing_run_dir}/proposed_final.osm"), true)
      forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      idf = forward_translator.translateModel(proposed_model)

      proposed_model.getSpaces.sort.each do |space|
        space_cond_type = space_conditioning_category(space)
        next if space_cond_type == 'Unconditioned'

        OpenStudioStandards::RulesetChecking.tag_spaces(idf, space)
      end
      idf_path = OpenStudio::Path.new("#{sizing_run_dir}/proposed_final.idf")
      idf.save(idf_path, true)

      # export to epjson
      OpenStudioStandards::RulesetChecking.export_epjson(proposed_model, sizing_run_dir, 'proposed_final')
    end

    # Define different orientation from original orientation
    # for each individual baseline models
    # Need to run proposed model sizing simulation if no sql data is available
    if debug
      pp "179d - bldg_type_hvac_zone_hash after handle_user_input_data: #{bldg_type_hvac_zone_hash.map { |k, v| "Key #{k} - Value: #{v}" }}"
    end

    degs_from_org = run_all_orientations(run_all_orients, user_model) ? [0, 90, 180, 270] : [0]

    # Create baseline model for each orientation
    degs_from_org.each do |degs|
      # New baseline model:
      # Starting point is the original proposed model
      # Create a deep copy of the user model if requested
      model = model_deep_copy ? BTAP::FileIO.deep_copy(user_model) : user_model
      model.getBuilding.setName("#{template}-#{building_type}-#{climate_zone} PRM baseline created: #{Time.new}")

      # Rotate building if requested,
      # Site shading isn't rotated
      model_rotate(model, degs) unless degs == 0
      # Perform a sizing run of the proposed model.
      #
      # Among others, one of the goal is to get individual
      # space load to determine each space's conditioning
      # type: conditioned, unconditioned, semiheated.
      if model_create_prm_baseline_building_requires_proposed_model_sizing_run(model)
        # Set up some special reports to be used for baseline system selection later
        # Zone return air flows
        # ! no need for 90.1-2007
        node_list = []
        var_name = 'System Node Standard Density Volume Flow Rate'
        frequency = 'hourly'
        model.getThermalZones.each do |zone|
          port_list = zone.returnPortList
          port_list_objects = port_list.modelObjects
          port_list_objects.each do |node|
            node_name = node.nameString
            node_list << node_name
            output = OpenStudio::Model::OutputVariable.new(var_name, model)
            output.setKeyValue(node_name)
            output.setReportingFrequency(frequency)
          end
        end

        # air loop relief air flows
        var_name = 'System Node Standard Density Volume Flow Rate'
        frequency = 'hourly'
        model.getAirLoopHVACs.sort.each do |air_loop_hvac|
          relief_node = air_loop_hvac.reliefAirNode.get
          output = OpenStudio::Model::OutputVariable.new(var_name, model)
          output.setKeyValue(relief_node.nameString)
          output.setReportingFrequency(frequency)
        end

        # Run the sizing run
        if model_run_sizing_run(model, "#{sizing_run_dir}/SR_PROP#{degs}") == false
          return false
        end

        # Set baseline model space conditioning category based on proposed model
        model.getSpaces.each do |space|
          # Get conditioning category at the space level
          space_conditioning_category = space_conditioning_category(space)

          # Set space conditioning category
          space.additionalProperties.setFeature('space_conditioning_category', space_conditioning_category)
        end

        # The following should be done after a sizing run of the proposed model
        # because the proposed model zone design air flow is needed
        model_identify_return_air_type(model)
      end
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prm.179d', '***179d === All non-HVAC alteration will be disabled***')
      # # Remove external shading devices
      # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Removing External Shading Devices ***')
      if baseline_179d
        model_remove_external_shading_devices(model)
      end

      # Reduce the WWR and SRR, if necessary
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Adjusting Window and Skylight Ratios ***')
        success, wwr_info = model_apply_prm_baseline_window_to_wall_ratio(model, climate_zone, wwr_building_type: wwr_building_type)
        model_apply_prm_baseline_skylight_to_roof_ratio(model)
      end

      # Assign building stories to spaces in the building where stories are not yet assigned.
      OpenstudioStandards::Geometry.model_assign_spaces_to_building_stories(model)

      # Modify the internal loads in each space type, keeping user-defined schedules.
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Changing Lighting Loads ***')
        model.getSpaceTypes.sort.each do |space_type|
          set_people = false
          set_lights = true
          set_electric_equipment = false
          set_gas_equipment = false
          set_ventilation = false
          # For PRM, it only applies lights for now.
          space_type_apply_internal_loads(space_type, set_people, set_lights, set_electric_equipment, set_gas_equipment, set_ventilation)
        end
      end

      # Modify the lighting schedule to handle lighting occupancy sensors
      # Modify the upper limit value of fractional schedule to avoid the fatal error caused by schedule value higher than 1
      # NOTE: 179D Disable: No light schedule change as it fixed wth ACM schedules
      # space_type_light_sch_change(model)

      # Modify electric equipment computer room schedule
      model.getSpaces.sort.each do |space|
        space_add_prm_computer_room_equipment_schedule(space)
      end

      # NOTE: 179D Disable: No exterior lighting schedule required
      # model_apply_baseline_exterior_lighting(model)

      # # Modify the elevator motor peak power
      # NOTE: 179D Disable: no need for 90.1-2007
      # model_add_prm_elevators(model)

      # Calculate infiltration as per 90.1 PRM rules
      model_apply_standard_infiltration(model, infiltration_rate: prm_building_envelope_infiltration_rate)

      # Apply user outdoor air specs as per 90.1 PRM rules exceptions
      model_apply_userdata_outdoor_air(model)

      # If any of the lights are missing schedules, assign an always-off schedule to those lights.
      # This is assumed to be the user's intent in the proposed model.
      model.getLightss.sort.each do |lights|
        if lights.schedule.empty?
          lights.setSchedule(model.alwaysOffDiscreteSchedule)
        end
      end

      # Run a sizing run to calculate VLT for layer-by-layer windows.
      # TODO check if not required for 90.1-2007 full appendix (only required for 90.1-2010)
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Adding Daylighting Controls ***')
        if model_create_prm_baseline_building_requires_vlt_sizing_run(model) && (model_run_sizing_run(model, "#{sizing_run_dir}/SRVLT") == false)
          return false
        end

        # Add or remove daylighting controls to each space
        # Add daylighting controls for 90.1-2013 and prior
        # Remove daylighting control for 90.1-PRM-2019 and onward
        # NOTE: check how daylighting required for 90.1-2007
        model.getSpaces.sort.each do |space|
          space_set_baseline_daylighting_controls(space, true, false)
        end
      end

      # Modify some of the construction types as necessary
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Baseline Constructions ***')
        model_apply_prm_construction_types(model)
      end

      # Get the groups of zones that define the baseline HVAC systems for later use.
      # This must be done before removing the HVAC systems because it requires knowledge of proposed HVAC fuels.
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Grouping Zones by Fuel Type and Occupancy Type ***')

      # 179d using local method with 90.1-2010
      # TODO test with warehouse and aparment midrise
      sys_groups = model_prm_baseline_system_groups(model, custom, bldg_type_hvac_zone_hash)

      # Also get hash of zoneName:boolean to record which zones have district heating, if any
      district_heat_zones = model_get_district_heating_zones(model)

      # Store occupancy and fan operation schedules for each zone before deleting HVAC objects
      # NOTE: 179D get ACM schedules directly without care
      zone_fan_scheds = get_fan_schedule_for_each_zone(model)

      # Set the construction properties of all the surfaces in the model
      if baseline_179d
        model_apply_standard_constructions(model, climate_zone, wwr_building_type: wwr_building_type, wwr_info: wwr_info)
      end

      # Update ground temperature profile (for F/C-factor construction objects)
      if baseline_179d
        model_update_ground_temperature_profile(model, climate_zone)
      end

      # Identify non-mechanically cooled systems if necessary
      model_identify_non_mechanically_cooled_systems(model)

      # Get supply, return, relief fan power for each air loop
      if model_get_fan_power_breakdown
        model.getAirLoopHVACs.sort.each do |air_loop|
          supply_fan_w = air_loop_hvac_get_supply_fan_power(air_loop)
          return_fan_w = air_loop_hvac_get_return_fan_power(air_loop)
          relief_fan_w = air_loop_hvac_get_relief_fan_power(air_loop)

          # Save fan power at the zone to determining
          # baseline fan power
          air_loop.thermalZones.sort.each do |zone|
            zone.additionalProperties.setFeature('supply_fan_w', supply_fan_w.to_f)
            zone.additionalProperties.setFeature('return_fan_w', return_fan_w.to_f)
            zone.additionalProperties.setFeature('relief_fan_w', relief_fan_w.to_f)
          end
        end
      end

      # Compute and marke DCV related information before deleting proposed model HVAC systems
      if baseline_179d
        model_evaluate_dcv_requirements(model)
      end

      # Get minimum and design outdoor airflow rates
      outdoor_airflow_rate_proposed_m_3_per_s = get_minimum_and_design_outdoor_airflow_rates(model, 'PROPOSED')

      # Remove all HVAC from model, excluding service water heating
      if baseline_179d
        model_remove_prm_hvac(model)
      end

      # Remove all EMS objects from the model
      model_remove_prm_ems_objects(model)
      # remove orphan object from DOE prototype
      if model.getMeterCustomDecrementByName('WIRED_INT_EQUIP').is_initialized
        model.getMeterCustomDecrementByName('WIRED_INT_EQUIP').get.remove
        pp 'Removed MeterCustomDecrement:WIRED_INT_EQUIP'
      end
      if model.getMeterCustomByName('Wired_LTG').is_initialized
        model.getMeterCustomByName('Wired_LTG').get.remove
        pp 'Removed MeterCustom:Wired_LTG'
      end
      model.getElectricLoadCenterTransformers.each do |ob|
        ob.remove
        pp "Removed Transformer #{ob.nameString}"
      end

      # Modify the service water heating loops per the baseline rules
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Cleaning up Service Water Heating Loops ***')
        model_apply_baseline_swh_loops(model, building_type, swh_building_type)
      end

      # system_type string
      prm_system_types = []

      # Determine the baseline HVAC system type for each of the groups of zones and add that system type.
      if baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Adding Baseline HVAC Systems ***')

        air_loop_name_array = []
        sys_groups.each_with_index do |sys_group, i|
          ## add data
          sys_group.each do |k, v|
            if k == 'zones'
              pp "179d - system_group #{i}: #{k} - #{v.map(&:nameString).join(':')}"
            else
              pp "179d - system_group #{i}: #{k} - #{v}"
            end
          end
          # Determine the primary baseline system type
          system_type = model_prm_baseline_system_type(model, climate_zone, sys_group, custom, hvac_building_type, district_heat_zones)
          # system_type --> ["PSZ_AC", "NaturalGas", nil, "Electricity"]
          # system_type[0] = "PTHP" ## force system type
          # system_type[0] = "PVAV_Reheat" ## force system type
          # system_type[0] = "VAV_PFP_Boxes" ## force system type
          # system_type[0] = "Gas_Furnace" ## force system type
          # system_type[0] = "Electric_Furnace" ## force system type
          prm_system_types << system_type
          system_str = system_type.zip(['type', 'central_heating_fuel', 'zone_heating_fuel', 'cooling_fuel']).map { |v, k| "#{k} => #{v}" }.join("\n")
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "179d - system_type: #{system_str}")

          sys_group['zones'].sort.each_slice(5) do |zone_list|
            zone_names = []
            zone_list.each do |zone|
              zone_names << zone.name.get.to_s
            end
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{zone_names.join(', ')}")
          end

          # Add system type reference to zone
          sys_group['zones'].sort.each do |zone|
            zone.additionalProperties.setFeature('baseline_system_type', system_type[0])
          end

          # Add the system type for these zones
          model_add_prm_baseline_system(model,
                                        system_type[0],
                                        system_type[1],
                                        system_type[2],
                                        system_type[3],
                                        sys_group['zones'],
                                        zone_fan_scheds)

          if baseline_179d && ['Gas_Furnace', 'Electric_Furnace'].include?(system_type[0])
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '179D - For Unit Heater, adding ZoneVentilationDesignFlowRate objects for ventilation and cooling exhaust')
            model_add_equivalent_zone_ventilation_for_heated_only_zones_with_dsoa(
              model,
              sys_group['zones'],
              ventilation_type: 'Exhaust',
              ensure_ddy_infiltration: true,
              add_cooling_exhaust: building_type == 'Warehouse'
            )
          end

          model.getAirLoopHVACs.each do |air_loop|
            air_loop_name = air_loop.name.get
            unless air_loop_name_array.include?(air_loop_name)
              air_loop.additionalProperties.setFeature('zone_group_type', sys_group['zone_group_type'] || 'None')
              air_loop.additionalProperties.setFeature('sys_group_occ', sys_group['occ'] || 'None')
              #  assign hvac_schedule directly not find from anywhere with air_loop_hvac_enable_unoccupied_fan_shutoff
              #  NOTE: 179D override!
              if !zone_fan_scheds.values.empty? && (zone_fan_scheds.values[0].is_a? String)
                air_loop.additionalProperties.setFeature('fan_sched_name', zone_fan_scheds.values[0])
              end

              air_loop_name_array << air_loop_name
            end

            # Determine return air type
            plenum, return_air_type = model_determine_baseline_return_air_type(model, system_type[0], air_loop.thermalZones)
            air_loop.thermalZones.sort.each do |zone|
              # Set up return air plenum
              zone.setReturnPlenum(model.getThermalZoneByName(plenum).get) if return_air_type == 'return_plenum'
            end
          end
        end
      end

      # Add system type reference to all air loops
      model.getAirLoopHVACs.sort.each do |air_loop|
        if air_loop.thermalZones[0].additionalProperties.hasFeature('baseline_system_type')
          sys_type = air_loop.thermalZones[0].additionalProperties.getFeatureAsString('baseline_system_type').get
          air_loop.additionalProperties.setFeature('baseline_system_type', sys_type)
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Thermal zone #{air_loop.thermalZones[0].name} is not associated to a particular system type.")
        end
      end

      unless ['PrimarySchool', 'SecondarySchool'].include?(building_type) && !baseline_179d
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Baseline HVAC System Sizing Settings ***')
        model.getThermalZones.each do |zone|
          thermal_zone_apply_prm_baseline_supply_temperatures(zone)
        end
      end

      # Set the system sizing properties based on the zone sizing information
      model.getAirLoopHVACs.each do |air_loop|
        air_loop_hvac_apply_prm_sizing_temperatures(air_loop)
      end

      # Set internal load sizing run schedules
      # ! no need for 90.1-2007
      model_apply_prm_baseline_sizing_schedule(model)

      # Set the heating and cooling sizing parameters
      model_apply_prm_sizing_parameters(model)

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Baseline HVAC System Controls ***')

      # SAT reset, economizers
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_hvac_apply_prm_baseline_controls(air_loop, climate_zone)
      end

      # Apply the baseline system water loop temperature reset control
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        plant_loop_apply_prm_baseline_temperatures(plant_loop)
      end

      # Run sizing run with the HVAC equipment
      if model_run_sizing_run(model, "#{sizing_run_dir}/SR1") == false
        return false
      end

      # Apply the minimum damper positions, assuming no DDC control of VAV terminals
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_hvac_apply_minimum_vav_damper_positions(air_loop, false)
      end

      # If there are any multi-zone systems, reset damper positions to achieve a 60% ventilation effectiveness minimum for the system
      # following the ventilation rate procedure from 62.1
      model_apply_multizone_vav_outdoor_air_sizing(model)

      # Force Sizing:System design outdoor airflow the same as Controller:OutdoorAir minimum OA airflow rate
      consistent_outdoor_airflow_rate(model)

      if baseline_179d

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Baseline Adjust Minimum/Design Outdoor Air Flow Rate to Proposed Levels if different ***')
        total_oa_design_flow_rate = 0.0

        # Get total design outdoor airflow rates using the same accounting scope
        # as reporting_179_d (air-loop + zone-level contributors).
        outdoor_airflow_rate_baseline_m_3_per_s = get_minimum_and_design_outdoor_airflow_rates(model, 'BASELINE')

        # Calculate % difference (relative to baseline)
        pct_diff_minimum_outdoor_airflow_rate =
          if outdoor_airflow_rate_baseline_m_3_per_s.zero?
            outdoor_airflow_rate_proposed_m_3_per_s.zero? ? 0.0 : 100.0
          else
            (
              outdoor_airflow_rate_proposed_m_3_per_s - outdoor_airflow_rate_baseline_m_3_per_s
            ) / outdoor_airflow_rate_baseline_m_3_per_s * 100.0
          end

        # Difference threshold
        diff_threshold_pcnt = 1.0

        # Adjust design outdoor airflow rate if difference between baseline/proposed is larger than 1%
        if outdoor_airflow_rate_baseline_m_3_per_s < -1.0e-9
          msg = 'BASELINE: Cannot proportionally adjust outdoor airflow rate because baseline total OA is negative.'
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', msg)
          raise msg
        end

        if pct_diff_minimum_outdoor_airflow_rate.abs > diff_threshold_pcnt # %
          if outdoor_airflow_rate_baseline_m_3_per_s.abs <= 1.0e-9
            msg = 'BASELINE: Cannot proportionally adjust outdoor airflow rate because baseline total OA is zero. Skipping OA scaling.'
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', msg)
          else
            msg = 'BASELINE: Minimum/Design outdoor airflow rate for the baseline model is ' \
                  "#{outdoor_airflow_rate_baseline_m_3_per_s.round(2)} m3/s, " \
                  "which is more than #{diff_threshold_pcnt}% different from the proposed model's minimum/design outdoor airflow rate of " \
                  "#{outdoor_airflow_rate_proposed_m_3_per_s.round(2)} m3/s. " \
                  "Adjusting baseline model design outdoor airflow rate to match the proposed model's design outdoor airflow rate."
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', msg)

            # Proportionally adjust design outdoor airflow rates to preserve
            # per-system/per-zone distributions while matching proposed total OA.
            scaling_factor = outdoor_airflow_rate_proposed_m_3_per_s / outdoor_airflow_rate_baseline_m_3_per_s
            model.getAirLoopHVACs.sort.each do |air_loop|
              sizing_system = air_loop.sizingSystem
              old_value = nil
              if sizing_system.designOutdoorAirFlowRate.is_initialized
                old_value = sizing_system.designOutdoorAirFlowRate.get
              elsif sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized
                old_value = sizing_system.autosizedDesignOutdoorAirFlowRate.get
              end
              if old_value
                sizing_system.setDesignOutdoorAirFlowRate(old_value * scaling_factor)
              else
                msg = "BASELINE: Cannot adjust design outdoor airflow rate — no existing value found on air loop '#{air_loop.nameString}'."
                OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', msg)
                raise msg
              end
            end

            scale_zone_level_outdoor_airflow_rates(model, scaling_factor)

            # Re-evaluate post-adjustment OA to ensure scaling converged.
            adjusted_baseline_oa_m_3_per_s = get_minimum_and_design_outdoor_airflow_rates(model, 'BASELINE (POST SCALE)')
            post_pct_diff =
              if adjusted_baseline_oa_m_3_per_s.zero?
                outdoor_airflow_rate_proposed_m_3_per_s.zero? ? 0.0 : 100.0
              else
                (
                  outdoor_airflow_rate_proposed_m_3_per_s - adjusted_baseline_oa_m_3_per_s
                ) / adjusted_baseline_oa_m_3_per_s * 100.0
              end
            if post_pct_diff.abs > diff_threshold_pcnt
              msg = 'BASELINE: Total design outdoor airflow rate remains outside threshold after scaling ' \
                    "(#{post_pct_diff.round(2)}% difference; threshold=#{diff_threshold_pcnt}%)."
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', msg)
              raise msg
            end
          end
        end
      end

      # Set the baseline fan power for all air loops
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_hvac_apply_prm_baseline_fan_power(air_loop)
      end

      # Set the baseline fan power for all zone HVAC
      model.getZoneHVACComponents.sort.each do |zone_hvac|
        zone_hvac_component_apply_prm_baseline_fan_power(zone_hvac)
      end

      # Set the baseline number of boilers and chillers
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        plant_loop_apply_prm_number_of_boilers(plant_loop)
        plant_loop_apply_prm_number_of_chillers(plant_loop, sizing_run_dir)
      end

      # Set the baseline number of cooling towers
      # Must be done after all chillers are added
      # rubocop:disable Style/CombinableLoops
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        if baseline_179d
          plant_loop_apply_prm_number_of_cooling_towers(plant_loop)
        end
      end
      # rubocop:enable Style/CombinableLoops

      # Run sizing run with the new chillers, boilers, and cooling towers to determine capacities
      if model_run_sizing_run(model, "#{sizing_run_dir}/SR2") == false
        return false
      end

      # Set the pumping control strategy and power
      # Must be done after sizing components
      model.getPlantLoops.sort.each do |plant_loop|
        # Skip the SWH loops
        next if plant_loop_swh_loop?(plant_loop)

        if baseline_179d
          plant_loop_apply_prm_baseline_pump_power(plant_loop)
        end
        plant_loop_apply_prm_baseline_pumping_type(plant_loop)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', '*** Applying Prescriptive HVAC Controls and Equipment Efficiencies ***')

      # Apply the HVAC efficiency standard -- !179D notes: autofan_turn_off apply to this one (both airLoop and ZoneHVAC)
      model_apply_hvac_efficiency_standard(model, climate_zone, baseline_179d)

      # NOTE: 179D Set the ACM schedule
      model_apply_acm_hvac_availability_schedule(model)

      # Set baseline DCV system
      model_set_baseline_demand_control_ventilation(model, climate_zone)

      if !baseline_179d
        # Force setting a motorized oa damper: sets the HVAC Operation Schedule
        # as a Controller:OA's Minimum Outdoor AIr Schedule so that OA intake
        # is turned off during nighttime
        occ_threshold = air_loop_hvac_unoccupied_threshold
        model.getAirLoopHVACs.sort.each { |air_loop_hvac| air_loop_hvac_add_motorized_oa_damper(air_loop_hvac, occ_threshold, air_loop_hvac.availabilitySchedule) }
      end

      # Final sizing run and adjustements to values that need refinement
      model_refine_size_dependent_values(model, sizing_run_dir)

      # Fix EMS references.
      # Temporary workaround for OS issue #2598
      model_temp_fix_ems_references(model)

      # Delete all the unused resource objects
      model_remove_unused_resource_objects(model)

      # Add reporting tolerances
      model_add_reporting_tolerances(model)

      # @todo: turn off self shading
      # Set Solar Distribution to MinimalShadowing... problem is when you also have detached shading such as surrounding buildings etc
      # It won't be taken into account, while it should: only self shading from the building itself should be turned off but to my knowledge there isn't a way to do this in E+
      model_status = degs > 0 ? "baseline_final_#{degs}" : 'baseline_final'
      OpenStudioStandards::RulesetChecking.export_json_output(model)
      model.save(OpenStudio::Path.new("#{sizing_run_dir}/#{model_status}.osm"), true)

      # Translate to IDF and save for debugging
      forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      idf = forward_translator.translateModel(model)
      model.getSpaces.sort.each do |space|
        space_cond_type = space_conditioning_category(space)
        next if space_cond_type == 'Unconditioned'

        OpenStudioStandards::RulesetChecking.tag_spaces(idf, space)
      end
      idf_path = OpenStudio::Path.new("#{sizing_run_dir}/#{model_status}.idf")
      idf.save(idf_path, true)
      OpenStudioStandards::RulesetChecking.export_epjson(model, sizing_run_dir, model_status.to_s)

      prm_system_type_str = prm_system_types.uniq.map { |x| x[0] }.uniq.join('***')
      model.getBuilding.additionalProperties.setFeature('prm_baseline_system_type', prm_system_type_str)

      # Check unmet load hours # disable for 179d
      if unmet_load_hours_check
        nb_adjustments = 0
        max_adjustments = 5
        max_sizing_factor = 10.0
        unmet_load_hours = nil
        # Original
        # get_sizing_factor_multiplier = lambda {|unmet_hours| unmet_hours > 150 ? 1.1 : 1.05 }
        # New, more aggressive
        get_sizing_factor_multiplier = ->(unmet_hours) { 1.025 + (unmet_hours * 0.0005) }

        loop do
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Starting the pre-simulation for the #{nb_adjustments + 1} round of zone sizing factor adjustments for the unmet load hours for the baseline model (#{degs} degree of rotation)")

          # Close the previous SQL session if open to prevent EnergyPlus from overloading the same session
          sql = model.sqlFile.get
          if sql.connectionOpen
            sql.close
          end

          if !model_run_simulation_and_log_errors(model, "#{sizing_run_dir}/final#{degs}_adjustment#{nb_adjustments}")
            # simulation failure, raise the exception.
            msg = "OpenStudio simulation failed on unmet_load_hours_check adjustment #{nb_adjustments}."
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', msg)
            raise msg
          end

          # If UMLH are greater than the threshold allowed by Appendix G,
          # increase zone air flow and load as per the recommendation in
          # the PRM-RM; Note that the PRM-RM only suggest to increase
          # air zone air flow, but the zone sizing factor in EnergyPlus
          # increase both air flow and load.
          umlh = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(model)
          if umlh <= 300
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "#{nb_adjustments} rounds of zone sizing factor adjustments were needed for the unmet load hours to be < 300 for the baseline model (#{degs} degree of rotation): final = #{umlh} unmet load hours")
            break
          end

          nb_adjustments += 1
          # Limit the number of zone sizing factor adjustment to 8
          if nb_adjustments > max_adjustments
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "After #{max_adjustments} rounds of zone sizing factor adjustments the unmet load hours for the baseline model (#{degs} degree of rotation) still exceed 300 hours: final = #{umlh} unmet load hours. Please open an issue on GitHub (https://github.com/NREL/openstudio-standards/issues) and share your user model with the developers.")
            break
          end

          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Starting the #{nb_adjustments} round of zone sizing factor adjustments for the unmet load hours for the baseline model (#{degs} degree of rotation)")

          has_adjusted = false

          model.getThermalZones.each do |thermal_zone|
            # Cooling adjustments
            clg_umlh = OpenstudioStandards::SqlFile.thermal_zone_get_annual_occupied_unmet_cooling_hours(thermal_zone)
            if clg_umlh > 50
              # Get zone cooling sizing factor
              sizing_factor = 1.0
              if thermal_zone.sizingZone.zoneCoolingSizingFactor.is_initialized
                sizing_factor = thermal_zone.sizingZone.zoneCoolingSizingFactor.get
              end
              # Make adjustment to zone cooling sizing factor
              # Do not adjust factors greater or equal to 2
              if sizing_factor < max_sizing_factor
                sizing_factor = (get_sizing_factor_multiplier.call(clg_umlh) * sizing_factor).clamp(0, max_sizing_factor)
                has_adjusted = true
                thermal_zone.sizingZone.setZoneCoolingSizingFactor(sizing_factor)
              end
            end

            # Heating adjustments
            htg_umlh = OpenstudioStandards::SqlFile.thermal_zone_get_annual_occupied_unmet_heating_hours(thermal_zone)
            if htg_umlh > 50
              sizing_factor = 1.0
              # Get zone heating sizing factor
              if thermal_zone.sizingZone.zoneHeatingSizingFactor.is_initialized
                sizing_factor = thermal_zone.sizingZone.zoneHeatingSizingFactor.get
              end

              # Make adjustment to zone heating sizing factor
              # Do not adjust factors greater or equal to 2
              if sizing_factor < max_sizing_factor
                sizing_factor = (get_sizing_factor_multiplier.call(htg_umlh) * sizing_factor).clamp(0, max_sizing_factor)
                has_adjusted = true
                thermal_zone.sizingZone.setZoneHeatingSizingFactor(sizing_factor)
              end
            end
          end
          if !has_adjusted
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model',
                               "After #{nb_adjustment} rounds of zone sizing factor adjustments the unmet load hours for the baseline model (#{degs} degree of rotation) still exceed 300 hours, but all Zone Sizing Factors are already at #{max_sizing_factor}.")
            break
          end
        end
      end
    end

    if debug
      generate_baseline_log(sizing_run_dir)
    end

    return true
  end
  # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity, Style/OptionalBooleanParameter

  def _get_or_create_ddy_only_infiltration_schedule(model)
    ddy_only_infil_sch_name = 'Infiltration Schedule Only One on Design Days'
    sch_ = model.getScheduleRulesetByName(ddy_only_infil_sch_name)
    return sch_.get if sch_.is_initialized

    sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model, 0.0)
    sch_ruleset.setName(ddy_only_infil_sch_name)
    sch_ruleset.defaultDaySchedule.setName("#{ddy_only_infil_sch_name} Default Day")

    # Winter Design Day
    temp = OpenStudio::Model::ScheduleDay.new(model)
    sch_ruleset.setWinterDesignDaySchedule(temp)
    temp.remove
    winter_dsn_day = sch_ruleset.winterDesignDaySchedule
    winter_dsn_day.setName("#{ddy_only_infil_sch_name} Winter Design Day")
    winter_dsn_day.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
    # Summer Design Day
    temp = OpenStudio::Model::ScheduleDay.new(model)
    sch_ruleset.setSummerDesignDaySchedule(temp)
    temp.remove
    summer_dsn_day = sch_ruleset.summerDesignDaySchedule
    summer_dsn_day.setName("#{ddy_only_infil_sch_name} Summer Design Day")
    summer_dsn_day.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
    return sch_ruleset
  end

  def space_get_outdoor_airflow_rate(space)
    return 0.0 if space.designSpecificationOutdoorAir.empty?

    dsoa = space.designSpecificationOutdoorAir.get
    oa_people = space.numberOfPeople * dsoa.outdoorAirFlowperPerson
    oa_floor_area = space.floorArea * dsoa.outdoorAirFlowperFloorArea
    oa_rate = dsoa.outdoorAirFlowRate
    oa_volume = space.volume * dsoa.outdoorAirFlowAirChangesperHour / 3600.0

    return [oa_people, oa_floor_area, oa_rate, oa_volume].sum if dsoa.outdoorAirMethod.casecmp('sum').zero?

    return [oa_people, oa_floor_area, oa_rate, oa_volume].max
  end

  def _zone_has_exterior_connection?(zone, minimum_exterior_area_m2: 0.001)
    zone.spaces.any? { |space| space.exteriorArea > minimum_exterior_area_m2 }
  end

  def _find_exterior_source_zone_for_interior_zone(interior_zone, exterior_zones)
    return nil if exterior_zones.empty?

    exterior_zone_handles = exterior_zones.map { |z| z.handle.to_s }
    interior_zone.spaces.each do |space|
      space.surfaces.each do |surface|
        next unless surface.adjacentSurface.is_initialized

        adjacent_surface = surface.adjacentSurface.get
        next unless adjacent_surface.space.is_initialized

        adjacent_space = adjacent_surface.space.get
        next unless adjacent_space.thermalZone.is_initialized

        adjacent_zone = adjacent_space.thermalZone.get
        return adjacent_zone if exterior_zone_handles.include?(adjacent_zone.handle.to_s)
      end
    end

    fallback_zone = exterior_zones.max_by(&:floorArea)
    OpenStudio.logFree(
      OpenStudio::Warn, 'openstudio.179D.Model',
      "No adjacent exterior zone found for interior zone '#{interior_zone.nameString}'; using largest exterior zone '#{fallback_zone.nameString}' as source for mixing."
    )
    fallback_zone
  end

  def _apply_cooling_exhaust_gate_to_zone_ventilation(zone_ventilation, zone, cooling_exhaust_delta_t_c:)
    # Trigger: activate when indoor temp exceeds the thermostat cooling setpoint.
    # Using the schedule allows this to track any thermostat updates automatically.
    if zone.thermostatSetpointDualSetpoint.is_initialized
      tstat = zone.thermostatSetpointDualSetpoint.get
      if tstat.coolingSetpointTemperatureSchedule.is_initialized
        zone_ventilation.setMinimumIndoorTemperatureSchedule(tstat.coolingSetpointTemperatureSchedule.get)
      else
        zone_ventilation.setMinimumIndoorTemperature(40.0)
      end
    else
      zone_ventilation.setMinimumIndoorTemperature(40.0)
    end

    zone_ventilation.setMaximumIndoorTemperature(100.0)
    # Only provide free cooling when outdoor is measurably cooler than indoor
    zone_ventilation.setDeltaTemperature(cooling_exhaust_delta_t_c)
    # Don't run when outdoor is very cold (no overheating risk near-freezing)
    zone_ventilation.setMinimumOutdoorTemperature(13.0)
    zone_ventilation.setMaximumOutdoorTemperature(100.0)
  end

  # For Heated Only Zones, System 9 or 10, there will be zero outside air
  # actually brought in, because the ZoneHVACUnitHeater does not provide OA.
  # While this has very little effect in most of the building types (heated
  # only zones are small), this is problematic for the Warehouse in particular.
  # This method will look at such zones, and for each zone it will find the
  # DesignSpecificationOutdoorAir objects for the spaces and compute an
  # equivalent OA flow rate.
  #
  # A ventilation ZoneVentilationDesignFlowRate object is created per zone:
  #
  # 1. **Ventilation exhaust** (year-round occupied): sized to the code-minimum
  #    OA requirement, runs on the zone's HVAC availability schedule (occupied
  #    hours), temperature limits are permissive — this satisfies IAQ requirements
  #    for the heating-only zone.
  #
  # If add_cooling_exhaust is enabled:
  # * Interior zones get a **Cooling Exhaust** object.
  # * Exterior-connected zones get a thermostat-gated **Cooling Makeup Air Intake**
  #   object (to avoid double counting simultaneous exhaust+intake OA at the same
  #   design flow in a single zone).
  # * Interior zones get always-on **ZoneMixing** from an exterior source zone.
  # * Exterior source zones get always-on **Mixing Makeup Air Intake** objects sized
  #   to the total outgoing interior mixing flow.
  #
  # @param ventilation_type [String] one of:
  #   * 'Natural': no fan power (0 W/CFM)
  #   * 'Intake': System 9 and 10 supply fan, 0.3 W/CFM
  #   * 'Exhaust': System 9 and 10 non-mechanical cooling, 0.054 W/CFM
  # @param ensure_ddy_infiltration [Boolean]: if true, checks that spaces have
  #   some ACH and adds a design-day-only infiltration object that matches the
  #   space DSOA to avoid sizing errors.
  # @param add_cooling_exhaust [Boolean]: if true, adds a second, higher-flow
  #   exhaust object controlled by the thermostat cooling setpoint.
  # @param cooling_exhaust_flow_per_area_m3_per_s_per_m2 [Float, nil]: cooling
  #   exhaust flow rate per floor area. Defaults to ~0.27 CFM/ft² (0.00137
  #   m³/s·m²) based on ASHRAE heat-balance sizing.
  # @param cooling_exhaust_delta_t_c [Float]: minimum indoor-minus-outdoor
  #   temperature difference (°C) required for the cooling exhaust to operate.
  #   Default 2.0°C prevents operation when outdoor air provides no cooling benefit.
  # @param interior_zone_mixing_flow_fraction [Float, nil]: optional multiplier
  #   on interior-zone always-on mixing flow. If nil, this can be calibrated via
  #   building additional property `179d_interior_zone_mixing_flow_fraction`.
  #   Defaults to 1.0 if not provided.
  # rubocop:disable Metrics/AbcSize, Metrics/BlockLength
  def model_add_equivalent_zone_ventilation_for_heated_only_zones_with_dsoa(
    model, zones,
    ventilation_type: 'Natural',
    ensure_ddy_infiltration: true,
    add_cooling_exhaust: false,
    cooling_exhaust_flow_per_area_m3_per_s_per_m2: nil,
    cooling_exhaust_delta_t_c: 2.0,
    interior_zone_mixing_flow_fraction: nil
  )
    # Default cooling exhaust flow rate: ASHRAE heat-balance approach,
    # ~4.4 BTU/hr/ft² internal gains at 15°F (8.3°C) permissible ΔT → ~0.27 CFM/ft²
    # Reference: ASHRAE Handbook of Fundamentals, Chapter 16.
    cooling_flow_m3_per_s_per_m2 = cooling_exhaust_flow_per_area_m3_per_s_per_m2 ||
                                   OpenStudio.convert(0.27, 'CFM/ft^2', 'm^3/s*m^2').get

    # Fan power parameters (same for both ventilation and cooling exhaust objects)
    case ventilation_type
    when 'Natural'
      pressure_rise_pa = 0.0
      fan_total_eff = 1.0
    when 'Intake'
      # System 9 and 10 supply fan: Pfan = CFM × 0.3 W/CFM
      target_w_per_m3_per_s = OpenStudio.convert(0.3, 'W/CFM', 'W*s/m^3').get
      fan_total_eff = 0.6
      pressure_rise_pa = fan_total_eff * target_w_per_m3_per_s
    when 'Exhaust'
      # System 9 and 10 non-mechanical cooling fan per §G3.1.2.8.2: Pfan = CFM × 0.054 W/CFM
      target_w_per_m3_per_s = OpenStudio.convert(0.054, 'W/CFM', 'W*s/m^3').get
      fan_total_eff = 0.6
      pressure_rise_pa = fan_total_eff * target_w_per_m3_per_s
    else
      raise "ventilation_type must be one of ['Natural', 'Intake', 'Exhaust']"
    end

    # Resolve the occupied schedule once for all zones.
    # Prefer the ACM schedule stored in building additional properties by get_fan_schedule_for_each_zone
    # (which runs before ZV creation in model_create_prm_baseline_building). Fall back to a standards
    # data lookup, then to always-on.
    occupied_sched = nil
    acm_sch_name_opt = model.getBuilding.additionalProperties.getFeatureAsString('acm_fan_sch')
    if acm_sch_name_opt.is_initialized
      occupied_sched = model_add_schedule(model, acm_sch_name_opt.get)
    end
    if occupied_sched.nil?
      begin
        data = model_get_standards_data(model)
        acm_sch_name = data['hvac_operation_schedule']
        occupied_sched = model_add_schedule(model, acm_sch_name) if acm_sch_name
      rescue StandardError
        # Fall back to always-on
      end
    end

    mixing_flow_fraction = interior_zone_mixing_flow_fraction
    if mixing_flow_fraction.nil?
      mixing_flow_fraction_opt = model.getBuilding.additionalProperties.getFeatureAsDouble('179d_interior_zone_mixing_flow_fraction')
      mixing_flow_fraction = mixing_flow_fraction_opt.is_initialized ? mixing_flow_fraction_opt.get : 1.0
    end
    raise 'interior_zone_mixing_flow_fraction must be >= 0.0' if mixing_flow_fraction < 0.0

    # If cooling exhaust is limited to interior zones, renormalize its per-area
    # flow so the *total* cooling exhaust capacity still reflects the entire
    # heated-only storage area served by this routine.
    eligible_zone_total_floor_area_m2 = 0.0
    eligible_interior_zone_total_floor_area_m2 = 0.0
    eligible_exterior_zone_total_floor_area_m2 = 0.0
    zones.sort.each do |zone|
      begin
        total_oa_m3_per_s = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
      rescue StandardError
        next
      end
      next unless total_oa_m3_per_s > 0

      eligible_zone_total_floor_area_m2 += zone.floorArea
      if _zone_has_exterior_connection?(zone)
        eligible_exterior_zone_total_floor_area_m2 += zone.floorArea
        next
      end

      eligible_interior_zone_total_floor_area_m2 += zone.floorArea
    end

    interior_cooling_exhaust_flow_m3_per_s_per_m2 = cooling_flow_m3_per_s_per_m2
    exterior_cooling_makeup_flow_m3_per_s_per_m2 = cooling_flow_m3_per_s_per_m2
    if add_cooling_exhaust
      if eligible_interior_zone_total_floor_area_m2 > 0.0
        interior_cooling_exhaust_flow_m3_per_s_per_m2 = cooling_flow_m3_per_s_per_m2 *
                                                        (eligible_zone_total_floor_area_m2 / eligible_interior_zone_total_floor_area_m2)
        OpenStudio.logFree(
          OpenStudio::Info, 'openstudio.179D.Model',
          "Renormalizing interior cooling exhaust flow from #{OpenStudio.convert(cooling_flow_m3_per_s_per_m2, 'm^3/s*m^2', 'CFM/ft^2').get.round(4)} to #{OpenStudio.convert(interior_cooling_exhaust_flow_m3_per_s_per_m2, 'm^3/s*m^2', 'CFM/ft^2').get.round(4)} CFM/ft^2 using area ratio #{(eligible_zone_total_floor_area_m2 / eligible_interior_zone_total_floor_area_m2).round(4)}"
        )
      else
        OpenStudio.logFree(
          OpenStudio::Warn, 'openstudio.179D.Model',
          'No interior heated-only zones found for cooling exhaust renormalization; using default cooling exhaust flow.'
        )
      end

      if eligible_exterior_zone_total_floor_area_m2 > 0.0
        exterior_cooling_makeup_flow_m3_per_s_per_m2 = cooling_flow_m3_per_s_per_m2 *
                                                       (eligible_zone_total_floor_area_m2 / eligible_exterior_zone_total_floor_area_m2)
        OpenStudio.logFree(
          OpenStudio::Info, 'openstudio.179D.Model',
          "Renormalizing exterior cooling make-up intake flow from #{OpenStudio.convert(cooling_flow_m3_per_s_per_m2, 'm^3/s*m^2', 'CFM/ft^2').get.round(4)} to #{OpenStudio.convert(exterior_cooling_makeup_flow_m3_per_s_per_m2, 'm^3/s*m^2', 'CFM/ft^2').get.round(4)} CFM/ft^2 using area ratio #{(eligible_zone_total_floor_area_m2 / eligible_exterior_zone_total_floor_area_m2).round(4)}"
        )
      else
        OpenStudio.logFree(
          OpenStudio::Warn, 'openstudio.179D.Model',
          'No exterior heated-only zones found for cooling make-up intake renormalization; using default cooling make-up intake flow.'
        )
      end
    end

    zone_data_by_handle = {}
    zones.sort.each do |zone|
      begin
        total_oa_m3_per_s = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone)
      rescue StandardError => e
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.179D.Model', "Skipping zone #{zone.name} due to standards lookup error: #{e.message}")
        next
      end

      total_oa_m3_per_m2s = total_oa_m3_per_s / zone.floorArea
      next unless total_oa_m3_per_s > 0

      tot_oa_cfm = OpenStudio.convert(total_oa_m3_per_s, 'm^3/s', 'cfm').get.round(2)
      total_oa_cfm_per_sqft = OpenStudio.convert(total_oa_m3_per_m2s, 'm^3/m^2*s', 'cfm/ft^2').get.round(4)

      OpenStudio.logFree(
        OpenStudio::Info, 'openstudio.179D.Model',
        "Adding ventilation exhaust for #{zone.name} - #{tot_oa_cfm} CFM total - #{total_oa_cfm_per_sqft} CFM/ft^2"
      )
      zone_data_by_handle[zone.handle.to_s] = {
        zone: zone,
        has_exterior_connection: _zone_has_exterior_connection?(zone),
        base_cooling_flow_m3_per_s: cooling_flow_m3_per_s_per_m2 * zone.floorArea
      }

      # ------------------------------------------------------------------
      # System 1: Year-round occupied exhaust for code-required ventilation
      # Runs on the zone HVAC availability schedule (occupied hours only).
      # Temperature limits are permissive — this provides IAQ-required OA
      # through infiltration makeup regardless of indoor/outdoor conditions.
      # ------------------------------------------------------------------
      ventilation = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
      ventilation.setName("#{zone.name} Ventilation")
      ventilation.setSchedule(occupied_sched || model.alwaysOnDiscreteSchedule)
      ventilation.setFlowRateperZoneFloorArea(total_oa_m3_per_m2s)
      ventilation.setConstantTermCoefficient(1.0)
      ventilation.setVelocityTermCoefficient(0.0)
      ventilation.setTemperatureTermCoefficient(0.0)
      ventilation.setMinimumIndoorTemperature(-73.3333352760033)
      ventilation.setMaximumIndoorTemperature(100.0)
      ventilation.setDeltaTemperature(-100.0)
      ventilation.setVentilationType(ventilation_type)
      ventilation.setFanPressureRise(pressure_rise_pa)
      ventilation.setFanTotalEfficiency(fan_total_eff)
      ventilation.addToThermalZone(zone)
      zone.setHeatingPriority(ventilation, 0)
      zone.setCoolingPriority(ventilation, 0)

      if add_cooling_exhaust
        # ------------------------------------------------------------------
        # System 2: Cooling airflow for summer overheating prevention.
        # Sized using ASHRAE heat-balance approach (~0.27 CFM/ft²).
        # Activates only when:
        #   (a) indoor temp > thermostat cooling setpoint (free-cooling trigger)
        #   (b) indoor temp exceeds outdoor temp by at least delta_t (free cooling)
        #   (c) outdoor temp >= 13°C (55°F) — prevents operation in cold weather
        # ------------------------------------------------------------------
        cooling_makeup_cfm_per_sqft = OpenStudio.convert(exterior_cooling_makeup_flow_m3_per_s_per_m2, 'm^3/s*m^2', 'CFM/ft^2').get.round(4)
        interior_cooling_exhaust_cfm_per_sqft = OpenStudio.convert(interior_cooling_exhaust_flow_m3_per_s_per_m2, 'm^3/s*m^2', 'CFM/ft^2').get.round(4)
        zone_data = zone_data_by_handle[zone.handle.to_s]
        if zone_data[:has_exterior_connection]
          intake_name = "#{zone.name} Cooling Makeup Air Intake"
          cooling_makeup_intake = zone.equipment.filter_map do |eq|
            zv = eq.to_ZoneVentilationDesignFlowRate
            zv.get if zv.is_initialized && zv.get.nameString == intake_name
          end.first
          if cooling_makeup_intake.nil?
            OpenStudio.logFree(
              OpenStudio::Info, 'openstudio.179D.Model',
              "Adding cooling make-up intake for #{zone.name} - #{cooling_makeup_cfm_per_sqft} CFM/ft^2"
            )
            cooling_makeup_intake = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
            cooling_makeup_intake.setName(intake_name)
            cooling_makeup_intake.setSchedule(model.alwaysOnDiscreteSchedule)
            cooling_makeup_intake.setFlowRateperZoneFloorArea(exterior_cooling_makeup_flow_m3_per_s_per_m2)
            cooling_makeup_intake.setConstantTermCoefficient(1.0)
            cooling_makeup_intake.setVelocityTermCoefficient(0.0)
            cooling_makeup_intake.setTemperatureTermCoefficient(0.0)
            _apply_cooling_exhaust_gate_to_zone_ventilation(cooling_makeup_intake, zone, cooling_exhaust_delta_t_c: cooling_exhaust_delta_t_c)
            cooling_makeup_intake.setVentilationType('Intake')
            # Gravity-damper analog: no dedicated intake fan power.
            cooling_makeup_intake.setFanPressureRise(0.0)
            cooling_makeup_intake.setFanTotalEfficiency(1.0)
            cooling_makeup_intake.addToThermalZone(zone)
            zone.setHeatingPriority(cooling_makeup_intake, 0)
            zone.setCoolingPriority(cooling_makeup_intake, 0)
          end
        else
          cooling_exhaust_name = "#{zone.name} Cooling Exhaust"
          has_cooling_exhaust = zone.equipment.any? do |eq|
            zv = eq.to_ZoneVentilationDesignFlowRate
            zv.is_initialized && zv.get.nameString == cooling_exhaust_name
          end
          unless has_cooling_exhaust
            OpenStudio.logFree(
              OpenStudio::Info, 'openstudio.179D.Model',
              "Adding cooling exhaust for #{zone.name} - #{interior_cooling_exhaust_cfm_per_sqft} CFM/ft^2 - delta_t=#{cooling_exhaust_delta_t_c}°C"
            )

            cooling_exhaust = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
            cooling_exhaust.setName(cooling_exhaust_name)
            cooling_exhaust.setSchedule(model.alwaysOnDiscreteSchedule)
            cooling_exhaust.setFlowRateperZoneFloorArea(interior_cooling_exhaust_flow_m3_per_s_per_m2)
            cooling_exhaust.setConstantTermCoefficient(1.0)
            cooling_exhaust.setVelocityTermCoefficient(0.0)
            cooling_exhaust.setTemperatureTermCoefficient(0.0)
            _apply_cooling_exhaust_gate_to_zone_ventilation(cooling_exhaust, zone, cooling_exhaust_delta_t_c: cooling_exhaust_delta_t_c)
            cooling_exhaust.setVentilationType(ventilation_type)
            cooling_exhaust.setFanPressureRise(pressure_rise_pa)
            cooling_exhaust.setFanTotalEfficiency(fan_total_eff)
            cooling_exhaust.addToThermalZone(zone)
            zone.setHeatingPriority(cooling_exhaust, 0)
            zone.setCoolingPriority(cooling_exhaust, 0)
          end
        end
      end

      next unless ensure_ddy_infiltration

      zone.spaces.each do |space|
        next if space.infiltrationDesignAirChangesPerHour > 0.001

        spi = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        spi.setName("#{space.nameString} Design Day Only Infiltration")
        spi.setSpace(space)
        spi.setSchedule(_get_or_create_ddy_only_infiltration_schedule(model))
        if space.designSpecificationOutdoorAir.is_initialized
          spi.setFlowperSpaceFloorArea(space_get_outdoor_airflow_rate(space) / space.floorArea)
        else
          spi.setAirChangesperHour(0.01)
        end
        target_ach = spi.getAirChangesPerHour(space.floorArea, space.exteriorArea, space.exteriorWallArea, space.volume)
        OpenStudio.logFree(
          OpenStudio::Info, 'openstudio.179D.Model',
          "Adding Design Day Only Infiltration for Space '#{space.nameString}' with equivalent #{target_ach.round(2)} ACH to avoid sizing errors"
        )
      end
    end

    return true unless add_cooling_exhaust

    exterior_zone_data = zone_data_by_handle.values.select { |zd| zd[:has_exterior_connection] }
    interior_zone_data = zone_data_by_handle.values.reject { |zd| zd[:has_exterior_connection] }
    exterior_zones = exterior_zone_data.map { |zd| zd[:zone] }
    source_zone_mixing_flow_m3_per_s = Hash.new(0.0)

    interior_zone_data.each do |zd|
      interior_zone = zd[:zone]
      source_zone = _find_exterior_source_zone_for_interior_zone(interior_zone, exterior_zones)
      next if source_zone.nil?

      mixing_name = "#{interior_zone.name} Exterior Storage Mixing"
      next if model.getZoneMixings.any? { |mixing| mixing.nameString == mixing_name }

      mixing = OpenStudio::Model::ZoneMixing.new(interior_zone)
      mixing.setName(mixing_name)
      # Air-wall-separated storage spaces continuously exchange air in operation.
      mixing.setSchedule(model.alwaysOnDiscreteSchedule)
      mixing.setSourceZone(source_zone)
      # Use base (pre-renormalization) cooling flow for interior/exterior transfer via mixing.
      mixing_flow_m3_per_s = zd[:base_cooling_flow_m3_per_s] * mixing_flow_fraction
      mixing.setDesignFlowRate(mixing_flow_m3_per_s)
      source_zone_mixing_flow_m3_per_s[source_zone.handle.to_s] += mixing_flow_m3_per_s
      OpenStudio.logFree(
        OpenStudio::Info, 'openstudio.179D.Model',
        "Adding always-on exterior/interior zone mixing from '#{source_zone.name}' to '#{interior_zone.name}' at #{OpenStudio.convert(mixing_flow_m3_per_s, 'm^3/s', 'cfm').get.round(2)} CFM (fraction=#{mixing_flow_fraction})"
      )
    end

    source_zone_mixing_flow_m3_per_s.each do |source_handle, total_mixing_flow_m3_per_s|
      next unless total_mixing_flow_m3_per_s > 0.0

      source_zone = zone_data_by_handle[source_handle][:zone]
      intake_name = "#{source_zone.name} Mixing Makeup Air Intake"
      mixing_makeup_intake = source_zone.equipment.filter_map do |eq|
        zv = eq.to_ZoneVentilationDesignFlowRate
        zv.get if zv.is_initialized && zv.get.nameString == intake_name
      end.first

      if mixing_makeup_intake.nil?
        mixing_makeup_intake = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(model)
        mixing_makeup_intake.setName(intake_name)
        mixing_makeup_intake.setSchedule(model.alwaysOnDiscreteSchedule)
        mixing_makeup_intake.setConstantTermCoefficient(1.0)
        mixing_makeup_intake.setVelocityTermCoefficient(0.0)
        mixing_makeup_intake.setTemperatureTermCoefficient(0.0)
        mixing_makeup_intake.setMinimumIndoorTemperature(-73.3333352760033)
        mixing_makeup_intake.setMaximumIndoorTemperature(100.0)
        mixing_makeup_intake.setDeltaTemperature(-100.0)
        mixing_makeup_intake.setMinimumOutdoorTemperature(-100.0)
        mixing_makeup_intake.setMaximumOutdoorTemperature(100.0)
        mixing_makeup_intake.setVentilationType('Intake')
        # Gravity-damper analog: no dedicated intake fan power.
        mixing_makeup_intake.setFanPressureRise(0.0)
        mixing_makeup_intake.setFanTotalEfficiency(1.0)
        mixing_makeup_intake.addToThermalZone(source_zone)
        source_zone.setHeatingPriority(mixing_makeup_intake, 0)
        source_zone.setCoolingPriority(mixing_makeup_intake, 0)
      end

      mixing_makeup_intake.setDesignFlowRate(total_mixing_flow_m3_per_s)
      OpenStudio.logFree(
        OpenStudio::Info, 'openstudio.179D.Model',
        "Adding always-on mixing make-up intake for '#{source_zone.name}' at #{OpenStudio.convert(total_mixing_flow_m3_per_s, 'm^3/s', 'cfm').get.round(2)} CFM"
      )
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/BlockLength

  # Add Design-Day-Only SpaceInfiltrationDesignFlowRate to spaces in the given
  # zones whose final infiltration ACH is < 0.001. Intended to be called AFTER
  # space_type_apply_standard_infiltration has re-applied space-type-level
  # infiltration (so space.infiltrationDesignAirChangesPerHour reflects the
  # final value). Schedule has value 1 only on design days, 0 in 8760 — so
  # this affects sizing convergence without changing annual results.
  #
  # @param model [OpenStudio::Model::Model]
  # @param zones [Array<OpenStudio::Model::ThermalZone>] zones whose spaces to consider
  def model_add_ddy_only_infiltration_for_heated_only_zones(model, zones)
    zones.sort.each do |zone|
      zone.spaces.each do |space|
        next if space.infiltrationDesignAirChangesPerHour > 0.001

        spi = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        spi.setName("#{space.nameString} Design Day Only Infiltration")
        spi.setSpace(space)
        spi.setSchedule(_get_or_create_ddy_only_infiltration_schedule(model))
        if space.designSpecificationOutdoorAir.is_initialized
          spi.setFlowperSpaceFloorArea(space_get_outdoor_airflow_rate(space) / space.floorArea)
        else
          spi.setAirChangesperHour(0.01)
        end
        target_ach = spi.getAirChangesPerHour(space.floorArea, space.exteriorArea, space.exteriorWallArea, space.volume)
        OpenStudio.logFree(
          OpenStudio::Info, 'openstudio.179D.Model',
          "Adding Design Day Only Infiltration for Space '#{space.nameString}' with equivalent #{target_ach.round(2)} ACH to avoid sizing errors"
        )
      end
    end
  end

  # Store fan operation schedule for each zone before deleting HVAC objects
  # NOTE: 179D overrides it to get the hvac_operation_schedule from ACM data
  # @param model [object]
  # @return [hash] of zoneName:STRING fan sch name! (Override)
  def get_fan_schedule_for_each_zone(model)
    data = model_get_standards_data(model, throw_if_not_found: true)
    acm_fan_sch_name = data['hvac_operation_schedule']
    acm_fan_sch = model_add_schedule(model, acm_fan_sch_name)
    model.getBuilding.additionalProperties.setFeature('acm_fan_sch', acm_fan_sch_name)

    # NOTE: 179D override, we set it to a String
    # fan_schedule_8760 = get_8760_values_from_schedule(model, acm_fan_sch)

    fan_sch_names = {}
    model.getThermalZones.sort.each do |zone|
      fan_sch_names[zone.name.get] = acm_fan_sch_name # fan_schedule_8760
    end

    return fan_sch_names
  end

  # get total design outdoor airflow rate by summing:
  # 1) air-loop outdoor airflow rates (Controller:OutdoorAir + Sizing:System context)
  # 2) zone-level outdoor airflow contributors
  # This matches the reporting_179_d accounting scope for
  # in_hvac_controls_design_outdoor_air_supply_flow_total.
  # @param model [object]
  # @return [float] total design outdoor airflow rate [m3/s]
  def get_minimum_and_design_outdoor_airflow_rates(model, scenario)
    air_loop_outdoor_airflow_rate_m_3_per_s = 0.0

    model.getAirLoopHVACs.each do |air_loop|
      # Initialize values for this air loop
      value = 0.0

      # Skip if no outdoor air system
      next if air_loop.airLoopHVACOutdoorAirSystem.empty?

      # Get the outdoor air system and controller
      air_loop_hvac_oasys = air_loop.airLoopHVACOutdoorAirSystem.get
      controller_oa = air_loop_hvac_oasys.getControllerOutdoorAir
      sizing_system = air_loop.sizingSystem

      # Get minimum/design outdoor airflow rate
      # sizing_system.autosizedDesignOutdoorAirFlowRate isn’t working correctly, so avoid using!
      # controller_oa.minimumOutdoorAirFlowRate is zero when DCV is enabled, so avoid using!
      if sizing_system.designOutdoorAirFlowRate.is_initialized
        value = sizing_system.designOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        value = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        msg = "#{scenario}: Cannot get minimum/design outdoor airflow rate from air loop hvac '#{air_loop.nameString}'."
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', msg)
        raise msg
      end

      # Use the maximum of the two values for this air loop
      air_loop_outdoor_airflow_rate_m_3_per_s += value
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "#{scenario}: airloop = #{air_loop.nameString} | minimum/design outdoor airflow rate = #{value} m3/s")
    end

    zone_level_outdoor_airflow_rate_m_3_per_s = get_zone_level_outdoor_airflow_rate(model)
    total_outdoor_airflow_rate_m_3_per_s = air_loop_outdoor_airflow_rate_m_3_per_s + zone_level_outdoor_airflow_rate_m_3_per_s

    OpenStudio.logFree(
      OpenStudio::Info,
      'openstudio.standards.Model', "#{scenario}: minimum_design_outdoor_airflow_rate_m_3_per_s = #{minimum_design_outdoor_airflow_rate_m_3_per_s}"
    )
    OpenStudio.logFree(
      OpenStudio::Info,
      'openstudio.standards.Model', "#{scenario}: zone_level_outdoor_airflow_rate_m_3_per_s = #{zone_level_outdoor_airflow_rate_m_3_per_s}"
    )
    OpenStudio.logFree(
      OpenStudio::Info,
      'openstudio.standards.Model', "#{scenario}: total_outdoor_airflow_rate_m_3_per_s = #{total_outdoor_airflow_rate_m_3_per_s}"
    )

    return total_outdoor_airflow_rate_m_3_per_s
  end

  def zone_ventilation_design_flow_rate_m3_per_s(zone_ventilation)
    return 0.0 unless zone_ventilation.thermalZone.is_initialized

    zone = zone_ventilation.thermalZone.get
    area = zone.floorArea
    volume = zone.airVolume
    people = zone.numberOfPeople
    case zone_ventilation.designFlowRateCalculationMethod
    when 'Flow/Area'
      zone_ventilation.flowRateperZoneFloorArea.to_f * area
    when 'Flow/Person'
      zone_ventilation.flowRateperPerson.to_f * people
    when 'AirChanges/Hour'
      zone_ventilation.airChangesperHour.to_f * volume / 3600.0
    when 'Flow/Zone'
      zone_ventilation.designFlowRate.to_f
    else
      0.0
    end
  end

  def get_zone_level_outdoor_airflow_rate(model)
    outdoor_airflow_rate_m_3_per_s = 0.0
    seen_zone_ventilation_signatures = {}
    model.getThermalZones.sort.each do |zone|
      zone.equipment.each do |zone_equipment|
        handled = false
        obj_types_to_check = [
          :to_ZoneHVACPackagedTerminalAirConditioner,
          :to_ZoneHVACPackagedTerminalHeatPump,
          :to_ZoneHVACWaterToAirHeatPump,
          :to_ZoneHVACFourPipeFanCoil,
          :to_ZoneHVACTerminalUnitVariableRefrigerantFlow
        ]
        obj_types_to_check.each do |meth|
          next unless zone_equipment.respond_to?(meth) && zone_equipment.send(meth).is_initialized

          zone_hvac = zone_equipment.send(meth).get
          oa_rate = if meth == :to_ZoneHVACFourPipeFanCoil
                      zone_hvac.maximumOutdoorAirFlowRate
                    else
                      zone_hvac.outdoorAirFlowRateDuringCoolingOperation
                    end

          if oa_rate.is_initialized
            outdoor_airflow_rate_m_3_per_s += oa_rate.get
          elsif meth == :to_ZoneHVACFourPipeFanCoil &&
                zone_hvac.respond_to?(:isMaximumOutdoorAirFlowRateAutosized) &&
                zone_hvac.isMaximumOutdoorAirFlowRateAutosized &&
                zone_hvac.respond_to?(:autosizedMaximumOutdoorAirFlowRate) &&
                zone_hvac.autosizedMaximumOutdoorAirFlowRate.is_initialized
            outdoor_airflow_rate_m_3_per_s += zone_hvac.autosizedMaximumOutdoorAirFlowRate.get
          elsif zone_hvac.respond_to?(:autosizedCoolingOutdoorAirFlowRate) &&
                zone_hvac.autosizedCoolingOutdoorAirFlowRate.is_initialized
            outdoor_airflow_rate_m_3_per_s += zone_hvac.autosizedCoolingOutdoorAirFlowRate.get
          end
          handled = true
          break
        end

        next if handled
        next unless zone_equipment.to_ZoneVentilationDesignFlowRate.is_initialized

        zone_ventilation = zone_equipment.to_ZoneVentilationDesignFlowRate.get
        flow_rate = zone_ventilation_design_flow_rate_m3_per_s(zone_ventilation)
        normalized_name = zone_ventilation.nameString.gsub(/\s+\d+$/, '')
        signature = [
          zone.handle.to_s,
          normalized_name,
          zone_ventilation.ventilationType,
          zone_ventilation.designFlowRateCalculationMethod,
          flow_rate.round(6)
        ]
        next if seen_zone_ventilation_signatures[signature]

        seen_zone_ventilation_signatures[signature] = true
        outdoor_airflow_rate_m_3_per_s += flow_rate
      end
    end
    return outdoor_airflow_rate_m_3_per_s
  end

  def _scaled_value(object, value_method, autosized_method, scaling_factor)
    if object.respond_to?(value_method)
      value_optional = object.send(value_method)
      return value_optional.get * scaling_factor if value_optional.is_initialized
    end
    if !autosized_method.nil? && object.respond_to?(autosized_method)
      autosized_optional = object.send(autosized_method)
      return autosized_optional.get * scaling_factor if autosized_optional.is_initialized
    end

    return nil
  end

  def scale_zone_ventilation_design_flow_rate(zone_ventilation, scaling_factor)
    case zone_ventilation.designFlowRateCalculationMethod
    when 'Flow/Area'
      zone_ventilation.setFlowRateperZoneFloorArea(zone_ventilation.flowRateperZoneFloorArea.to_f * scaling_factor)
    when 'Flow/Person'
      zone_ventilation.setFlowRateperPerson(zone_ventilation.flowRateperPerson.to_f * scaling_factor)
    when 'AirChanges/Hour'
      zone_ventilation.setAirChangesperHour(zone_ventilation.airChangesperHour.to_f * scaling_factor)
    when 'Flow/Zone'
      zone_ventilation.setDesignFlowRate(zone_ventilation.designFlowRate.to_f * scaling_factor)
    else
      msg = "Unsupported ZoneVentilationDesignFlowRate calculation method '#{zone_ventilation.designFlowRateCalculationMethod}' for '#{zone_ventilation.nameString}'."
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', msg)
      raise msg
    end
  end

  def scale_zone_level_outdoor_airflow_rates(model, scaling_factor)
    model.getThermalZones.sort.each do |zone|
      zone.equipment.each do |zone_equipment|
        if zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          zone_hvac = zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.get
          cooling_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringCoolingOperation, :autosizedCoolingOutdoorAirFlowRate, scaling_factor)
          heating_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringHeatingOperation, :autosizedHeatingOutdoorAirFlowRate, scaling_factor)
          no_load_value = _scaled_value(zone_hvac, :outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded, :autosizedNoLoadOutdoorAirFlowRate, scaling_factor)
          zone_hvac.setOutdoorAirFlowRateDuringCoolingOperation(cooling_value) unless cooling_value.nil?
          zone_hvac.setOutdoorAirFlowRateDuringHeatingOperation(heating_value) unless heating_value.nil?
          zone_hvac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(no_load_value) unless no_load_value.nil?
        elsif zone_equipment.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
          zone_hvac = zone_equipment.to_ZoneHVACPackagedTerminalHeatPump.get
          cooling_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringCoolingOperation, :autosizedCoolingOutdoorAirFlowRate, scaling_factor)
          heating_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringHeatingOperation, :autosizedHeatingOutdoorAirFlowRate, scaling_factor)
          no_load_value = _scaled_value(zone_hvac, :outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded, :autosizedNoLoadOutdoorAirFlowRate, scaling_factor)
          zone_hvac.setOutdoorAirFlowRateDuringCoolingOperation(cooling_value) unless cooling_value.nil?
          zone_hvac.setOutdoorAirFlowRateDuringHeatingOperation(heating_value) unless heating_value.nil?
          zone_hvac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(no_load_value) unless no_load_value.nil?
        elsif zone_equipment.to_ZoneHVACWaterToAirHeatPump.is_initialized
          zone_hvac = zone_equipment.to_ZoneHVACWaterToAirHeatPump.get
          cooling_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringCoolingOperation, :autosizedCoolingOutdoorAirFlowRate, scaling_factor)
          heating_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringHeatingOperation, :autosizedHeatingOutdoorAirFlowRate, scaling_factor)
          no_load_value = _scaled_value(zone_hvac, :outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded, :autosizedNoLoadOutdoorAirFlowRate, scaling_factor)
          zone_hvac.setOutdoorAirFlowRateDuringCoolingOperation(cooling_value) unless cooling_value.nil?
          zone_hvac.setOutdoorAirFlowRateDuringHeatingOperation(heating_value) unless heating_value.nil?
          zone_hvac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(no_load_value) unless no_load_value.nil?
        elsif zone_equipment.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
          zone_hvac = zone_equipment.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
          cooling_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringCoolingOperation, :autosizedCoolingOutdoorAirFlowRate, scaling_factor)
          heating_value = _scaled_value(zone_hvac, :outdoorAirFlowRateDuringHeatingOperation, :autosizedHeatingOutdoorAirFlowRate, scaling_factor)
          no_load_value = _scaled_value(zone_hvac, :outdoorAirFlowRateWhenNoCoolingorHeatingisNeeded, :autosizedNoLoadOutdoorAirFlowRate, scaling_factor)
          zone_hvac.setOutdoorAirFlowRateDuringCoolingOperation(cooling_value) unless cooling_value.nil?
          zone_hvac.setOutdoorAirFlowRateDuringHeatingOperation(heating_value) unless heating_value.nil?
          zone_hvac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(no_load_value) unless no_load_value.nil?
        elsif zone_equipment.to_ZoneHVACFourPipeFanCoil.is_initialized
          zone_hvac = zone_equipment.to_ZoneHVACFourPipeFanCoil.get
          max_oa_value = _scaled_value(zone_hvac, :maximumOutdoorAirFlowRate, :autosizedMaximumOutdoorAirFlowRate, scaling_factor)
          zone_hvac.setMaximumOutdoorAirFlowRate(max_oa_value) unless max_oa_value.nil?
        elsif zone_equipment.to_ZoneVentilationDesignFlowRate.is_initialized
          scale_zone_ventilation_design_flow_rate(zone_equipment.to_ZoneVentilationDesignFlowRate.get, scaling_factor)
        end
      end
    end
  end

  # get minimum outdoor airflow rate from Controller:OutdoorAir
  # adjust design outdoor airflow rate in Sizing:System
  # @param model [object]
  def consistent_outdoor_airflow_rate(model)
    model.getAirLoopHVACs.each do |air_loop|
      # Skip if no outdoor air system
      next if air_loop.airLoopHVACOutdoorAirSystem.empty?

      # Get the outdoor air system and controller
      air_loop_hvac_oasys = air_loop.airLoopHVACOutdoorAirSystem.get
      controller_oa = air_loop_hvac_oasys.getControllerOutdoorAir
      sizing_system = air_loop.sizingSystem

      # get minimum outdoor airflow rate from Controller:OutdoorAir
      minimum_outdoor_airflow_rate_m_3_per_s = nil
      if controller_oa.minimumOutdoorAirFlowRate.is_initialized
        minimum_outdoor_airflow_rate_m_3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
      elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        minimum_outdoor_airflow_rate_m_3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
      else
        # making it fail for now to test later
        msg = "Cannot get minimum outdoor airflow rate from air loop hvac '#{air_loop.nameString}'."
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', msg)
        raise msg
      end

      # get existing outdoor airflow rate from Sizing:System
      minimum_outdoor_airflow_rate_m_3_per_s_old = nil
      if sizing_system.designOutdoorAirFlowRate.is_initialized
        minimum_outdoor_airflow_rate_m_3_per_s_old = sizing_system.designOutdoorAirFlowRate.get
      elsif sizing_system.autosizedDesignOutdoorAirFlowRate.is_initialized
        minimum_outdoor_airflow_rate_m_3_per_s_old = sizing_system.autosizedDesignOutdoorAirFlowRate.get
      end

      # force the above value to Sizing:System
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', 'Forcing OA rate to Sizing:System based on Controller:OutdoorAir  ' \
                                                                         "| old value = #{minimum_outdoor_airflow_rate_m_3_per_s_old} | new value = #{minimum_outdoor_airflow_rate_m_3_per_s}")
      sizing_system.setDesignOutdoorAirFlowRate(minimum_outdoor_airflow_rate_m_3_per_s)
    end
  end

  # Template method for evaluate DCV requirements in the user model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @return [Boolean] returns true if successful, false if not
  def model_evaluate_dcv_requirements(model)
    model_mark_zone_dcv_existence(model)
    model_add_dcv_user_exception_properties(model)
    model_add_dcv_requirement_properties(model)
    model_add_apxg_dcv_properties(model)
    model_raise_user_model_dcv_errors(model)
    return true
  end

  # https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/ashrae_90_1_prm/ashrae_90_1_prm.Model.rb#L1180
  # Add zone additional property "zone DCV implemented in user model":
  #   - 'true' if zone OA flow requirement is specified as per person & airloop supporting this zone has DCV enabled
  #   - 'false' otherwise
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @return [Boolean] returns true if successful, false if not
  def model_mark_zone_dcv_existence(model)
    model.getAirLoopHVACs.each do |air_loop_hvac|
      next unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized

      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      controller_mv = controller_oa.controllerMechanicalVentilation
      next unless controller_mv.demandControlledVentilation == true

      air_loop_hvac.thermalZones.each do |thermal_zone|
        zone_dcv = false
        thermal_zone.spaces.each do |space|
          dsn_oa = space.designSpecificationOutdoorAir
          next if dsn_oa.empty?

          dsn_oa = dsn_oa.get
          next if dsn_oa.outdoorAirMethod == 'Maximum'

          if dsn_oa.outdoorAirFlowperPerson > 0
            # only in this case the thermal zone is considered to be implemented with DCV
            zone_dcv = true
          end
        end

        if zone_dcv
          thermal_zone.additionalProperties.setFeature('zone DCV implemented in user model', true)
        end
      end
    end

    # mark unmarked zones
    model.getThermalZones.each do |zone|
      next if zone.additionalProperties.hasFeature('zone DCV implemented in user model')

      zone.additionalProperties.setFeature('zone DCV implemented in user model', false)
    end

    return true
  end

  # https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/ashrae_90_1_prm/ashrae_90_1_prm.Model.rb#L1226
  # read user data and add to zone additional properties
  # "airloop user specified DCV exception"
  # "one user specified DCV exception"
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model
  def model_add_dcv_user_exception_properties(model)
    model.getAirLoopHVACs.each do |air_loop_hvac|
      dcv_airloop_user_exception = false
      if standards_data.key?('userdata_airloop_hvac')
        standards_data['userdata_airloop_hvac'].each do |row|
          next unless row['name'].to_s.downcase.strip == air_loop_hvac.name.to_s.downcase.strip

          if row['dcv_exception_airloop'].to_s.upcase.strip == 'TRUE'
            dcv_airloop_user_exception = true
            break
          end
        end
      end
      air_loop_hvac.thermalZones.each do |thermal_zone|
        if dcv_airloop_user_exception
          thermal_zone.additionalProperties.setFeature('airloop user specified DCV exception', true)
        end
      end
    end

    # zone level exception tagging is put outside of airloop because it directly reads from user data and
    # a zone not under an airloop in user model may be in an airloop in baseline
    model.getThermalZones.each do |thermal_zone|
      dcv_zone_user_exception = false
      if standards_data.key?('userdata_thermal_zone')
        standards_data['userdata_thermal_zone'].each do |row|
          next unless row['name'].to_s.downcase.strip == thermal_zone.name.to_s.downcase.strip

          if row['dcv_exception_thermal_zone'].to_s.upcase.strip == 'TRUE'
            dcv_zone_user_exception = true
            break
          end
        end
      end
      if dcv_zone_user_exception
        thermal_zone.additionalProperties.setFeature('zone user specified DCV exception', true)
      end
    end

    # mark unmarked zones
    # rubocop:disable Style/CombinableLoops
    model.getThermalZones.each do |zone|
      unless zone.additionalProperties.hasFeature('airloop user specified DCV exception')
        zone.additionalProperties.setFeature('airloop user specified DCV exception', false)
      end

      unless zone.additionalProperties.hasFeature('zone user specified DCV exception')
        zone.additionalProperties.setFeature('zone user specified DCV exception', false)
      end
    end
    # rubocop:enable Style/CombinableLoops
  end

  # https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/ashrae_90_1_prm/ashrae_90_1_prm.Model.rb#L1286
  # add zone additional property "airloop dcv required by 901"
  # - "true" if the airloop supporting this zone is required by 90.1 (non-exception requirement + user provided exception flag) to have DCV regarding user model
  # - "false" otherwise
  # add zone additional property "zone dcv required by 901"
  # - "true" if the zone is required by 90.1(non-exception requirement + user provided exception flag) to have DCV regarding user model
  # - 'flase' otherwise
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model
  def model_add_dcv_requirement_properties(model)
    model.getAirLoopHVACs.each do |air_loop_hvac|
      if user_model_air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac)
        air_loop_hvac.thermalZones.each do |thermal_zone|
          thermal_zone.additionalProperties.setFeature('airloop dcv required by 901', true)

          # the zone level dcv requirement can only be true if it is in an airloop that is required to have DCV
          if user_model_zone_demand_control_ventilation_required?(thermal_zone)
            thermal_zone.additionalProperties.setFeature('zone dcv required by 901', true)
          end
        end
      end
    end

    # mark unmarked zones
    model.getThermalZones.each do |zone|
      unless zone.additionalProperties.hasFeature('airloop dcv required by 901')
        zone.additionalProperties.setFeature('airloop dcv required by 901', false)
      end

      unless zone.additionalProperties.hasFeature('zone dcv required by 901')
        zone.additionalProperties.setFeature('zone dcv required by 901', false)
      end
    end
  end

  # https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/ashrae_90_1_prm/ashrae_90_1_prm.Model.rb#L1319
  # based on previously added flag, raise error if DCV is required but not implemented in zones, in which case
  # baseline generation will be terminated; raise warning if DCV is not required but implemented, and continue baseline
  # generation
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @todo JXL add log msgs to PRM logger
  def model_raise_user_model_dcv_errors(model)
    model.getThermalZones.each do |thermal_zone|
      if thermal_zone.additionalProperties.getFeatureAsBoolean('zone DCV implemented in user model').get &&
         (!thermal_zone.additionalProperties.getFeatureAsBoolean('zone dcv required by 901').get ||
           !thermal_zone.additionalProperties.getFeatureAsBoolean('airloop dcv required by 901').get)
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "For thermal zone #{thermal_zone.name}, ASHRAE 90.1 2019 6.4.3.8 does NOT require this zone to have demand control ventilation, but it was implemented in the user model, Appendix G baseline generation will continue!")
        if thermal_zone.additionalProperties.hasFeature('apxg no need to have DCV') && !thermal_zone.additionalProperties.getFeatureAsBoolean('apxg no need to have DCV').get
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Moreover, for thermal zone #{thermal_zone.name}, Appendix G baseline model will have DCV based on ASHRAE 90.1 2019 G3.1.2.5")
        end
      end
      if thermal_zone.additionalProperties.getFeatureAsBoolean('zone dcv required by 901').get &&
         thermal_zone.additionalProperties.getFeatureAsBoolean('airloop dcv required by 901').get &&
         !thermal_zone.additionalProperties.getFeatureAsBoolean('zone DCV implemented in user model').get
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "For thermal zone #{thermal_zone.name}, ASHRAE 90.1 2019 6.4.3.8 requires this zone to have demand control ventilation, but it was not implemented in the user model, Appendix G baseline generation should be terminated!")
      end
    end
  end

  # https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/ashrae_90_1_prm/ashrae_90_1_prm.Model.rb#L1344
  # Check if zones in the baseline model (to be created) should have DCV based on 90.1 2019 G3.1.2.5. Zone additional
  # property 'apxg no need to have DCV' added
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model
  def model_add_apxg_dcv_properties(model)
    model.getAirLoopHVACs.each do |air_loop_hvac|
      if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
        oa_flow_m3_per_s = get_airloop_hvac_design_oa_from_sql(air_loop_hvac)
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, DCV not applicable because it has no OA intake.")
        return false
      end
      # oa_flow_m3_per_s can be false if the sizing run failed or sql not avail
      if oa_flow_m3_per_s == false
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, DCV not applicable because oa_flow_m3_per_s is FALSE.")
        return false
      else
        oa_flow_cfm = OpenStudio.convert(oa_flow_m3_per_s, 'm^3/s', 'cfm').get
      end
      if oa_flow_cfm <= 3000
        air_loop_hvac.thermalZones.each do |thermal_zone|
          thermal_zone.additionalProperties.setFeature('apxg no need to have DCV', true)
        end
      else # oa_flow_cfg > 3000, check zone people density
        air_loop_hvac.thermalZones.each do |thermal_zone|
          area_served_m2 = 0
          num_people = 0
          thermal_zone.spaces.each do |space|
            area_served_m2 += space.floorArea
            num_people += space.numberOfPeople
          end
          area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get
          occ_per_1000_ft2 = num_people / area_served_ft2 * 1000
          if occ_per_1000_ft2 <= 40
            thermal_zone.additionalProperties.setFeature('apxg no need to have DCV', true)
          else
            thermal_zone.additionalProperties.setFeature('apxg no need to have DCV', false)
          end
        end
      end
    end
    # if a zone does not have this additional property, it means it was not served by airloop.
  end

  # Convert total minimum OA requirement to a per-area value.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
  # @return [Boolean] returns true if successful, false if not
  def thermal_zone_convert_outdoor_air_to_per_area(thermal_zone)
    # For each space in the zone, convert
    # all design OA to per-area
    # unless the "Outdoor Air Method" is "Maximum"
    thermal_zone.spaces.each do |space|
      # Find the design OA, which may be assigned at either the
      # SpaceType or directly at the Space
      dsn_oa = space.designSpecificationOutdoorAir
      next if dsn_oa.empty?

      dsn_oa = dsn_oa.get
      next if dsn_oa.outdoorAirMethod == 'Maximum'

      # Get the space properties
      floor_area = space.floorArea
      number_of_people = space.numberOfPeople
      volume = space.volume

      # Sum up the total OA from all sources
      oa_for_people = number_of_people * dsn_oa.outdoorAirFlowperPerson
      oa_for_floor_area = floor_area * dsn_oa.outdoorAirFlowperFloorArea
      oa_rate = dsn_oa.outdoorAirFlowRate
      oa_for_volume = volume * dsn_oa.outdoorAirFlowAirChangesperHour / 3600
      tot_oa = oa_for_people + oa_for_floor_area + oa_rate + oa_for_volume

      # Convert total to per-area
      tot_oa_per_area = tot_oa / floor_area

      # Check if there is another design OA object that has already
      # been converted from per-person to per-area that matches.
      # If so, reuse that instead of creating a duplicate.
      new_dsn_oa_name = "#{dsn_oa.name} to per-area"
      if thermal_zone.model.getDesignSpecificationOutdoorAirByName(new_dsn_oa_name).is_initialized
        new_dsn_oa = thermal_zone.model.getDesignSpecificationOutdoorAirByName(new_dsn_oa_name).get
      else
        new_dsn_oa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(thermal_zone.model)
        new_dsn_oa.setName(new_dsn_oa_name)
      end

      # Assign this new design OA to the space
      space.setDesignSpecificationOutdoorAir(new_dsn_oa)

      # Set the method
      new_dsn_oa.setOutdoorAirMethod('Sum')
      # Set the per-area requirement
      new_dsn_oa.setOutdoorAirFlowperFloorArea(tot_oa_per_area)
      # Zero-out the per-person, ACH, and flow requirements
      new_dsn_oa.setOutdoorAirFlowperPerson(0.0)
      new_dsn_oa.setOutdoorAirFlowAirChangesperHour(0.0)
      new_dsn_oa.setOutdoorAirFlowRate(0.0)
      # Copy the orignal OA schedule, if any
      if dsn_oa.outdoorAirFlowRateFractionSchedule.is_initialized
        oa_sch = dsn_oa.outdoorAirFlowRateFractionSchedule.get
        new_dsn_oa.setOutdoorAirFlowRateFractionSchedule(oa_sch)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ThermalZone', "For #{thermal_zone.name}: Converted total ventilation requirements to per-area value.")
    end

    return true
  end

  # https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/ashrae_90_1_prm/ashrae_90_1_prm.Model.rb#L1382
  # Set DCV in baseline HVAC system if required
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model
  def model_set_baseline_demand_control_ventilation(model, climate_zone)
    model.getAirLoopHVACs.each do |air_loop_hvac|
      if baseline_air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac)
        air_loop_hvac_enable_demand_control_ventilation(air_loop_hvac, climate_zone)
        air_loop_hvac.thermalZones.sort.each do |zone|
          unless baseline_thermal_zone_demand_control_ventilation_required?(zone)
            thermal_zone_convert_outdoor_air_to_per_area(zone)
          end
        end
      end
    end
  end

  # Applies the HVAC parts of the template to all objects in the model using the the template specified in the model.
  # for 179D, only apply DCV in baseline and not in proposed
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param apply_controls [Bool] toggle whether to apply air loop and plant loop controls
  # @param sql_db_vars_map [Hash] hash map
  # @param necb_ref_hp [Bool] for compatability with NECB ruleset only.
  # @return [Bool] returns true if successful, false if not
  def model_apply_hvac_efficiency_standard(model, climate_zone, baseline_179d, apply_controls: true, sql_db_vars_map: nil, necb_ref_hp: false)
    sql_db_vars_map = {} if sql_db_vars_map.nil?

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Started applying HVAC efficiency standards for #{template} template.")

    # Air Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getAirLoopHVACs.sort.each { |obj| air_loop_hvac_apply_standard_controls(obj, climate_zone, baseline_179d) }
    end

    # Plant Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getPlantLoops.sort.each { |obj| plant_loop_apply_standard_controls(obj, climate_zone) }
    end

    # Zone HVAC Controls
    model.getZoneHVACComponents.sort.each { |obj| zone_hvac_component_apply_standard_controls(obj) }

    ##### Apply equipment efficiencies

    # Fans
    model.getFanVariableVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanConstantVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanOnOffs.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanZoneExhausts.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }

    # Pumps
    model.getPumpConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getPumpVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getHeaderedPumpsConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getHeaderedPumpsVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }

    # Unitary HPs
    # set DX HP coils before DX clg coils because when DX HP coils need to first
    # pull the capacities of their paired DX clg coils, and this does not work
    # correctly if the DX clg coil efficiencies have been set because they are renamed.
    model.getCoilHeatingDXSingleSpeeds.sort.each { |obj| sql_db_vars_map = coil_heating_dx_single_speed_apply_efficiency_and_curves(obj, sql_db_vars_map, necb_ref_hp) }

    # Unitary ACs
    model.getCoilCoolingDXTwoSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_two_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingDXSingleSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_single_speed_apply_efficiency_and_curves(obj, sql_db_vars_map, necb_ref_hp) }
    model.getCoilCoolingDXMultiSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_multi_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # WSHPs
    # set WSHP heating coils before cooling coils to get cooling coil capacities before they are renamed
    model.getCoilHeatingWaterToAirHeatPumpEquationFits.sort.each { |obj| sql_db_vars_map = coil_heating_water_to_air_heat_pump_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each { |obj| sql_db_vars_map = coil_cooling_water_to_air_heat_pump_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # Chillers
    clg_tower_objs = model.getCoolingTowerSingleSpeeds
    model.getChillerElectricEIRs.sort.each { |obj| chiller_electric_eir_apply_efficiency_and_curves(obj, clg_tower_objs) }

    # Boilers
    model.getBoilerHotWaters.sort.each { |obj| boiler_hot_water_apply_efficiency_and_curves(obj) }

    # Water Heaters
    model.getWaterHeaterMixeds.sort.each { |obj| water_heater_mixed_apply_efficiency(obj) }

    # Cooling Towers
    model.getCoolingTowerSingleSpeeds.sort.each { |obj| cooling_tower_single_speed_apply_efficiency_and_curves(obj) }
    model.getCoolingTowerTwoSpeeds.sort.each { |obj| cooling_tower_two_speed_apply_efficiency_and_curves(obj) }
    model.getCoolingTowerVariableSpeeds.sort.each { |obj| cooling_tower_variable_speed_apply_efficiency_and_curves(obj) }

    # Fluid Coolers
    model.getFluidCoolerSingleSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Dry Cooler') }
    model.getFluidCoolerTwoSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Dry Cooler') }
    model.getEvaporativeFluidCoolerSingleSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Closed Cooling Tower') }
    model.getEvaporativeFluidCoolerTwoSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Closed Cooling Tower') }

    # ERVs
    model.getHeatExchangerAirToAirSensibleAndLatents.each { |obj| heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness(obj) }

    # Gas Heaters
    model.getCoilHeatingGass.sort.each { |obj| coil_heating_gas_apply_efficiency_and_curves(obj) }
    model.getCoilHeatingGasMultiStages.each { |obj| coil_heating_gas_multi_stage_apply_efficiency_and_curves(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Finished applying HVAC efficiency standards for #{template} template.")
    return true
  end

  # 179D ACM mandates that Kitchen, Restroom, and Cafeteria zone exhaust fans
  # operate on the building's HVAC operation schedule (per IRS Notice 2006-52
  # §3.03 / CA 2005 ACM Tables N2-2..N2-9), not the always-on default that
  # OpenstudioStandards::HVAC.create_exhaust_fan applies in standards 0.8.x.
  # Call super for the stock fan creation (sized from typical_exhaust.csv,
  # transfer-air zone mixing if applicable), then replace availability and
  # flow-fraction schedules on those three space types with the ACM schedule.
  #
  # Replaces the v0.4-era thermal_zone_add_exhaust override (dead under 0.8
  # because exhaust creation moved to a module function that doesn't dispatch
  # through Standard inheritance).
  ACM_EXHAUST_SPACE_TYPES = ['Kitchen', 'Restroom', 'Cafeteria'].freeze

  def model_add_exhaust(model, makeup_source: 'None', remove_existing_exhaust_fans: true)
    zone_exhaust_fans = super
    return zone_exhaust_fans if zone_exhaust_fans.empty?

    data = model_get_standards_data(model, throw_if_not_found: true)
    acm_fan_sch_name = data['hvac_operation_schedule']
    return zone_exhaust_fans if acm_fan_sch_name.nil?

    acm_fan_sch = model_add_schedule(model, acm_fan_sch_name)
    return zone_exhaust_fans if acm_fan_sch.nil?

    zone_exhaust_fans.each do |fan|
      next unless fan.thermalZone.is_initialized

      zone = fan.thermalZone.get
      next unless zone.spaces.any? do |s|
        s.spaceType.is_initialized && s.spaceType.get.standardsSpaceType.is_initialized &&
        ACM_EXHAUST_SPACE_TYPES.include?(s.spaceType.get.standardsSpaceType.get)
      end

      fan.setAvailabilitySchedule(acm_fan_sch)
      fan.setFlowFractionSchedule(acm_fan_sch)
      OpenStudio.logFree(OpenStudio::Info, '179d.standards.Model',
                         "Set ACM exhaust schedule '#{acm_fan_sch_name}' on '#{fan.name}' (179D override of v0.8 alwaysOn default)")

      # Balance kitchen/restroom/cafeteria exhaust with explicit makeup OA.
      # For these zones the exhaust hood pulls a fixed-flow amount that VAV
      # supply at low cooling/heating demand cannot match. Without explicit
      # makeup-air modeling EnergyPlus emits "Load due to induced outdoor air
      # is neglected" and silently drops the heat load — zone goes under-setpoint.
      # Fix:
      #   1. Add SpaceInfiltrationDesignFlowRate = exhaust max, scheduled to the
      #      exhaust availability schedule, so EP accounts for the makeup OA load.
      #   2. Set BalancedExhaustFractionSchedule = always-on so EP treats the
      #      exhaust as balanced (no neglected induced OA term) and uses the
      #      infiltration as the canonical makeup path.
      # For VAV:Reheat terminals also set cooling minimum = exhaust max so the
      # supply system can deliver the extra mass flow during cooking peak.
      # Do NOT cap max airflow or heating sizing — let autosize converge.
      next unless fan.maximumFlowRate.is_initialized

      maximum_flow_rate_si = fan.maximumFlowRate.get
      space = zone.spaces.first

      air_terminal = zone.airLoopHVACTerminal
      if air_terminal.is_initialized && air_terminal.get.to_AirTerminalSingleDuctVAVReheat.is_initialized
        sz = zone.sizingZone
        sz.setCoolingDesignAirFlowMethod('DesignDayWithLimit')
        sz.setCoolingMinimumAirFlow(maximum_flow_rate_si)
      end

      makeup_infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
      makeup_infiltration.setName("#{fan.name} Makeup infil")
      makeup_infiltration.setDesignFlowRate(maximum_flow_rate_si)
      makeup_infiltration.setSpace(space)
      makeup_infiltration.setSchedule(acm_fan_sch)
      fan.setBalancedExhaustFractionSchedule(model.alwaysOnDiscreteSchedule)
      OpenStudio.logFree(OpenStudio::Info, '179d.standards.Model',
                         "Added makeup infiltration '#{makeup_infiltration.name}' (#{maximum_flow_rate_si.round(4)} m\u00b3/s) and balanced-exhaust flag on '#{fan.name}'.")
    end

    zone_exhaust_fans
  end
end
# rubocop:enable Metrics/ClassLength
