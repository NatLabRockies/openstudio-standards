class ASHRAE901PRM < Standard
  # @!group Model

  # Returns the PRM building envelope infiltration rate at a pressure differential of 75 Pa in cfm per ft^2
  # @return [Double] infiltration rate in cfm per ft^2 at 75 Pa
  def prm_building_envelope_infiltration_rate
    return 1.0
  end

  # Determines which system number is used for the baseline system.
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] the system number: 1_or_2, 3_or_4, 5_or_6, 7_or_8, 9_or_10
  def model_prm_baseline_system_number(model, climate_zone, area_type, fuel_type, area_ft2, num_stories, custom)
    sys_num = nil

    # Customization - Xcel EDA Program Manual 2014
    # Table 3.2.2 Baseline HVAC System Types
    if custom == 'Xcel Energy CO EDA'
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', 'Custom; per Xcel EDA Program Manual 2014 Table 3.2.2 Baseline HVAC System Types, the 90.1-2010 lookup for HVAC system types shall be used.')

      # Set the area limit
      limit_ft2 = 25_000

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

    else

      # Set the area limit
      limit_ft2 = 25_000

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
        sys_num = '3_or_4'
      end

    end

    return sys_num
  end

  # Change the fuel type based on climate zone, depending on the standard.
  # For 90.1-2013, fuel type is based on climate zone, not the proposed model.
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param fuel_type [String] Valid choices are electric, fossil, fossilandelectric,
  #   purchasedheat, purchasedcooling, purchasedheatandcooling
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] the revised fuel type
  def model_prm_baseline_system_change_fuel_type(model, fuel_type, climate_zone)
    # For 90.1-2013 the fuel type is determined based on climate zone.
    # Don't change the fuel if it purchased heating or cooling.
    if fuel_type == 'electric' || fuel_type == 'fossil'
      case climate_zone
      when 'ASHRAE 169-2006-1A',
           'ASHRAE 169-2006-2A',
           'ASHRAE 169-2006-3A',
           'ASHRAE 169-2013-1A',
           'ASHRAE 169-2013-2A',
           'ASHRAE 169-2013-3A'
        fuel_type = 'electric'
      else
        fuel_type = 'fossil'
      end
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Heating fuel is #{fuel_type} for 90.1-2013, climate zone #{climate_zone}.  This is independent of the heating fuel type in the proposed building, per G3.1.1-3.  This is different than previous versions of 90.1.")
    end

    return fuel_type
  end

  # Determines the fan type used by VAV_Reheat and VAV_PFP_Boxes systems.
  # Variable speed fan for 90.1-2019
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] the fan type: TwoSpeed Fan, Variable Speed Fan
  def model_baseline_system_vav_fan_type(model)
    fan_type = 'Variable Speed Fan'
    return fan_type
  end

  # This method creates customized infiltration objects for each space and removes the SpaceType-level infiltration objects.
  # @param model [OpenStudio::Model::Model] openstudio model
  # @param infiltration_rate [Double] space infiltration rate at a pressure differential of 75 Pa in cfm per ft^2
  # @return [Boolean] true if successful, false if not
  def model_apply_standard_infiltration(model, infiltration_rate: prm_building_envelope_infiltration_rate)
    # Model shouldn't use SpaceInfiltrationEffectiveLeakageArea
    # Excerpt from the EnergyPlus Input/Output reference manual:
    #     "This model is based on work by Sherman and Grimsrud (1980)
    #     and is appropriate for smaller, residential-type buildings."
    # Raise exception if the model does use this object
    ela = 0
    model.getSpaceInfiltrationEffectiveLeakageAreas.sort.each do |eff_la|
      ela += 1
    end
    if ela > 0
      OpenStudio.logFree(OpenStudio::Warn, 'prm.log', 'The current model cannot include SpaceInfiltrationEffectiveLeakageArea. These objects will be skipped in modeling infiltration according to the 90.1-PRM rules.')
    end

    # Get the space building envelope area
    building_envelope_area_m2 = OpenstudioStandards::Geometry.model_get_envelope_area(model)
    prm_raise(building_envelope_area_m2 > 0.0, @sizing_run_dir, 'Calculated building envelope area is 0 m2, Please check model inputs.')

    # Calculate current model air leakage rate @ 75 Pa and report it
    curr_tot_infil_m3_per_s_per_envelope_area = model_current_building_envelope_infiltration_at_75pa(model, building_envelope_area_m2)
    OpenStudio.logFree(OpenStudio::Info, 'prm.log', "The model's I_75Pa is estimated to be #{curr_tot_infil_m3_per_s_per_envelope_area} m3/s per m2 of total building envelope.")

    # Calculate building adjusted building envelope air infiltration following the 90.1 PRM rules
    tot_infil_m3_per_s = model_adjusted_building_envelope_infiltration(building_envelope_area_m2, infiltration_rate: infiltration_rate)

    # Find infiltration method used in the model, if any.
    #
    # If multiple methods are used, use per above grade wall
    # area (i.e. exterior wall area), if air/changes per hour
    # or exterior surface area is used, use Flow/ExteriorWallArea
    infil_method = model_get_infiltration_method(model)
    infil_method = 'Flow/ExteriorWallArea' if infil_method != 'Flow/Area' || infil_method != 'Flow/ExteriorWallArea'
    infil_coefficients = model_get_infiltration_coefficients(model)

    # Set the infiltration rate at each space
    model.getSpaces.each do |space|
      space_apply_infiltration_rate(space, tot_infil_m3_per_s, infil_method, infil_coefficients)
    end

    # Remove infiltration rates set at the space type
    model.getSpaceTypes.each do |space_type|
      space_type.spaceInfiltrationDesignFlowRates.each(&:remove)
    end

    return true
  end

  # This method retrieves the type of infiltration input
  # used in the model. If input is inconsistent, returns
  # Flow/Area
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] infiltration input type
  def model_get_infiltration_method(model)
    infil_method = nil
    model.getSpaces.each do |space|
      # Infiltration at the space level
      unless space.spaceInfiltrationDesignFlowRates.empty?
        old_infil = space.spaceInfiltrationDesignFlowRates[0]
        old_infil_method = old_infil.designFlowRateCalculationMethod.to_s
        # Return flow per space floor area if method is inconsistent in proposed model
        return 'Flow/Area' if infil_method != old_infil_method && !infil_method.nil?

        infil_method = old_infil_method
      end

      # Infiltration at the space type level
      if infil_method.nil? && space.spaceType.is_initialized
        space_type = space.spaceType.get
        unless space_type.spaceInfiltrationDesignFlowRates.empty?
          old_infil = space_type.spaceInfiltrationDesignFlowRates[0]
          old_infil_method = old_infil.designFlowRateCalculationMethod.to_s
          # Return flow per space floor area if method is inconsisten in proposed model
          return 'Flow/Area' if infil_method != old_infil_method && !infil_method.nil?

          infil_method = old_infil_method
        end
      end
    end

    return infil_method
  end

  # This method retrieves the infiltration coefficients
  # used in the model. If input is inconsitent, returns
  # [0, 0, 0.224, 0] as per PRM user manual
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] infiltration input type
  def model_get_infiltration_coefficients(model)
    cst = nil
    temp = nil
    vel = nil
    vel_2 = nil
    infil_coeffs = [cst, temp, vel, vel_2]
    model.getSpaces.each do |space|
      # Infiltration at the space level
      unless space.spaceInfiltrationDesignFlowRates.empty?
        old_infil = space.spaceInfiltrationDesignFlowRates[0]
        cst = old_infil.constantTermCoefficient
        temp = old_infil.temperatureTermCoefficient
        vel = old_infil.velocityTermCoefficient
        vel_2 = old_infil.velocitySquaredTermCoefficient
        old_infil_coeffs = [cst, temp, vel, vel_2] if !(cst.nil? && temp.nil? && vel.nil? && vel_2.nil?)
        # Return flow per space floor area if method is inconsistent in proposed model
        return [0.0, 0.0, 0.224, 0.0] if infil_coeffs != old_infil_coeffs && !(infil_coeffs[0].nil? &&
                                                                                    infil_coeffs[1].nil? &&
                                                                                    infil_coeffs[2].nil? &&
                                                                                    infil_coeffs[3].nil?)

        infil_coeffs = old_infil_coeffs
      end

      # Infiltration at the space type level
      if (infil_coeffs == [nil, nil, nil, nil]) && space.spaceType.is_initialized
        space_type = space.spaceType.get
        unless space_type.spaceInfiltrationDesignFlowRates.empty?
          old_infil = space_type.spaceInfiltrationDesignFlowRates[0]
          cst = old_infil.constantTermCoefficient
          temp = old_infil.temperatureTermCoefficient
          vel = old_infil.velocityTermCoefficient
          vel_2 = old_infil.velocitySquaredTermCoefficient
          old_infil_coeffs = [cst, temp, vel, vel_2] if !(cst.nil? && temp.nil? && vel.nil? && vel_2.nil?)
          # Return flow per space floor area if method is inconsistent in proposed model
          return [0.0, 0.0, 0.224, 0.0] unless infil_coeffs != old_infil_coeffs && !(infil_coeffs[0].nil? &&
                                                                                      infil_coeffs[1].nil? &&
                                                                                      infil_coeffs[2].nil? &&
                                                                                      infil_coeffs[3].nil?)

          infil_coeffs = old_infil_coeffs
        end
      end
    end
    return infil_coeffs
  end

  # This methods calculate the air leakage rate of a space
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [Double] Space air leakage rate
  def model_get_space_air_leakage(space)
    space_air_leakage = 0
    space_multipler = space.multiplier
    # Infiltration at the space level
    unless space.spaceInfiltrationDesignFlowRates.empty?
      space.spaceInfiltrationDesignFlowRates.each do |infil_obj|
        unless infil_obj.designFlowRate.is_initialized
          if infil_obj.flowperSpaceFloorArea.is_initialized
            space_air_leakage += infil_obj.flowperSpaceFloorArea.get * space.floorArea * space_multipler
          elsif infil_obj.flowperExteriorSurfaceArea.is_initialized
            space_air_leakage += infil_obj.flowperExteriorSurfaceArea.get * space.exteriorArea * space_multipler
          elsif infil_obj.flowperExteriorWallArea.is_initialized
            space_air_leakage += infil_obj.flowperExteriorWallArea.get * space.exteriorWallArea * space_multipler
          elsif infil_obj.airChangesperHour.is_initialized
            space_air_leakage += infil_obj.airChangesperHour.get * space.volume * space_multipler / 3600
          end
        end
      end
    end

    return space_air_leakage
  end

  # This methods calculate the current model air leakage rate @ 75 Pa.
  # It assumes that the model follows the PRM methods, see G3.1.1.4
  # in 90.1-2019 for reference.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio Model object
  # @param building_envelope_area_m2 [Double] Building envelope area as per 90.1 in m^2
  # @return [Double] building model air leakage rate
  def model_current_building_envelope_infiltration_at_75pa(model, building_envelope_area_m2)
    bldg_air_leakage_rate = 0
    model.getSpaces.each do |space|
      bldg_air_leakage_rate += model_get_space_air_leakage(space)
    end

    # adjust_infiltration_to_prototype_building_conditions(1) corresponds to the 0.112 shown in G3.1.1.4
    curr_tot_infil_m3_per_s_per_envelope_area = bldg_air_leakage_rate / OpenstudioStandards::Infiltration.adjust_infiltration_to_prototype_building_conditions(1) / building_envelope_area_m2
    return curr_tot_infil_m3_per_s_per_envelope_area
  end

  # Determine the total building baseline infiltration rate in cfm per ft2 of the building envelope at 75 Pa per the 90.1 PRM rules.
  #
  # @param building_envelope_area_m2 [Double] Building envelope area as per 90.1 in m^2
  # @param infiltration_rate [Double] Specific space infiltration rate at 75 pa in cfm per ft2
  # @return [Double] building envelope infiltration
  def model_adjusted_building_envelope_infiltration(building_envelope_area_m2, infiltration_rate: prm_building_envelope_infiltration_rate)
    # Conversion factor
    conv_fact = OpenStudio.convert(1.0, 'm^3/s', 'ft^3/min').get / OpenStudio.convert(1.0, 'm^2', 'ft^2').get

    # Adjust the infiltration rate to the average pressure for the prototype buildings.
    adj_infil_rate_cfm_per_ft2 = OpenstudioStandards::Infiltration.adjust_infiltration_to_prototype_building_conditions(infiltration_rate)
    adj_infil_rate_m3_per_s_per_m2 = adj_infil_rate_cfm_per_ft2 / conv_fact

    # Calculate the total infiltration
    tot_infil_m3_per_s = adj_infil_rate_m3_per_s_per_m2 * building_envelope_area_m2

    return tot_infil_m3_per_s
  end

  # Reduces the SRR to the values specified by the PRM. SRR reduction will be done by shrinking vertices toward the centroid.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_apply_prm_baseline_skylight_to_roof_ratio(model)
    # Loop through all spaces in the model, and
    # per the 90.1-2019 PRM User Manual, only
    # account for exterior roofs for enclosed
    # spaces. Include space multipliers.
    roof_m2 = 0.001 # Avoids divide by zero errors later
    sky_m2 = 0
    total_roof_m2 = 0.001
    total_subsurface_m2 = 0
    model.getSpaces.sort.each do |space|
      next if space_conditioning_category(space) == 'Unconditioned'

      # Loop through all surfaces in this space
      roof_area_m2 = 0
      sky_area_m2 = 0
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == 'RoofCeiling'

        # This roof's gross area (including skylight area)
        roof_area_m2 += surface.grossArea * space.multiplier
        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          next unless ss.subSurfaceType == 'Skylight'

          sky_area_m2 += ss.netArea * space.multiplier
        end
      end

      total_roof_m2 += roof_area_m2
      total_subsurface_m2 += sky_area_m2
    end

    # Calculate the SRR of each category
    srr = ((total_subsurface_m2 / total_roof_m2) * 100.0).round(1)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "The skylight to roof ratios (SRRs) is: : #{srr.round}%.")

    # SRR limit
    srr_lim = model_prm_skylight_to_roof_ratio_limit(model)

    # Check against SRR limit
    red = srr > srr_lim

    # Stop here unless skylights need reducing
    return true unless red

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Reducing the size of all skylights equally down to the limit of #{srr_lim.round}%.")

    # Determine the factors by which to reduce the skylight area
    mult = srr_lim / srr

    # Reduce the skylight area if any of the categories necessary
    model.getSpaces.sort.each do |space|
      next if space_conditioning_category(space) == 'Unconditioned'

      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == 'RoofCeiling'

        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          next unless ss.subSurfaceType == 'Skylight'

          # Reduce the size of the skylight
          red = 1.0 - mult
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(ss, red)
        end
      end
    end

    return true
  end

  # Apply baseline values to exterior lights objects
  # Characterization of objects must be done via user data
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def model_apply_baseline_exterior_lighting(model)
    model.getExteriorLightss.each do |ext_lights_obj|
      # Update existing exterior lights object: control, schedule, power
      ext_lights_obj.setControlOption('AstronomicalClock')
      ext_lights_obj.setSchedule(model.alwaysOnDiscreteSchedule)
      ext_lights_obj.setMultiplier(1)
      ext_lights_def = ext_lights_obj.exteriorLightsDefinition
      ext_ltg_pwr = get_additional_property_as_double(ext_lights_obj, 'design_level', 0.0)
      if ext_ltg_pwr > 0.0
        ext_lights_def.setDesignLevel(ext_ltg_pwr)
      end
    end
  end

  # Function to add baseline elevators based on user data
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def model_add_prm_elevators(model)
    # Load elevator data from userdata csv files
    equipment_array = model.getElectricEquipments + model.getExteriorFuelEquipments
    equipment_array.each do |equipment|
      elevator_number_of_lifts = get_additional_property_as_integer(equipment, 'elevator_number_of_lifts', 0)
      next unless elevator_number_of_lifts > 0.0

      elevator_name = equipment.name.get
      elevator_number_of_stories = get_additional_property_as_integer(equipment, 'elevator_number_of_stories', 0)
      elevator_weight_of_car = get_additional_property_as_double(equipment, 'elevator_weight_of_car', 0.0)
      elevator_rated_load = get_additional_property_as_double(equipment, 'elevator_rated_load', 0.0)
      elevator_speed_of_car = get_additional_property_as_double(equipment, 'elevator_speed_of_car', 0.0)
      elevator_counter_weight_of_car = get_additional_property_as_double(equipment, 'elevator_counter_weight_of_car', 0.0)

      if elevator_number_of_stories < 5
        # From Table G3.9.2 performance rating method baseline elevator motor
        elevator_mech_eff = 0.58
        elevator_counter_weight_of_car = 0.0
        search_criteria = {
          'template' => template,
          'type' => 'Hydraulic'
        }
      else
        # From Table G3.9.2 performance rating method baseline elevator motor
        elevator_mech_eff = 0.64
        # Determine the elevator counterweight
        if elevator_counter_weight_of_car < 0.001
          # When the proposed design counterweight is not specified
          # it is determined as per Table G3.9.2
          elevator_counter_weight_of_car = elevator_weight_of_car + (0.4 * elevator_rated_load)
        end
        search_criteria = {
          'template' => template
        }
      end
      elevator_motor_bhp = (elevator_weight_of_car + elevator_rated_load - elevator_counter_weight_of_car) * elevator_speed_of_car / (33000 * elevator_mech_eff) # Lookup the minimum motor efficiency
      elevator_motor_eff = standards_data['motors']
      motor_properties = model_find_object(elevator_motor_eff, search_criteria, nil, nil, nil, nil, elevator_motor_bhp)
      if motor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{elevator_name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{elevator_motor_bhp} hp.")
        return false
      end
      nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
      # Round to nearest whole HP for niceness
      if nominal_hp >= 2
        nominal_hp = nominal_hp.round
      end

      # Get the efficiency based on the nominal horsepower
      # Add 0.01 hp to avoid search errors.
      motor_properties = model_find_object(elevator_motor_eff, search_criteria, nil, nil, nil, nil, nominal_hp + 0.01)
      if motor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "For #{elevator_name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
        return false
      end
      motor_eff = motor_properties['nominal_full_load_efficiency'].to_f
      elevator_power = elevator_number_of_lifts * elevator_motor_bhp * 746 / motor_eff

      if equipment.is_a?(OpenStudio::Model::ElectricEquipment)
        equipment.electricEquipmentDefinition.setDesignLevel(elevator_power)
      else
        equipment.exteriorFuelEquipmentDefinition.setDesignLevel(elevator_power)
      end
      elevator_space = prm_get_optional_handler(equipment, @sizing_run_dir, 'space')
      # Add ventilation and lighting process loads if modeled in the proposed model
      misc_elevator_process_loads = 0.0
      misc_elevator_process_loads += get_additional_property_as_double(equipment, 'elevator_ventilation_cfm', 0.0) * 0.33
      misc_elevator_process_loads += get_additional_property_as_double(equipment, 'elevator_area_ft2', 0.0) * 3.14
      if misc_elevator_process_loads > 0
        misc_elevator_process_loads_def = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
        misc_elevator_process_loads_def.setName("#{elevator_name} - Misc Process Loads - Def")
        misc_elevator_process_loads_def.setDesignLevel(misc_elevator_process_loads)
        misc_elevator_process_loads = OpenStudio::Model::ElectricEquipment.new(misc_elevator_process_loads_def)
        misc_elevator_process_loads.setName("#{elevator_name} - Misc Process Loads")
        misc_elevator_process_loads.setEndUseSubcategory('Elevators')
        misc_elevator_process_loads.setSchedule(model.alwaysOnDiscreteSchedule)
        misc_elevator_process_loads.setSpace(elevator_space)
      end
    end
  end

  # Add design day schedule objects for space loads, for PRM 2019 baseline models
  # @author Xuechen (Jerry) Lei, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def model_apply_prm_baseline_sizing_schedule(model)
    space_loads = model.getSpaceLoads
    loads = []
    space_loads.sort.each do |space_load|
      casted_load = model_cast_model_object(space_load)
      loads << casted_load unless casted_load.nil?
    end

    load_schedule_name_hash = {
      'People' => 'numberofPeopleSchedule',
      'Lights' => 'schedule',
      'ElectricEquipment' => 'schedule',
      'GasEquipment' => 'schedule',
      'SpaceInfiltration_DesignFlowRate' => 'schedule'
    }

    loads.each do |load|
      load_type = load.iddObjectType.valueName.sub('OS_', '').strip
      load_schedule_name = load_schedule_name_hash[load_type]
      next if load_schedule_name.nil?

      # check if the load is in a dwelling space
      if load.spaceType.is_initialized
        space_type = load.spaceType.get
      elsif load.space.is_initialized && load.space.get.spaceType.is_initialized
        space_type = load.space.get.spaceType.get
      else
        space_type = nil
        puts "No hosting space/spacetype found for load: #{load.name}"
      end
      if !space_type.nil? && /apartment/i =~ space_type.standardsSpaceType.to_s
        load_in_dwelling = true
      else
        load_in_dwelling = false
      end

      load_schedule = load.public_send(load_schedule_name).get
      schedule_type = load_schedule.iddObjectType.valueName.sub('OS_', '').strip.sub('_', '')
      load_schedule = load_schedule.public_send("to_#{schedule_type}").get

      case schedule_type
      when 'ScheduleRuleset'
        load_schmax = OpenstudioStandards::Schedules.schedule_get_min_max(load_schedule)['max']
        load_schmin = OpenstudioStandards::Schedules.schedule_get_min_max(load_schedule)['min']
        load_schmode = get_weekday_values_from_8760(model,
                                                    Array(OpenstudioStandards::Schedules.schedule_get_hourly_values(load_schedule)),
                                                    value_includes_holiday = true).mode[0]

        # AppendixG-2019 G3.1.2.2.1
        if load_type == 'SpaceInfiltration_DesignFlowRate'
          summer_value = load_schmax
          winter_value = load_schmax
        else
          summer_value = load_schmax
          winter_value = load_schmin
        end

        # AppendixG-2019 Exception to G3.1.2.2.1
        if load_in_dwelling
          summer_value = load_schmode
        end

        # set cooling design day schedule
        summer_dd_schedule = OpenStudio::Model::ScheduleDay.new(model)
        summer_dd_schedule.setName("#{load.name} Summer Design Day")
        summer_dd_schedule.addValue(OpenStudio::Time.new(1.0), summer_value)
        load_schedule.setSummerDesignDaySchedule(summer_dd_schedule)

        # set heating design day schedule
        winter_dd_schedule = OpenStudio::Model::ScheduleDay.new(model)
        winter_dd_schedule.setName("#{load.name} Winter Design Day")
        winter_dd_schedule.addValue(OpenStudio::Time.new(1.0), winter_value)
        load_schedule.setWinterDesignDaySchedule(winter_dd_schedule)

      when 'ScheduleConstant'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Space load #{load.name} has schedule type of ScheduleConstant. Nothing to be done for ScheduleConstant")
        next
      end
    end
  end

  # Applies the multi-zone VAV outdoor air sizing requirements to all applicable air loops in the model.
  # @note This is not applicable to the stable baseline; hence no action in this method
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_apply_multizone_vav_outdoor_air_sizing(model)
    return true
  end

  # Identifies non mechanically cooled ("nmc") systems, if applicable
  # and add a flag to the zone's and air loop's additional properties.
  # @todo Zone-level evaporative cooler is not currently supported
  # by OpenStudio, will need to be added to the method when supported.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] Zone to nmc system type mapping
  def model_identify_non_mechanically_cooled_systems(model)
    # Iterate through zones to find out if they are served by nmc systems
    model.getThermalZones.each do |zone|
      # Check if airloop has economizer and either:
      # - No cooling coil and/or,
      # - An evaporative cooling coil
      zone.airLoopHVACs.each do |air_loop|
        if (!air_loop_hvac_include_cooling_coil?(air_loop) &&
          air_loop_hvac_include_evaporative_cooler?(air_loop)) ||
           (!air_loop_hvac_include_cooling_coil?(air_loop) &&
             air_loop_hvac_include_economizer?(air_loop))
          air_loop.additionalProperties.setFeature('non_mechanically_cooled', true)
          zone.additionalProperties.setFeature('non_mechanically_cooled', true)
        end
      end
    end
  end

  # Specify supply air temperature setpoint for unit heaters based on 90.1 Appendix G G3.1.2.8.2
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone Object
  # @return [Double] for zone with unit heaters, return design supply temperature; otherwise, return nil
  def thermal_zone_prm_unitheater_design_supply_temperature(thermal_zone)
    thermal_zone.equipment.each do |eqt|
      if eqt.to_ZoneHVACUnitHeater.is_initialized
        return OpenStudio.convert(105, 'F', 'C').get
      end
    end
    return nil
  end

  # Specify supply to room delta for laboratory spaces based on 90.1 Appendix G Exception to G3.1.2.8.1
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone Object
  # @return [Double] for zone with laboratory space, return 17; otherwise, return nil
  def thermal_zone_prm_lab_delta_t(thermal_zone)
    # For labs, add 17 delta-T; otherwise, add 20 delta-T
    thermal_zone.spaces.each do |space|
      space_std_type = space.spaceType.get.standardsSpaceType.get
      if space_std_type == 'laboratory'
        return 17
      end
    end
    return nil
  end

  # Indicate if fan power breakdown (supply, return, and relief)
  # are needed
  #
  # @return [Boolean] true if necessary, false otherwise
  def model_get_fan_power_breakdown
    return true
  end

  # Applies the HVAC parts of the template to all objects in the model using the the template specified in the model.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param apply_controls [Boolean] toggle whether to apply air loop and plant loop controls
  # @param sql_db_vars_map [Hash] hash map
  # @return [Boolean] returns true if successful, false if not
  def model_apply_hvac_efficiency_standard(model, climate_zone, apply_controls: true, sql_db_vars_map: nil)
    sql_db_vars_map = {} if sql_db_vars_map.nil?

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Started applying HVAC efficiency standards for #{template} template.")

    # Air Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getAirLoopHVACs.sort.each { |obj| air_loop_hvac_apply_standard_controls(obj, climate_zone) }
    end

    # Plant Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getPlantLoops.sort.each { |obj| plant_loop_apply_standard_controls(obj, climate_zone) }
    end

    # Zone HVAC Controls
    model.getZoneHVACComponents.sort.each { |obj| zone_hvac_component_apply_standard_controls(obj) }

    # @todo The fan and pump efficiency will be done by another task.
    # Fans
    # model.getFanVariableVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    # model.getFanConstantVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    # model.getFanOnOffs.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    # model.getFanZoneExhausts.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }

    # Pumps
    # model.getPumpConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    # model.getPumpVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    # model.getHeaderedPumpsConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    # model.getHeaderedPumpsVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }

    # Zone level systems/components
    model.getThermalZones.each do |zone|
      if zone.additionalProperties.getFeatureAsString('baseline_system_type').is_initialized
        sys_type = zone.additionalProperties.getFeatureAsString('baseline_system_type').get
      end
      zone.equipment.each do |zone_equipment|
        if zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          ptac = zone_equipment.to_ZoneHVACPackagedTerminalAirConditioner.get
          cooling_coil = ptac.coolingCoil
          sql_db_vars_map = set_coil_cooling_efficiency_and_curves(cooling_coil, sql_db_vars_map, sys_type)
        elsif zone_equipment.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
          pthp = zone_equipment.to_ZoneHVACPackagedTerminalHeatPump.get
          cooling_coil = pthp.coolingCoil
          heating_coil = pthp.heatingCoil
          sql_db_vars_map = set_coil_cooling_efficiency_and_curves(cooling_coil, sql_db_vars_map, sys_type)
          sql_db_vars_map = set_coil_heating_efficiency_and_curves(heating_coil, sql_db_vars_map, sys_type)
        elsif zone_equipment.to_ZoneHVACUnitHeater.is_initialized
          unit_heater = zone_equipment.to_ZoneHVACUnitHeater.get
          heating_coil = unit_heater.heatingCoil
          sql_db_vars_map = set_coil_heating_efficiency_and_curves(heating_coil, sql_db_vars_map, sys_type)
        end
      end
    end

    # Airloop HVAC level components
    model.getAirLoopHVACs.sort.each do |air_loop|
      sys_type = air_loop.additionalProperties.getFeatureAsString('baseline_system_type').get
      air_loop.components.each do |icomponent|
        if icomponent.to_AirLoopHVACUnitarySystem.is_initialized
          unitary_system = icomponent.to_AirLoopHVACUnitarySystem.get
          if unitary_system.coolingCoil.is_initialized
            cooling_coil = unitary_system.coolingCoil.get
            sql_db_vars_map = set_coil_cooling_efficiency_and_curves(cooling_coil, sql_db_vars_map, sys_type)
          end
          if unitary_system.heatingCoil.is_initialized
            heating_coil = unitary_system.heatingCoil.get
            sql_db_vars_map = set_coil_heating_efficiency_and_curves(heating_coil, sql_db_vars_map, sys_type)
          end
        elsif icomponent.to_CoilCoolingDXSingleSpeed.is_initialized
          cooling_coil = icomponent.to_CoilCoolingDXSingleSpeed.get
          sql_db_vars_map = coil_cooling_dx_single_speed_apply_efficiency_and_curves(cooling_coil, sql_db_vars_map, sys_type)
        elsif icomponent.to_CoilCoolingDXTwoSpeed.is_initialized
          cooling_coil = icomponent.to_CoilCoolingDXTwoSpeed.get
          sql_db_vars_map = coil_cooling_dx_two_speed_apply_efficiency_and_curves(cooling_coil, sql_db_vars_map, sys_type)
        elsif icomponent.to_CoilHeatingDXSingleSpeed.is_initialized
          heating_coil = icomponent.to_CoilHeatingDXSingleSpeed.get
          sql_db_vars_map = coil_heating_dx_single_speed_apply_efficiency_and_curves(heating_coil, sql_db_vars_map, sys_type)
        elsif icomponent.to_CoilHeatingGas.is_initialized
          heating_coil = icomponent.to_CoilHeatingGas.get
          sql_db_vars_map = coil_heating_gas_apply_efficiency_and_curves(heating_coil, sql_db_vars_map, sys_type)
        end
      end
    end

    # Chillers
    model.getChillerElectricEIRs.sort.each { |obj| chiller_electric_eir_apply_efficiency_and_curves(obj) }

    # Boilers
    model.getBoilerHotWaters.sort.each { |obj| boiler_hot_water_apply_efficiency_and_curves(obj) }

    # Cooling Towers
    model.getCoolingTowerVariableSpeeds.sort.each { |obj| cooling_tower_variable_speed_apply_efficiency_and_curves(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Finished applying HVAC efficiency standards for #{template} template.")
    return true
  end

  # This function returns the cooling dx coil efficiency and curve coefficient in a Hashmap.
  #
  # @param cooling_coil [OpenStudio::Model::ModeObject]
  # @param sql_db_vars_map [Hash] hash map
  # @param sys_type [String] baseline system type string
  # @return [Hash] sql_db_vars_map
  def set_coil_cooling_efficiency_and_curves(cooling_coil, sql_db_vars_map, sys_type)
    if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
      # single speed coil
      sql_db_vars_map = coil_cooling_dx_single_speed_apply_efficiency_and_curves(cooling_coil.to_CoilCoolingDXSingleSpeed.get, sql_db_vars_map, sys_type)
    elsif cooling_coil.to_CoilCoolingDXTwoSpeed.is_initialized
      # two speed coil
      sql_db_vars_map = coil_cooling_dx_two_speed_apply_efficiency_and_curves(cooling_coil.to_CoilCoolingDXTwoSpeed.get, sql_db_vars_map, sys_type)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "#{cooling_coil.name} is not single speed or two speed DX cooling coil. Nothing to be done for efficiency")
    end

    return sql_db_vars_map
  end

  # This function returns the heating dx coil efficiency and curve coefficient in a Hashmap.
  #
  # @param heating_coil [OpenStudio::Model::ModeObject]
  # @param sql_db_vars_map [Hash] hash map
  # @param sys_type [String] baseline system type string
  # @return [Hash] the hashmap contains the heating efficiency and curve coefficient for the heating_coil
  def set_coil_heating_efficiency_and_curves(heating_coil, sql_db_vars_map, sys_type)
    if heating_coil.to_CoilHeatingDXSingleSpeed.is_initialized
      # single speed coil
      sql_db_vars_map = coil_heating_dx_single_speed_apply_efficiency_and_curves(heating_coil.to_CoilHeatingDXSingleSpeed.get, sql_db_vars_map, sys_type)
    elsif heating_coil.to_CoilHeatingGas.is_initialized
      # single speed coil
      sql_db_vars_map = coil_heating_gas_apply_efficiency_and_curves(heating_coil.to_CoilHeatingGas.get, sql_db_vars_map, sys_type)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "#{heating_coil.name} is not single speed DX heating coil. Nothing to be done for efficiency")
    end

    return sql_db_vars_map
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

  # Template method for adding a setpoint manager for a coil control logic to a heating coil.
  # ASHRAE 90.1-2019 Appendix G.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @param thermal_zones Array([OpenStudio::Model::ThermalZone]) thermal zone array
  # @param coil [OpenStudio::Model::StraightComponent] heating coil
  # @return [Boolean] returns true if successful, false if not
  def model_set_central_preheat_coil_spm(model, thermal_zones, coil)
    # search for the highest zone setpoint temperature
    max_heat_setpoint = 0.0
    coil_name = coil.name.get.to_s
    thermal_zones.each do |zone|
      tstat = zone.thermostatSetpointDualSetpoint
      if tstat.is_initialized
        tstat = tstat.get
        setpoint_sch = tstat.heatingSetpointTemperatureSchedule
        setpoint_c = OpenstudioStandards::Schedules.schedule_get_design_day_min_max(setpoint_sch.get, 'winter')['max']
        next if setpoint_c.nil?

        if setpoint_c > max_heat_setpoint
          max_heat_setpoint = setpoint_c
        end
      end
    end
    # in this situation, we hard set the temperature to be 22 F
    # (ASHRAE 90.1 Room heating stepoint temperature is 72 F)
    max_heat_setpoint = 22.2 if max_heat_setpoint.zero?

    max_heat_setpoint_f = OpenStudio.convert(max_heat_setpoint, 'C', 'F').get
    preheat_setpoint_f = max_heat_setpoint_f - 20
    preheat_setpoint_c = OpenStudio.convert(preheat_setpoint_f, 'F', 'C').get

    # create a new constant schedule and this method will add schedule limit type
    preheat_coil_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                       preheat_setpoint_c,
                                                                                       name: "#{coil_name} Setpoint Temp - #{preheat_setpoint_f.round}F",
                                                                                       schedule_type_limit: 'Temperature')
    preheat_coil_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, preheat_coil_sch)
    preheat_coil_manager.setName("#{coil_name} Preheat Coil Setpoint Manager")

    if coil.to_CoilHeatingWater.is_initialized
      preheat_coil_manager.addToNode(coil.airOutletModelObject.get.to_Node.get)
    elsif coil.to_CoilHeatingElectric.is_initialized
      preheat_coil_manager.addToNode(coil.outletModelObject.get.to_Node.get)
    elsif coil.to_CoilHeatingGas.is_initialized
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.models.CoilHeatingGas', 'Preheat coils in baseline system shall only be electric or hydronic. Current coil type: Natural Gas')
      preheat_coil_manager.addToNode(coil.airOutletModelObject.get.to_Node.get)
    end

    return true
  end

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

          if row['dcv_exception_airloop']
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

          if row['dcv_exception_thermal_zone']
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
    model.getThermalZones.each do |zone|
      unless zone.additionalProperties.hasFeature('airloop user specified DCV exception')
        zone.additionalProperties.setFeature('airloop user specified DCV exception', false)
      end

      unless zone.additionalProperties.hasFeature('zone user specified DCV exception')
        zone.additionalProperties.setFeature('zone user specified DCV exception', false)
      end
    end
  end

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
        if thermal_zone.additionalProperties.hasFeature('apxg no need to have DCV')
          if !thermal_zone.additionalProperties.getFeatureAsBoolean('apxg no need to have DCV').get
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Moreover, for thermal zone #{thermal_zone.name}, Appendix G baseline model will have DCV based on ASHRAE 90.1 2019 G3.1.2.5")
          end
        end
      end
      if thermal_zone.additionalProperties.getFeatureAsBoolean('zone dcv required by 901').get &&
         thermal_zone.additionalProperties.getFeatureAsBoolean('airloop dcv required by 901').get &&
         !thermal_zone.additionalProperties.getFeatureAsBoolean('zone DCV implemented in user model').get
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "For thermal zone #{thermal_zone.name}, ASHRAE 90.1 2019 6.4.3.8 requires this zone to have demand control ventilation, but it was not implemented in the user model, Appendix G baseline generation should be terminated!")
      end
    end
  end

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
      oa_flow_cfm = OpenStudio.convert(oa_flow_m3_per_s, 'm^3/s', 'cfm').get
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
          if occ_per_1000_ft2 <= 100
            thermal_zone.additionalProperties.setFeature('apxg no need to have DCV', true)
          else
            thermal_zone.additionalProperties.setFeature('apxg no need to have DCV', false)
          end
        end
      end
    end
    # if a zone does not have this additional property, it means it was not served by airloop.
  end

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
            OpenstudioStandards::ThermalZone.thermal_zone_convert_outdoor_air_to_per_area(zone)
          end
        end
      end
    end
  end

  # A template method that handles the loading of user input data from multiple sources
  # include data source from:
  # 1. user data csv files
  # 2. data from measure and OpenStudio interface
  # @param [OpenStudio:model:Model] model
  # @param [String] climate_zone
  # @param [String] default_hvac_building_type
  # @param [String] default_wwr_building_type
  # @param [String] default_swh_building_type
  # @param [Hash] bldg_type_hvac_zone_hash A hash maps building type for hvac to a list of thermal zones
  # @return [Boolean] returns true if successful, false if not
  def handle_user_input_data(model, climate_zone, sizing_run_dir, default_hvac_building_type, default_wwr_building_type, default_swh_building_type, bldg_type_hvac_zone_hash)
    # Set sizing run directory
    @sizing_run_dir = sizing_run_dir
    # load the multiple building area types from user data
    handle_multi_building_area_types(model, climate_zone, default_hvac_building_type, default_wwr_building_type, default_swh_building_type, bldg_type_hvac_zone_hash)
    # load user data from proposed model
    handle_airloop_user_input_data(model)
    # exterior lighting handler
    handle_exterior_lighting_user_input_data(model)
    # load lights data from user data
    handle_lights_user_input_data(model)
    # load OA data from user data
    handle_outdoor_air_user_input_data(model)
    # load air loop DOAS user data from the proposed model
    handle_airloop_doas_user_input_data(model)
    # load zone HVAC user data from proposed model
    handle_zone_hvac_user_input_data(model)
    # load thermal zone user data from proposed model
    handle_thermal_zone_user_input_data(model)
    # load electric equipment user data
    handle_electric_equipment_user_input_data(model)
    # load gas equipment user data
    handle_gas_equipment_user_input_data(model)
    # load water use connection user data
    handle_wateruse_connections_user_input_data(model)
    # load water use equipment user data
    handle_wateruse_equipment_user_input_data(model, default_swh_building_type)
    # load water use equipment definition user data
    handle_wateruse_equipment_definition_user_input_data(model)
    return true
  end

  # A function to load lights from user data csv files
  # The file name is userdata_lights.csv
  # @param [OpenStudio::Model::Model] model
  def handle_lights_user_input_data(model)
    user_lights = get_userdata(UserDataFiles::LIGHTS)
    model.getLightss.each do |light|
      if user_lights
        user_data_updated = false
        user_lights.each do |user_light|
          next unless UserData.compare(light.name.get, user_light['name'])

          has_retail_display_exception = prm_read_user_data(user_light, 'has_retail_display_exception', false)
          if has_retail_display_exception
            light.additionalProperties.setFeature('has_retail_display_exception', true)
          else
            light.additionalProperties.setFeature('has_retail_display_exception', false)
          end

          has_unregulated_exception = prm_read_user_data(user_light, 'has_unregulated_exception', false)
          if has_unregulated_exception
            light.additionalProperties.setFeature('has_unregulated_exception', true)
          else
            light.additionalProperties.setFeature('has_unregulated_exception', false)
          end

          unregulated_category = prm_read_user_data(user_light, 'unregulated_category')
          if unregulated_category
            light.additionalProperties.setFeature('unregulated_category', unregulated_category)
          end

          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "WaterUseConnections name #{light.name.get} was not found in user data file: #{UserDataFiles::LIGHTS}; No user data applied.")
        end
      end
    end
  end

  # A function to load water use equipment definition from user data csv files
  # The file name is userdata_wateruse_equipment_definition.csv
  # @param [OpenStudio::Model::Model] model
  def handle_wateruse_equipment_definition_user_input_data(model)
    user_data_wateruse_equipment_definition = get_userdata(UserDataFiles::WATERUSE_EQUIPMENT_DEFINITION)
    model.getWaterUseEquipmentDefinitions.each do |wateruse_equipment|
      if user_data_wateruse_equipment_definition
        user_data_updated = false
        user_data_wateruse_equipment_definition.each do |user_wateruse|
          next unless UserData.compare(wateruse_equipment.name.get, user_wateruse['name'])

          peak_flow_rate = prm_read_user_data(user_wateruse, 'peak_flow_rate', nil)
          if peak_flow_rate
            wateruse_equipment.additionalProperties.setFeature('peak_flow_rate', peak_flow_rate)
          end

          flow_rate_fraction_schedule_name = prm_read_user_data(user_wateruse, 'flow_rate_fraction_schedule', '')
          # verify the schedule exist in the model
          prm_raise(model.getScheduleRulesetByName(flow_rate_fraction_schedule_name) ||
                      model.getScheduleCompactByName(flow_rate_fraction_schedule_name) ||
                      model.getScheduleConstantByName(flow_rate_fraction_schedule_name),
                    @sizing_run_dir,
                    "Cannot find #{flow_rate_fraction_schedule_name} in the model. Note, such schedule shall be one of the following type: RuleSet, Compact and Constant")
          wateruse_equipment.additionalProperties.setFeature('flow_rate_fraction_schedule', flow_rate_fraction_schedule_name)

          target_temperature_schedule_name = prm_read_user_data(user_wateruse, 'target_temperature_schedule', '')
          # verify the schedule exist in the model
          prm_raise(model.getScheduleRulesetByName(target_temperature_schedule_name) ||
                      model.getScheduleCompactByName(target_temperature_schedule_name) ||
                      model.getScheduleConstantByName(target_temperature_schedule_name),
                    @sizing_run_dir,
                    "Cannot find #{target_temperature_schedule_name} in the model. Note, such schedule shall be one of the following type: RuleSet, Compact and Constant")
          wateruse_equipment.additionalProperties.setFeature('target_temperature_schedule', target_temperature_schedule_name)
          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "WaterUseConnections name #{wateruse_equipment.name.get} was not found in user data file: #{UserDataFiles::WATERUSE_EQUIPMENT_DEFINITION}; No user data applied.")
        end
      end
    end
  end

  # A function to load water use equipment from user data csv files
  # The file name is userdata_wateruse_equipment.csv
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @param default_swh_building_type [String] SWH building type
  def handle_wateruse_equipment_user_input_data(model, default_swh_building_type)
    user_data_wateruse_equipment = get_userdata(UserDataFiles::WATERUSE_EQUIPMENT)
    user_data_building = get_userdata(UserDataFiles::BUILDING)
    # get swh building type from user data building
    default_type = default_swh_building_type
    if user_data_building
      building_name = prm_get_optional_handler(model, @sizing_run_dir, 'building', 'name')
      user_building_index = user_data_building.index { |user_building| UserData.compare(user_building['name'], building_name) }
      unless user_building_index.nil? || prm_read_user_data(user_data_building[user_building_index], 'building_type_swh', nil)
        # Only thermal zone in the buildings user data and have building_type_for_hvac data will be assigned.
        default_type = prm_read_user_data(user_data_building[user_building_index], 'building_type_swh', default_type)
        OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Building type swh found in #{UserDataFiles::WATERUSE_EQUIPMENT} for building #{building_name}, set default building type swh to #{default_type}")
      end
    end
    model.getWaterUseEquipments.each do |wateruse_equipment|
      user_data_updated = false
      if user_data_wateruse_equipment
        user_data_wateruse_equipment.each do |user_wateruse|
          if UserData.compare(wateruse_equipment.name.get, user_wateruse['name'])
            building_type_swh = prm_read_user_data(user_wateruse, 'building_type_swh', nil)
            if building_type_swh
              wateruse_equipment.additionalProperties.setFeature('building_type_swh', building_type_swh)
            end
            user_data_updated = true
          end
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "WaterUseEquipment name #{wateruse_equipment.name.get} was not found in user data file: #{UserDataFiles::WATERUSE_EQUIPMENT}; default building swh type #{default_type} applied.")
        end
      end
      # No user data updated, use default type
      unless user_data_updated
        wateruse_equipment.additionalProperties.setFeature('building_type_swh', default_type)
      end
    end
  end

  # A function to load water use connections schedules from user data csv files
  # The file name is userdata_wateruse_connections.csv
  # @param [OpenStudio::Model::Model] model
  def handle_wateruse_connections_user_input_data(model)
    user_data_wateruse_connections = get_userdata(UserDataFiles::WATERUSE_CONNECTIONS)
    model.getWaterUseConnectionss.each do |wateruse_connections|
      if user_data_wateruse_connections
        user_data_updated = false
        user_data_wateruse_connections.each do |user_wateruse|
          next unless UserData.compare(wateruse_connections.name.get, user_wateruse['name'])

          hot_water_supply_temperature_schedule_name = prm_read_user_data(user_wateruse, 'hot_water_supply_temperature_schedule', '')
          # verify the schedule exist in the model
          prm_raise(model.getScheduleRulesetByName(hot_water_supply_temperature_schedule_name) ||
                      model.getScheduleCompactByName(hot_water_supply_temperature_schedule_name) ||
                      model.getScheduleConstantByName(hot_water_supply_temperature_schedule_name),
                    @sizing_run_dir,
                    "Cannot find #{hot_water_supply_temperature_schedule_name} in the model. Note, such schedule shall be one of the following type: RuleSet, Compact and Constant")
          wateruse_connections.additionalProperties.setFeature('hot_water_supply_temperature_schedule', hot_water_supply_temperature_schedule_name)

          cold_water_supply_temperature_schedule_name = prm_read_user_data(user_wateruse, 'cold_water_supply_temperature_schedule', '')
          # verify the schedule exist in the model
          prm_raise(model.getScheduleRulesetByName(cold_water_supply_temperature_schedule_name) ||
                      model.getScheduleCompactByName(cold_water_supply_temperature_schedule_name) ||
                      model.getScheduleConstantByName(cold_water_supply_temperature_schedule_name),
                    @sizing_run_dir,
                    "Cannot find #{cold_water_supply_temperature_schedule_name} in the model. Note, such schedule shall be one of the following type: RuleSet, Compact and Constant")
          wateruse_connections.additionalProperties.setFeature('cold_water_supply_temperature_schedule', cold_water_supply_temperature_schedule_name)
          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "WaterUseConnections name #{wateruse_connections.name.get} was not found in user data file: #{UserDataFiles::WATERUSE_CONNECTIONS}; No user data applied.")
        end
      end
    end
  end

  # A function to load exterior lighting data from user data csv files
  # The file name is userdata_exterior_lighting.csv
  # @param [OpenStudio::Model::Model] model
  def handle_exterior_lighting_user_input_data(model)
    user_data_exterior_lighting_objects = get_userdata(UserDataFiles::EXTERIOR_LIGHTS)

    search_criteria = {
      'template' => template
    }
    ext_ltg_baseline_values = standards_lookup_table_first(table_name: 'prm_exterior_lighting', search_criteria: search_criteria)

    model.getExteriorLightss.each do |exterior_light|
      if user_data_exterior_lighting_objects
        user_data_updated = false
        # get exterior lighting object.
        user_data_exterior_lighting_objects.each do |user_exterior_lighting|
          next unless UserData.compare(exterior_light.name.get, user_exterior_lighting['name'])

          num_cats = prm_read_user_data(user_exterior_lighting, 'num_ext_lights_subcats', '0').to_i
          # Make sure none of the categories are nontradeable and not a mix of tradeable and nontradeable
          num_trade = 0
          num_notrade = 0
          ext_ltg_cats = {}
          (1..num_cats).each do |icat|
            cat_key = format('end_use_subcategory_%02d', icat)
            # validated
            subcat = user_exterior_lighting[cat_key]
            # handle the userdata missing value issue.
            if UserDataNonTradableLightsCategory.matched_any?(subcat)
              num_notrade += 1
            else
              num_trade += 1
              meas_val_key = format('end_use_measurement_value_%02d', icat)
              meas_val = prm_read_user_data(user_exterior_lighting, meas_val_key, '0.0').to_f
              unless meas_val == 0
                OpenStudio.logFree(OpenStudio::Info, 'prm.log', "End use subcategory #{subcat} has either missing measurement value or invalid measurement value, set to 0.0")
              end
              ext_ltg_cats[subcat] = meas_val
            end
          end

          # skip this if all lights are non-tradeable
          if num_trade == 0
            exterior_light.additionalProperties.setFeature('design_level', 0.0)
            next
          end

          if (num_trade > 0) && (num_notrade > 0)
            OpenStudio.logFree(OpenStudio::Warn, 'prm.log', "ExteriorLights object named #{user_exterior_lighting['name']} from user data file has a mix of tradeable and non-tradeable lighting types. All will be treated as non-tradeable.")
            next
          end

          ext_ltg_pwr = 0
          ext_ltg_cats.each do |subcat, meas_val|
            # Get baseline power for this type of exterior lighting
            baseline_value = ext_ltg_baseline_values[subcat].to_f
            ext_ltg_pwr += baseline_value * meas_val
          end

          exterior_light.additionalProperties.setFeature('design_level', ext_ltg_pwr)
          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Exterior Lights name #{exterior_light.name.get} was not found in user data file: #{UserDataFiles::EXTERIOR_LIGHTS}; No user data applied.")
        end
      end
    end
  end

  # A function to load electric equipment csv files
  # The file name is userdata_electric_equipment.csv
  # @param [OpenStudio::Model::Model] model
  def handle_electric_equipment_user_input_data(model)
    user_data_plug_load = get_userdata(UserDataFiles::ELECTRIC_EQUIPMENT)
    model.getElectricEquipments.each do |elevator_equipment|
      if user_data_plug_load
        user_data_updated = false
        user_data_plug_load.each do |user_plug_load|
          next unless UserData.compare(elevator_equipment.name.get, user_plug_load['name'])

          fraction_of_controlled_receptacles = prm_read_user_data(user_plug_load, 'fraction_of_controlled_receptacles', '0.0').to_f
          elevator_equipment.additionalProperties.setFeature('fraction_of_controlled_receptacles', fraction_of_controlled_receptacles)

          receptacle_power_savings = prm_read_user_data(user_plug_load, 'receptacle_power_savings', '0.0').to_f
          elevator_equipment.additionalProperties.setFeature('receptacle_power_savings', receptacle_power_savings)

          num_lifts = prm_read_user_data(user_plug_load, 'elevator_number_of_lifts', '0').to_i
          if num_lifts > 0
            elevator_equipment.additionalProperties.setFeature('elevator_number_of_lifts', num_lifts)
            number_of_levels = prm_read_user_data(user_plug_load, 'elevator_number_of_stories', '0').to_i
            elevator_equipment.additionalProperties.setFeature('elevator_number_of_stories', number_of_levels)
            elevator_weight_of_car = prm_read_user_data(user_plug_load, 'elevator_weight_of_car', '0.0').to_f
            elevator_equipment.additionalProperties.setFeature('elevator_weight_of_car', elevator_weight_of_car)
            elevator_weight_of_car = prm_read_user_data(user_plug_load, 'elevator_counter_weight_of_car', '0.0').to_f
            elevator_equipment.additionalProperties.setFeature('elevator_counter_weight_of_car', elevator_weight_of_car)
            elevator_rated_load = prm_read_user_data(user_plug_load, 'elevator_rated_load', '0.0').to_f
            elevator_equipment.additionalProperties.setFeature('elevator_rated_load', elevator_rated_load)
            elevator_speed_of_car = prm_read_user_data(user_plug_load, 'elevator_speed_of_car', '0.0').to_f
            elevator_equipment.additionalProperties.setFeature('elevator_speed_of_car', elevator_speed_of_car)
            elevator_ventilation_cfm = prm_read_user_data(user_plug_load, 'elevator_ventilation_cfm', '0.0').to_f
            elevator_equipment.additionalProperties.setFeature('elevator_ventilation_cfm', elevator_ventilation_cfm)
            elevator_area_ft2 = prm_read_user_data(user_plug_load, 'elevator_area_ft2', '0.0').to_f
            elevator_equipment.additionalProperties.setFeature('elevator_area_ft2', elevator_area_ft2)
          end
          user_data_updated = true
        end

        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Electric equipment name #{elevator_equipment.name.get} was not found in user data file: #{UserDataFiles::ELECTRIC_EQUIPMENT}; No user data applied.")
        end
      end
    end
  end

  # A function to load gas equipment csv files
  # The file name is userdata_gas_equipment.csv
  # @param [OpenStudio::Model::Model] model
  def handle_gas_equipment_user_input_data(model)
    user_data_gas_equipment = get_userdata(UserDataFiles::GAS_EQUIPMENT)
    model.getGasEquipments.each do |gas_equipment|
      if user_data_gas_equipment
        user_data_updated = false
        user_data_gas_equipment.each do |user_gas_equipment|
          next unless UserData.compare(gas_equipment.name.get, user_gas_equipment['name'])

          fraction_of_controlled_receptacles = prm_read_user_data(user_gas_equipment, 'fraction_of_controlled_receptacles', '0.0').to_f
          prm_raise(fraction_of_controlled_receptacles > 1.0, 'The fraction of all controlled receptacles cannot be higher than 1.0')
          gas_equipment.additionalProperties.setFeature('fraction_of_controlled_receptacles', fraction_of_controlled_receptacles)

          receptacle_power_savings = prm_read_user_data(user_gas_equipment, 'receptacle_power_savings', '0.0').to_f
          gas_equipment.additionalProperties.setFeature('receptacle_power_savings', receptacle_power_savings)
          user_data_updated = true
        end

        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Gas equipment name #{gas_equipment.name.get} was not found in user data file: #{UserDataFiles::GAS_EQUIPMENT}; No user data applied.")
        end
      end
    end
  end

  # A function to load outdoor air data from user data csv files
  # The file name is userdata_design_specification_outdoor_air.csv
  # @param [OpenStudio::Model::Model] model
  def handle_outdoor_air_user_input_data(model)
    user_data_oas = get_userdata(UserDataFiles::DESIGN_SPECIFICATION_OUTDOOR_AIR)
    model.getDesignSpecificationOutdoorAirs.each do |zone_oa|
      if user_data_oas
        user_data_updated = false
        user_data_oas.each do |user_oa|
          next unless UserData.compare(zone_oa.name.get, user_oa['name'])

          user_oa.each_key do |info_key|
            if info_key == 'name'
              zone_oa.additionalProperties.setFeature('has_user_data', true)
            else
              # this will capture the invalid string to 0.0, need to add note
              OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Add user provided outdoor air field: #{info_key}, value: #{user_oa[info_key].to_f} to DesignSpecification:OutdoorAir #{zone_oa.name.get} ")
              zone_oa.additionalProperties.setFeature(info_key, user_oa[info_key].to_f)
            end
          end
          user_data_updated = true
        end

        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Zone outdoor air name #{zone_oa.name.get} was not found in user data file: #{UserDataFiles::DESIGN_SPECIFICATION_OUTDOOR_AIR}; No user data applied.")
        end
      end
    end
  end

  # A function to load airloop data from userdata csv files
  # The function works with validated user data only.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def handle_airloop_user_input_data(model)
    # ============================Process airloop info ============================================
    user_airloops = get_userdata(UserDataFiles::AIRLOOP_HVAC)
    model.getAirLoopHVACs.each do |air_loop|
      if user_airloops
        user_data_updated = false
        user_airloops.each do |user_airloop|
          next unless UserData.compare(air_loop.name.get, user_airloop['name'])

          air_loop.thermalZones.each do |thermal_zone|
            # gas phase air cleaning is system base - add proposed hvac system name to zones
            economizer_exception_for_gas_phase_air_cleaning = user_airloop['economizer_exception_for_gas_phase_air_cleaning']
            economizer_exception_for_open_refrigerated_cases = user_airloop['economizer_exception_for_open_refrigerated_cases']
            user_airloop.each_key do |info_key|
              if info_key.include?('has_fan_power_credit') && UserData.compare(user_airloop[info_key], UserDataBoolean::TRUE)
                current_value = get_additional_property_as_double(thermal_zone, info_key, 0.0)
                thermal_zone.additionalProperties.setFeature(info_key, current_value + 1.0)
              elsif info_key.include?('fan_power_credit')
                # Case 2: user provided value
                fan_power_credit = prm_read_user_data(user_airloop, info_key, '0.0').to_f
                current_value = get_additional_property_as_double(thermal_zone, info_key, 0.0)
                thermal_zone.additionalProperties.setFeature(info_key, current_value + fan_power_credit)
              end

              # Exhaust air energy recovery
              if info_key.include?('exhaust_energy_recovery_exception')
                if UserData.compare(user_airloop[info_key], UserDataBoolean::TRUE)
                  thermal_zone.additionalProperties.setFeature(info_key, true)
                else
                  thermal_zone.additionalProperties.setFeature(info_key, false)
                end
              end
            end
            if UserData.compare(economizer_exception_for_gas_phase_air_cleaning, UserDataBoolean::TRUE)
              thermal_zone.additionalProperties.setFeature('economizer_exception_for_gas_phase_air_cleaning', true)
            else
              thermal_zone.additionalProperties.setFeature('economizer_exception_for_gas_phase_air_cleaning', false)
            end

            if UserData.compare(economizer_exception_for_open_refrigerated_cases, UserDataBoolean::TRUE)
              thermal_zone.additionalProperties.setFeature('economizer_exception_for_open_refrigerated_cases', true)
            else
              thermal_zone.additionalProperties.setFeature('economizer_exception_for_open_refrigerated_cases', false)
            end
          end
          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Air loop name #{air_loop.name.get} was not found in user data file: #{UserDataFiles::AIRLOOP_HVAC}; No user data applied.")
        end
      end
    end
  end

  # Retrieve zone HVAC user specified compliance inputs from CSV file
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def handle_zone_hvac_user_input_data(model)
    user_zone_hvac = get_userdata(UserDataFiles::ZONE_HVAC)
    return unless user_zone_hvac && !user_zone_hvac.empty?

    zone_hvac_equipment = model.getZoneHVACComponents
    if zone_hvac_equipment.empty?
      OpenStudio.logFree(OpenStudio::Error, 'prm.log', 'No zone HVAC equipment is present in the proposed model, user provided information cannot be used to generate the baseline building model.')
      return
    end

    user_zone_hvac.each do |zone_hvac_eqp_info|
      user_defined_zone_hvac_obj_name = zone_hvac_eqp_info['name']
      user_defined_zone_hvac_obj_type_name = zone_hvac_eqp_info['zone_hvac_object_type_name']

      # Check that the object type name do exist
      begin
        user_defined_zone_hvac_obj_type_name_idd = user_defined_zone_hvac_obj_type_name.to_IddObjectType
      rescue StandardError => e
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "#{user_defined_zone_hvac_obj_type_name}, provided in the user zone HVAC user data, is not a valid OpenStudio model object.")
      end

      # Retrieve zone HVAC object(s) by name
      zone_hvac_eqp = model.getZoneHVACComponentsByName(user_defined_zone_hvac_obj_name, false)

      # If multiple object have the same name
      if zone_hvac_eqp.empty?
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "The #{user_defined_zone_hvac_obj_type_name} object named #{user_defined_zone_hvac_obj_name} provided in the user zone HVAC user data could not be found in the model.")
      elsif zone_hvac_eqp.length == 1
        zone_hvac_eqp = zone_hvac_eqp[0]
        zone_hvac_eqp_idd = zone_hvac_eqp.iddObjectType.to_s
        if zone_hvac_eqp_idd != user_defined_zone_hvac_obj_type_name
          OpenStudio.logFree(OpenStudio::Error, 'prm.log', "The object type name provided in the zone HVAC user data (#{user_defined_zone_hvac_obj_type_name}) does not match with the one in the model: #{zone_hvac_eqp_idd}.")
        end
      else
        zone_hvac_eqp.each do |eqp|
          zone_hvac_eqp_idd = eqp.iddObjectType
          if zone_hvac_eqp_idd == user_defined_zone_hvac_obj_type_name
            zone_hvac_eqp = eqp
            break
          end
        end
        OpenStudio.logFree(OpenStudio::Error, 'prm.log', "A #{user_defined_zone_hvac_obj_type_name} object named #{user_defined_zone_hvac_obj_name} (as specified in the user zone HVAC data) could not be found in the model.")
      end

      if zone_hvac_eqp.thermalZone.is_initialized
        thermal_zone = zone_hvac_eqp.thermalZone.get

        zone_hvac_eqp_info.each_key do |info_key|
          if info_key.include?('fan_power_credit')
            if !zone_hvac_eqp_info[info_key].to_s.empty?
              if info_key.include?('has_')
                if thermal_zone.additionalProperties.hasFeature(info_key)
                  current_value = thermal_zone.additionalProperties.getFeatureAsDouble(info_key).to_f
                  thermal_zone.additionalProperties.setFeature(info_key, current_value + 1.0)
                else
                  thermal_zone.additionalProperties.setFeature(info_key, 1.0)
                end
              else
                if thermal_zone.additionalProperties.hasFeature(info_key)
                  current_value = thermal_zone.additionalProperties.getFeatureAsDouble(info_key).to_f
                  thermal_zone.additionalProperties.setFeature(info_key, current_value + zone_hvac_eqp_info[info_key])
                else
                  thermal_zone.additionalProperties.setFeature(info_key, zone_hvac_eqp_info[info_key])
                end
              end
            end
          end
        end
      end
    end
  end

  # A function to load airloop DOAS data from userdata csv files
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def handle_airloop_doas_user_input_data(model)
    # Get user data
    user_airloop_doass = get_userdata(UserDataFiles::AIRLOOP_HVAC_DOAS)
    model.getAirLoopHVACDedicatedOutdoorAirSystems.each do |air_loop_doas|
      if user_airloop_doass
        user_data_updated = false
        user_airloop_doass.each do |user_airloop_doas|
          next unless UserData.compare(user_airloop_doas['name'], air_loop_doas.name.get)

          # Parse fan power credits data
          user_airloop_doas.each_key do |info_key|
            if info_key.include?('has_fan_power_credit') && UserDataBoolean.compare(user_airloop_doas[info_key], UserDataBoolean::TRUE)
              air_loop_doas.airLoops.each do |air_loop|
                air_loop.thermalZones.each do |thermal_zone|
                  current_value = get_additional_property_as_double(thermal_zone, info_key, 0.0)
                  thermal_zone.additionalProperties.setFeature(info_key, current_value + 1.0)
                end
              end
            elsif info_key.include?('fan_power_credit')
              # Case 2: user provided value
              air_loop_doas.airLoops.each do |air_loop|
                air_loop.thermalZones.each do |thermal_zone|
                  current_value = get_additional_property_as_double(thermal_zone, info_key, 0.0)
                  thermal_zone.additionalProperties.setFeature(info_key, current_value + prm_read_user_data(user_airloop_doas, info_key, '0.0').to_f)
                end
              end
            end
          end
          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Air Loop DOAS name #{air_loop_doas.name.get} was not found in user data file: #{UserDataFiles::AIRLOOP_HVAC_DOAS}; No user data applied.")
        end
      end
    end
  end

  # A function to load thermal zone data from userdata csv files
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def handle_thermal_zone_user_input_data(model)
    userdata_thermal_zones = get_userdata(UserDataFiles::THERMAL_ZONE)
    model.getThermalZones.each do |thermal_zone|
      nightcycle_exception = false
      if userdata_thermal_zones
        user_data_updated = false
        userdata_thermal_zones.each do |row|
          next unless UserData.compare(row['name'], thermal_zone.name.get)

          if UserData.compare(row['has_health_safety_night_cycle_exception'], UserDataBoolean::TRUE)
            nightcycle_exception = true
            break
          end
          user_data_updated = true
        end
        unless user_data_updated
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Thermal Zone name #{thermal_zone.name.get} was not found in user data file: #{UserDataFiles::THERMAL_ZONE}.")
        end
      end
      if nightcycle_exception
        thermal_zone.additionalProperties.setFeature('has_health_safety_night_cycle_exception', true)
      end

      # mark unmarked zones
      unless thermal_zone.additionalProperties.hasFeature('has_health_safety_night_cycle_exception')
        thermal_zone.additionalProperties.setFeature('has_health_safety_night_cycle_exception', false)
      end
    end
  end

  # Analyze HVAC, window-to-wall ratio and SWH building (area) types from user data inputs in the @standard_data library
  # This function returns True, but the values are stored in the multi-building_data argument.
  # The hierarchy for process the building types
  # 1. Highest: PRM rules - if rules applied against user inputs, the function will use the calculated value to reset the building type
  # 2. Second: User defined building type in the csv file.
  # 3. Third: User defined userdata_building.csv file. If an object (e.g. space, thermalzone) are not defined in their correspondent userdata csv file, use the building csv file
  # 4. Fourth: Dropdown list in the measure GUI. If none presented, use the data from the dropdown list.
  # NOTE! This function will add building types to OpenStudio objects as an additional features for hierarchy 1-3
  # The object additional feature is empty when the function determined it uses fourth hierarchy.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param default_hvac_building_type [String] (Fourth Hierarchy hvac building type)
  # @param default_wwr_building_type [String] (Fourth Hierarchy wwr building type)
  # @param default_swh_building_type [String] (Fourth Hierarchy swh building type)
  # @param bldg_type_hvac_zone_hash [Hash] An empty hash that maps building type for hvac to a list of thermal zones
  # @return [Boolean] returns true if successful, false if not
  def handle_multi_building_area_types(model, climate_zone, default_hvac_building_type, default_wwr_building_type, default_swh_building_type, bldg_type_hvac_zone_hash)
    # Construct the user_building hashmap
    user_buildings = get_userdata(UserDataFiles::BUILDING)

    # Build up a hvac_building_type : thermal zone hash map
    # =============================HVAC user data process===========================================
    user_thermal_zones = get_userdata(UserDataFiles::THERMAL_ZONE)
    # First construct hvac building type -> thermal Zone hash and hvac building type -> floor area
    bldg_type_zone_hash = {}
    bldg_type_zone_area_hash = {}
    model.getThermalZones.each do |thermal_zone|
      # get climate zone to check the conditioning category
      thermal_zone_condition_category = thermal_zone_conditioning_category(thermal_zone, climate_zone)
      if thermal_zone_condition_category == 'Semiheated' || thermal_zone_condition_category == 'Unconditioned'
        next
      end

      # Check for Second hierarchy
      hvac_building_type = nil
      if user_thermal_zones
        user_thermal_zone_index = user_thermal_zones.index { |user_thermal_zone| UserData.compare(user_thermal_zone['name'], thermal_zone.name.get) }
        # make sure the thermal zone has assigned a building_type_for_hvac
        unless user_thermal_zone_index.nil? || user_thermal_zones[user_thermal_zone_index]['building_type_for_hvac'].nil?
          # Only thermal zone in the user data and have building_type_for_hvac data will be assigned.
          hvac_building_type = user_thermal_zones[user_thermal_zone_index]['building_type_for_hvac']
        end
      end
      # Second hierarchy does not apply, check Third hierarchy
      if hvac_building_type.nil? && user_buildings
        building_name = prm_get_optional_handler(thermal_zone.model, @sizing_run_dir, 'building', 'name')
        user_building_index = user_buildings.index { |user_building| UserData.compare(user_building['name'], building_name) }
        unless user_building_index.nil? || user_buildings[user_building_index]['building_type_for_hvac'].nil?
          # Only thermal zone in the buildings user data and have building_type_for_hvac data will be assigned.
          hvac_building_type = user_buildings[user_building_index]['building_type_for_hvac']
        end
      end
      # Third hierarchy does not apply, apply Fourth hierarchy
      if hvac_building_type.nil?
        hvac_building_type = default_hvac_building_type
      end
      # Add data to the hash map
      unless bldg_type_zone_hash.key?(hvac_building_type)
        bldg_type_zone_hash[hvac_building_type] = []
      end
      unless bldg_type_zone_area_hash.key?(hvac_building_type)
        bldg_type_zone_area_hash[hvac_building_type] = 0.0
      end
      # calculate floor area for the thermal zone
      part_of_floor_area = false
      thermal_zone.spaces.sort.each do |space|
        next unless space.partofTotalFloorArea

        # a space in thermal zone is part of floor area.
        part_of_floor_area = true
        bldg_type_zone_area_hash[hvac_building_type] += space.floorArea * space.multiplier
      end
      if part_of_floor_area
        # Only add the thermal_zone if it is part of the floor area
        bldg_type_zone_hash[hvac_building_type].append(thermal_zone)
      end
    end

    if bldg_type_zone_hash.empty?
      # Build hash with all zones assigned to default hvac building type
      zone_array = []
      model.getThermalZones.each do |thermal_zone|
        zone_array.append(thermal_zone)
        thermal_zone.additionalProperties.setFeature('building_type_for_hvac', default_hvac_building_type)
      end
      bldg_type_hvac_zone_hash[default_hvac_building_type] = zone_array
    else
      # Calculate the total floor area.
      # If the max tie, this algorithm will pick the first encountered hvac building type as the maximum.
      total_floor_area = 0.0
      hvac_bldg_type_with_max_floor = nil
      hvac_bldg_type_max_floor_area = 0.0
      bldg_type_zone_area_hash.each do |key, value|
        if value > hvac_bldg_type_max_floor_area
          hvac_bldg_type_with_max_floor = key
          hvac_bldg_type_max_floor_area = value
        end
        total_floor_area += value
      end

      # Reset the thermal zones by going through the hierarchy 1 logics
      bldg_type_hvac_zone_hash.clear
      # Add the thermal zones for the maximum floor (primary system)
      bldg_type_hvac_zone_hash[hvac_bldg_type_with_max_floor] = bldg_type_zone_hash[hvac_bldg_type_with_max_floor]
      bldg_type_zone_hash.each do |bldg_type, bldg_type_zone|
        # loop the rest bldg_types
        unless bldg_type.eql? hvac_bldg_type_with_max_floor
          if OpenStudio.convert(total_floor_area, 'm^2', 'ft^2').get <= 40000
            # Building is smaller than 40k sqft, it could only have one hvac_building_type, reset all the thermal zones.
            bldg_type_hvac_zone_hash[hvac_bldg_type_with_max_floor].push(*bldg_type_zone)
            OpenStudio.logFree(OpenStudio::Info, 'prm.log', "The building floor area is less than 40,000 square foot. Thermal zones under hvac building type #{bldg_type} is reset to #{hvac_bldg_type_with_max_floor}")
          else
            if OpenStudio.convert(bldg_type_zone_area_hash[bldg_type], 'm^2', 'ft^2').get < 20000
              # in this case, all thermal zones shall be categorized as the primary hvac_building_type
              bldg_type_hvac_zone_hash[hvac_bldg_type_with_max_floor].push(*bldg_type_zone)
              OpenStudio.logFree(OpenStudio::Info, 'prm.log', "The floor area in hvac building type #{bldg_type} is less than 20,000 square foot. Thermal zones under this hvac building type is reset to #{hvac_bldg_type_with_max_floor}")
            else
              bldg_type_hvac_zone_hash[bldg_type] = bldg_type_zone
            end
          end
        end
      end

      # Write in hvac building type thermal zones by thermal zone
      bldg_type_hvac_zone_hash.each do |h1_bldg_type, bldg_type_zone_array|
        bldg_type_zone_array.each do |thermal_zone|
          thermal_zone.additionalProperties.setFeature('building_type_for_hvac', h1_bldg_type)
        end
      end
    end

    # =============================SPACE user data process===========================================
    user_spaces = get_userdata(UserDataFiles::SPACE)
    model.getSpaces.each do |space|
      type_for_wwr = nil
      # Check for 2nd level hierarchy
      if user_spaces
        user_spaces.each do |user_space|
          unless user_space['building_type_for_wwr'].nil?
            if UserData.compare(space.name.get, user_space['name'])
              type_for_wwr = user_space['building_type_for_wwr']
            end
          end
        end
      end

      if type_for_wwr.nil?
        # 2nd Hierarchy does not apply, check for 3rd level hierarchy
        building_name = prm_get_optional_handler(space.model, @sizing_run_dir, 'building', 'name')
        if user_buildings
          user_buildings.each do |user_building|
            unless user_building['building_type_for_wwr'].nil?
              if UserData.compare(user_building['name'], building_name)
                type_for_wwr = user_building['building_type_for_wwr']
              end
            end
          end
        end
      end

      if type_for_wwr.nil?
        # 3rd level hierarchy does not apply, Apply 4th level hierarchy
        type_for_wwr = default_wwr_building_type
      end
      # add wwr type to space:
      space.additionalProperties.setFeature('building_type_for_wwr', type_for_wwr)
    end
    # =============================SWH user data process===========================================
    user_wateruse_equipments = get_userdata(UserDataFiles::WATERUSE_EQUIPMENT)
    model.getWaterUseEquipments.each do |wateruse_equipment|
      type_for_swh = nil
      # Check for 2nd hierarchy
      if user_wateruse_equipments
        user_wateruse_equipments.each do |user_wateruse_equipment|
          unless user_wateruse_equipment['building_type_for_swh'].nil?
            if UserData.compare(wateruse_equipment.name.get, user_wateruse_equipment['name'])
              type_for_swh = user_wateruse_equipment['building_type_for_swh']
            end
          end
        end
      end

      if type_for_swh.nil?
        # 2nd hierarchy does not apply, check for 3rd hierarchy
        # get space building type
        building_name = prm_get_optional_handler(wateruse_equipment.model, @sizing_run_dir, 'building', 'name')
        if user_buildings
          user_buildings.each do |user_building|
            unless user_building['building_type_for_swh'].nil?
              if UserData.compare(user_building['name'], building_name)
                type_for_swh = user_building['building_type_for_swh']
              end
            end
          end
        end
      end

      if type_for_swh.nil?
        # 3rd hierarchy does not apply, apply 4th hierarchy
        type_for_swh = default_swh_building_type
      end
      # add swh type to wateruse equipment:
      wateruse_equipment.additionalProperties.setFeature('building_type_for_swh', type_for_swh)
    end
    return true
  end

  # Modify the existing service water heating loops to match the baseline required heating type.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param building_type [String] the building type
  # @return [Boolean] returns true if successful, false if not
  def model_apply_baseline_swh_loops(model, building_type)
    model.getPlantLoops.each do |plant_loop|
      # Skip non service water heating loops
      next unless plant_loop_swh_loop?(plant_loop)

      # Rename the loop to avoid accidentally hooking up the HVAC systems to this loop later.
      plant_loop.setName('Service Water Heating Loop')

      htg_fuels, combination_system, storage_capacity, total_heating_capacity = plant_loop_swh_system_type(plant_loop)

      electric = true
      if htg_fuels.include?('NaturalGas') ||
         htg_fuels.include?('PropaneGas') ||
         htg_fuels.include?('FuelOilNo1') ||
         htg_fuels.include?('FuelOilNo2') ||
         htg_fuels.include?('Coal') ||
         htg_fuels.include?('Diesel') ||
         htg_fuels.include?('Gasoline')
        electric = false
      end

      # Per Table G3.1 11.e, if the baseline system was a combination of heating and service water heating,
      # delete all heating equipment and recreate a WaterHeater:Mixed.
      if combination_system
        a = plant_loop.supplyComponents
        b = plant_loop.demandComponents
        plantloop_components = a += b
        plantloop_components.each do |component|
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          next if ['OS_Node', 'OS_Pump_ConstantSpeed', 'OS_Pump_VariableSpeed', 'OS_Connector_Splitter', 'OS_Connector_Mixer', 'OS_Pipe_Adiabatic'].include?(obj_type)

          component.remove
        end

        water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)
        water_heater.setName('Baseline Water Heater')
        water_heater.setHeaterMaximumCapacity(total_heating_capacity)
        water_heater.setTankVolume(storage_capacity)
        plant_loop.addSupplyBranchForComponent(water_heater)

        if electric
          # G3.1.11.b: If electric, WaterHeater:Mixed with electric resistance
          water_heater.setHeaterFuelType('Electricity')
          water_heater.setHeaterThermalEfficiency(1.0)
        else
          # @todo for now, just get the first fuel that isn't Electricity
          # A better way would be to count the capacities associated
          # with each fuel type and use the preponderant one
          fuels = htg_fuels - ['Electricity']
          fossil_fuel_type = fuels[0]
          water_heater.setHeaterFuelType(fossil_fuel_type)
          water_heater.setHeaterThermalEfficiency(0.8)
        end
        # If it's not a combination heating and service water heating system
        # just change the fuel type of all water heaters on the system
        # to electric resistance if it's electric
      else
        # Per Table G3.1 11.i, piping losses was deleted
        plant_loop_adiabatic_pipes_only(plant_loop)

        if electric
          plant_loop.supplyComponents.each do |component|
            next unless component.to_WaterHeaterMixed.is_initialized

            water_heater = component.to_WaterHeaterMixed.get
            # G3.1.11.b: If electric, WaterHeater:Mixed with electric resistance
            water_heater.setHeaterFuelType('Electricity')
            water_heater.setHeaterThermalEfficiency(1.0)
          end
        end
      end
    end

    # Set the water heater fuel types if it's 90.1-2013
    model.getWaterHeaterMixeds.sort.each do |water_heater|
      water_heater_mixed_apply_prm_baseline_fuel_type(water_heater, building_type)
    end

    return true
  end

  # Check whether the baseline model generation needs to run all four orientations
  # The default shall be true
  # The orientation takes priority of:
  # 1. Appx G
  # 2. Method user input.
  # 3. User data override.
  #
  # @param run_all_orients [Boolean] user inputs to indicate whether it is required to run all orientations
  # @param user_model [OpenStudio::Model::Model] OpenStudio model
  # @return [Boolean] True if run all orientation is required, false otherwise
  def run_all_orientations(run_all_orients, user_model)
    run_orients_flag = false
    # Step 1 check orientation variations - priority 3
    fenestration_area_hash = get_model_fenestration_area_by_orientation(user_model)
    fenestration_area_hash.each do |orientation, fenestration_area|
      OpenStudio.logFree(OpenStudio::Info, 'prm.log',
                         "#{orientation} orientation has total fenestration area of #{fenestration_area} m2")
      fenestration_area_hash.each do |other_orientation, other_fenestration_area|
        next unless orientation != other_orientation

        variance = (other_fenestration_area - fenestration_area) / fenestration_area
        if variance.abs > 0.05
          # if greater then 0.05
          OpenStudio.logFree(OpenStudio::Info,
                             'prm.log',
                             "#{orientation} has total fenestration area of #{fenestration_area} m2, which is higher than 5% variance compare to #{other_fenestration_area} at #{other_orientation}")
          run_orients_flag = true
        end
      end
    end
    # Step 2, assign method user input if it is provided as false.
    unless run_all_orients
      OpenStudio.logFree(OpenStudio::Error,
                         'prm.log',
                         'The run_all_orientation flag is set to False, update the run to a single orientation PRM generation.')
      run_orients_flag = run_all_orients
    end
    # Step 3 read user data - priority 1 - user data will override the priority 2
    user_buildings = @standards_data.key?('userdata_building') ? @standards_data['userdata_building'] : nil
    if user_buildings
      building_name = user_model.building.get.name.get
      user_building_index = user_buildings.index { |user_building| building_name.include? user_building['name'] }
      unless user_building_index.nil? || user_buildings[user_building_index]['is_exempt_from_rotations'].nil?
        # user data exempt the rotation, No indicates true for running orients.
        OpenStudio.logFree(OpenStudio::Error,
                           'prm.log',
                           "User data in the userdata_building.csv indicate building #{building_name} is exempted from rotation. Update the run to a single orientation PRM generation.")
        # @todo need to use user data enums later.
        run_orients_flag = user_buildings[user_building_index]['is_exempt_from_rotations']
      end
    end
    run_orients_flag
  end

  # Function that extract the total fenestration area from a model by orientations.
  # Orientation is identified as N (North), S (South), E (East), W (West)
  #
  # @param user_model [OpenStudio::Model::Model] OpenStudio model
  # @return [Hash] Hash map that contains the total area of fenestration at each orientation (N, S, E, W)
  def get_model_fenestration_area_by_orientation(user_model)
    # First index is wall, second index is window
    fenestration_area_hash = {
      'N' => 0.0,
      'S' => 0.0,
      'E' => 0.0,
      'W' => 0.0
    }
    user_model.getSpaces.each do |space|
      space_cond_type = space_conditioning_category(space)
      next if space_cond_type == 'Unconditioned'

      # Get zone multiplier
      multiplier = prm_get_optional_handler(space, @sizing_run_dir, 'thermalZone').multiplier
      space.surfaces.each do |surface|
        next if surface.surfaceType != 'Wall'
        next if surface.outsideBoundaryCondition != 'Outdoors'

        orientation = OpenstudioStandards::Geometry.surface_get_cardinal_direction(surface)
        surface.subSurfaces.each do |subsurface|
          subsurface_type = subsurface.subSurfaceType.to_s.downcase
          # Do not count doors
          next unless (subsurface_type.include? 'window') || (subsurface_type.include? 'glass')

          fenestration_area_hash[orientation] += subsurface.grossArea * subsurface.multiplier * multiplier
        end
      end
    end
    return fenestration_area_hash
  end

  # Apply the standard construction to each surface in the model, based on the construction type currently assigned.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if successful, false if not
  def model_apply_constructions(model, climate_zone, wwr_building_type, wwr_info)
    model_apply_standard_constructions(model, climate_zone, wwr_building_type: wwr_building_type, wwr_info: wwr_info)

    return true
  end

  # Update ground temperature profile based on the weather file specified in the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] surfaces_with_fc_factor_boundary, returns true if successful, false if not
  def model_update_ground_temperature_profile(model, climate_zone)
    # Check if the ground temperature profile is needed
    surfaces_with_fc_factor_boundary = false
    model.getSurfaces.each do |surface|
      if surface.outsideBoundaryCondition.to_s == 'GroundFCfactorMethod'
        surfaces_with_fc_factor_boundary = true
        break
      end
    end

    if surfaces_with_fc_factor_boundary
      # Remove existing FCFactor temperature profile
      ground_temp = model.getSiteGroundTemperatureFCfactorMethod
      ground_temp.resetAllMonths

      # Get path to weather file specified in the model
      weather_file_path = prm_get_optional_handler(model.getWeatherFile, @sizing_run_dir, 'path').to_s

      # Look for stat file corresponding to the weather file
      stat_file_path = weather_file_path.sub('.epw', '.stat').to_s
      if !File.exist? stat_file_path
        # When the stat file corresponding with the weather file in the model is missing,
        # use the weather file that represent the climate zone
        climate_zone_weather_file_map = OpenstudioStandards::Weather.climate_zone_weather_file_map
        prm_raise(climate_zone_weather_file_map.key?(climate_zone),
                  @sizing_run_dir,
                  "Failed to find a matching climate zone #{climate_zone} from the climate zone weather files.")
        weather_file = climate_zone_weather_file_map[climate_zone]
        stat_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file).sub('.epw', '.stat').to_s
      end

      stat_file = OpenstudioStandards::Weather::StatFile.load(stat_file_path)
      ground_temperatures = stat_file.monthly_lagged_dry_bulb
      unless ground_temperatures.empty?
        # set the site ground temperature building surface
        ground_temp.setAllMonthlyTemperatures(ground_temperatures)
      end
    end

    return surfaces_with_fc_factor_boundary
  end

  # Generate baseline log to a specific file directory
  # @param file_directory [String] file directory
  def generate_baseline_log(file_directory)
    log_messages_to_file_prm("#{file_directory}/prm.log", false)
  end

  # This function checks whether it is required to adjust the window to wall ratio based on the model WWR and wwr limit.
  # @param wwr_limit [Double] window to wall ratio limit
  # @param wwr_list [Array] list of wwr of zone conditioning category in a building area type category - residential, nonresidential and semiheated
  # @return [Boolean] True, require adjustment, false not require adjustment
  def model_does_require_wwr_adjustment?(wwr_limit, wwr_list)
    # 90.1 PRM routine requires
    return true
  end

  # For 2019, it is required to adjusted wwr based on building categories for all other types
  #
  # @param bat [String] building category
  # @param wwr_list [Array] list of zone conditioning category-based WWR - residential, nonresidential and semiheated
  # @return [Double] return adjusted wwr_limit
  def model_get_bat_wwr_target(bat, wwr_list)
    wwr_limit = 40.0
    # Lookup WWR target from stable baseline table
    wwr_lib = standards_data['prm_wwr_bldg_type']
    search_criteria = {
      'template' => template,
      'wwr_building_type' => bat
    }
    wwr_limit_bat = model_find_object(wwr_lib, search_criteria)
    # If building type isn't found, assume that it's
    # the same as 'All Others'
    if wwr_limit_bat.nil? || bat.casecmp?('all others')
      wwr = wwr_list.max
      # All others type
      # use the min of 40% and the max wwr in the ZCC-wwr list.
      wwr_limit = [wwr_limit, wwr].min
    else
      # Matched type: use WWR from database.
      wwr_limit = wwr_limit_bat['wwr'] * 100.0
    end
    return wwr_limit
  end

  # Calculate the window to wall ratio reduction factor
  #
  # @param multiplier [Double] multiplier of the wwr
  # @param surface [OpenStudio::Model:Surface] the surface object
  # @param wwr_building_type[String] building type for wwr
  # @param wwr_target [Double] target window to wall ratio
  # @param total_wall_m2 [Double] total wall area of the category in m2.
  # @param total_wall_with_fene_m2 [Double] total wall area of the category with fenestrations in m2.
  # @param total_fene_m2 [Double] total fenestration area
  # @return [Double] reduction factor
  def surface_get_wwr_reduction_ratio(multiplier,
                                      surface,
                                      wwr_building_type: 'All others',
                                      wwr_target: nil,
                                      total_wall_m2: 0.0, # prevent 0.0 division
                                      total_wall_with_fene_m2: 0.0,
                                      total_fene_m2: 0.0,
                                      total_plenum_wall_m2: 0.0)

    surface_name = surface.name.get
    surface_wwr = OpenstudioStandards::Geometry.surface_get_window_to_wall_ratio(surface)
    surface_dr = OpenstudioStandards::Geometry.surface_get_door_to_wall_ratio(surface)

    if multiplier < 1.0
      # Case when reduction is required
      reduction_ratio = 1.0 - multiplier
      OpenStudio.logFree(OpenStudio::Info, 'prm.log',
                         "Surface #{surface_name} WWR is #{surface_wwr}. Reduce its WWR to #{surface_wwr * reduction_ratio}%")
    else
      # Case when increase is required - takes the door area into consideration.
      # The target is to increase each surface to maximum 90% WWR deduct the total door area.
      exist_max_wwr = 0.0
      if total_wall_m2 > 0 then exist_max_wwr = total_wall_with_fene_m2 * 0.9 / total_wall_m2 end
      if exist_max_wwr < wwr_target
        # In this case, it is required to add vertical fenestration to other surfaces
        if surface_wwr < 0.001
          # delta_fenestration_surface_area / delta_wall_surface_area + 1.0 = increase_ratio for a surface with no windows.
          # ASSUMPTION!! assume adding windows to surface with no windows will never be window_m2 + door_m2 > surface_m2.
          reduction_ratio = ((wwr_target - exist_max_wwr) * total_wall_m2 / (total_wall_m2 - total_wall_with_fene_m2 - total_plenum_wall_m2)) + 1.0
          OpenStudio.logFree(OpenStudio::Info, 'prm.log',
                             "The max window to wall ratio is #{exist_max_wwr}, smaller than the target window to wall ratio #{wwr_target}.
                              Surface #{surface_name} has no fenestration subsurfaces. Adding new fenestration band with WWR of #{(reduction_ratio - 1) * 100}%")
        else
          # surface has fenestration - expand it to 90% WWR or surface area minus door area, whichever is smaller.
          if (1.0 - surface_dr) < 0.9
            # A negative reduction ratio as a flat to main function that this reduction ratio is adjusted by doors
            # and it is needed to adjust the WWR of the no fenestration surfaces to meet the lost
            reduction_ratio = (surface_dr - 1.0) / surface_wwr
          else
            reduction_ratio = 0.9 / surface_wwr
          end
          OpenStudio.logFree(OpenStudio::Info, 'prm.log',
                             "The max window to wall ratio is #{exist_max_wwr}, smaller than the target window to wall ratio #{wwr_target}.
                              Surface #{surface_name} will expand its WWR to 90%")
        end
      else
        # multiplier will be negative number thus resulting in > 1 reduction_ratio
        if surface_wwr < 0.001
          # 1.0 means remain the original form
          reduction_ratio = 1.0
        else
          reduction_ratio = multiplier
        end
      end
    end
    return reduction_ratio
  end

  # Readjusted the WWR for surfaces previously has no windows to meet the
  # overall WWR requirement.
  # This function shall only be called if the maximum WWR value for surfaces with fenestration is lower than 90% due to
  # accommodating the total door surface areas
  #
  # @param residual_ratio [Double] the ratio of residual surfaces among the total wall surface area with no fenestrations
  # @param space [OpenStudio::Model:Space] a space
  # @param model [OpenStudio::Model::Model] openstudio model
  # @return [Boolean] returns true if successful, false if not
  def model_readjust_surface_wwr(residual_ratio, space, model)
    # In this loop, we will focus on the surfaces with newly added a fenestration.
    space.surfaces.sort.each do |surface|
      next unless surface.additionalProperties.hasFeature('added_wwr')

      added_wwr = surface.additionalProperties.getFeatureAsDouble('added_wwr').to_f
      # The full calculation of adjustment is:
      # ((residual_ratio * surface_area + added_wwr * surface_area) / surface_area ) / added_wwr
      adjustment_ratio = (residual_ratio / added_wwr) + 1.0
      surface_adjust_fenestration_in_a_surface(surface, adjustment_ratio, model)
    end
  end

  # Assign spaces to system groups based on building area type
  # Get zone groups separately for each hvac building type
  #
  # @param model [OpenStudio::Model::Model] openstudio model
  # @param custom [String] identifier for custom programs, not used here, but included for backwards compatibility
  # @param bldg_type_hvac_zone_hash [Hash of bldg_type:list of zone objects] association of zones to each hvac building type
  # @return [Array<Hash>] an array of hashes of area information,
  #   with keys area_ft2, type, fuel, and zones (an array of zones)
  def model_prm_baseline_system_groups(model, custom, bldg_type_hvac_zone_hash)
    bldg_groups = []

    bldg_type_hvac_zone_hash.each_key do |hvac_building_type, zones_in_building_type|
      # Get all groups for this hvac building type
      new_groups = get_baseline_system_groups_for_one_building_type(model, hvac_building_type, zones_in_building_type)

      # Add the groups for this hvac building type to the full list
      new_groups.each do |group|
        bldg_groups << group
      end
    end

    return bldg_groups
  end

  # Assign spaces to system groups for one hvac building type
  # One group contains all zones associated with one HVAC type
  # Separate groups are made for laboratories, computer rooms, district cooled zones, heated-only zones, or hybrids of these
  # Groups may include zones from multiple floors; separating by floor is handled later
  # For stable baseline, heating type is based on climate, not proposed heating type
  # Isolate zones that have heating-only or district (purchased) heat or chilled water
  # @param hvac_building_type [String] Chosen by user via measure interface or user data files
  # @param zones_in_building_type [Array<OpenStudio::Model::ThermalZone>] array of thermal zones
  # @return [Array<Hash>] an array of hashes of area information,
  #   with keys area_ft2, type, fuel, and zones (an array of zones)
  def get_baseline_system_groups_for_one_building_type(model, hvac_building_type, zones_in_building_type)
    # Build zones hash of [zone, zone area, occupancy type, building type, fuel]
    zones = model_zones_with_occ_and_fuel_type(model, 'custom')

    # Ensure that there is at least one conditioned zone
    prm_raise(!zones.empty?, @sizing_run_dir, 'The building does not appear to have any conditioned zones. Make sure zones have thermostat with appropriate heating and cooling setpoint schedules.')

    # Consider special rules for computer rooms
    # need load of all
    # Get cooling load of all computer rooms to establish system types
    comp_room_loads = {}
    bldg_comp_room_load = 0
    zones.each do |zn|
      zone_load = 0.0
      has_computer_room = false
      # First check if any space in zone has a computer room
      zn['zone'].spaces.each do |space|
        if prm_get_optional_handler(space, @sizing_run_dir, 'spaceType', 'standardsSpaceType') == 'computer room'
          has_computer_room = true
          break
        end
      end
      if has_computer_room
        # Collect load for entire zone
        if zn['zone'].model.version < OpenStudio::VersionString.new('3.6.0')
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.ashrae_90_1_prm.Model', 'Required ThermalZone method .autosizedCoolingDesignLoad is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
        end
        zone_load_w = zn['zone'].autosizedCoolingDesignLoad.get
        zone_load_w *= zn['zone'].multiplier
        zone_load = OpenStudio.convert(zone_load_w, 'W', 'Btu/hr').get
      end
      comp_room_loads[zn['zone'].name.get] = zone_load
      bldg_comp_room_load += zone_load
    end

    # Lab zones are grouped separately if total lab exhaust in building > 15000 cfm
    # Make list of zone objects that contain laboratory spaces
    lab_zones = []
    has_lab_spaces = {}
    model.getThermalZones.each do |zone|
      # Check if this zone includes laboratory space
      zone.spaces.each do |space|
        space_type = prm_get_optional_handler(space, @sizing_run_dir, 'spaceType', 'standardsSpaceType')
        zone_name = zone.name.get
        has_lab_spaces[zone_name] = false
        if space_type == 'laboratory'
          lab_zones << zone
          has_lab_spaces[zone_name] = true
          break
        end
      end
    end

    lab_exhaust_si = 0
    lab_relief_si = 0
    if !lab_zones.empty?
      # Build a hash of return_node:zone_name
      node_list = {}
      zone_return_flow_si = Hash.new(0)
      var_name = 'System Node Standard Density Volume Flow Rate'
      frequency = 'hourly'
      model.getThermalZones.each do |zone|
        port_list = zone.returnPortList
        port_list_objects = port_list.modelObjects
        port_list_objects.each do |node|
          node_name = node.nameString
          node_list[node_name] = zone.name.get
        end
        zone_return_flow_si[zone.name.get] = 0
      end

      # Get return air flow for each zone (even non-lab zones are needed)
      # Take from hourly reports created during sizing run
      node_list.each do |node_name, zone_name|
        sql = model.sqlFile
        prm_raise(sql.is_initialized, @sizing_run_dir, 'Model is missing SQL file. It is likely caused by: 1. unsuccessful simulation, 2. SQL is not set as one of the output file.')
        sql = sql.get
        query = "SELECT ReportDataDictionaryIndex FROM ReportDataDictionary WHERE KeyValue = '#{node_name}' COLLATE NOCASE"
        val = sql.execAndReturnFirstDouble(query)
        prm_raise(val.is_initialized, @sizing_run_dir, "No hourly return air flow data reported for node #{node_name}")
        report_data_dict_index = val.get
        query = "SELECT MAX(Value) FROM ReportData WHERE ReportDataDictionaryIndex = '#{report_data_dict_index}'"
        val = sql.execAndReturnFirstDouble(query)
        prm_raise(val.is_initialized, @sizing_run_dir, "No hourly return air flow data reported at report index #{report_data_dict_index}")
        zone_return_flow_si[zone_name] += OpenStudio::OptionalDouble.new(val.get).to_f
      end

      # Calc ratio of Air Loop relief to sum of zone return for each air loop
      # and store in zone hash

      # For each air loop, get relief air flow and calculate lab exhaust from the central air handler
      # Take from hourly reports created during sizing run
      zone_relief_flow_si = {}
      model.getAirLoopHVACs.each do |air_loop_hvac|
        # First get relief air flow from sizing run sql file
        relief_node = prm_get_optional_handler(air_loop_hvac, @sizing_run_dir, 'reliefAirNode')
        node_name = relief_node.nameString
        relief_flow_si = 0
        relief_fraction = 0
        sql = model.sqlFile
        prm_raise(sql.is_initialized, @sizing_run_dir, 'Model is missing SQL file. It is likely caused by: 1. unsuccessful simulation, 2. SQL is not set as one of the output file.')
        sql = sql.get
        query = "SELECT ReportDataDictionaryIndex FROM ReportDataDictionary WHERE KeyValue = '#{node_name}' COLLATE NOCASE"
        val = sql.execAndReturnFirstDouble(query)
        query = "SELECT MAX(Value) FROM ReportData WHERE ReportDataDictionaryIndex = '#{val.get}'"
        val = sql.execAndReturnFirstDouble(query)
        if val.is_initialized
          result = OpenStudio::OptionalDouble.new(val.get)
        end
        relief_flow_si = result.to_f

        # Get total flow of zones on this air loop
        total_zone_return_si = 0
        air_loop_hvac.thermalZones.each do |zone|
          total_zone_return_si += zone_return_flow_si[zone.name.get]
        end

        relief_fraction = relief_flow_si / total_zone_return_si unless total_zone_return_si == 0

        # For each zone calc total effective exhaust
        air_loop_hvac.thermalZones.each do |zone|
          zone_relief_flow_si[zone.name.get] = relief_fraction * zone_return_flow_si[zone.name.get]
        end
      end

      # Now check for exhaust driven by zone exhaust fans
      lab_zones.each do |zone|
        zone.equipment.each do |zone_equipment|
          # Get tally of exhaust fan flow
          if zone_equipment.to_FanZoneExhaust.is_initialized
            zone_exh_fan = zone_equipment.to_FanZoneExhaust.get
            # Check if any spaces in this zone are laboratory
            lab_exhaust_si += zone_exh_fan.maximumFlowRate.get
          end
        end

        # Also account for outdoor air exhausted from this zone via return/relief
        lab_relief_si += zone_relief_flow_si[zone.name.get]
      end
    end

    lab_exhaust_si += lab_relief_si
    lab_exhaust_cfm = OpenStudio.convert(lab_exhaust_si, 'm^3/s', 'cfm').get

    # Isolate computer rooms onto separate groups
    # Computer rooms may need to be split to two groups, depending on load
    # Isolate heated-only and destrict cooling zones onto separate groups
    # District heating does not require separate group
    final_groups = []
    # Initialize arrays of zone objects by category
    heated_only_zones = []
    heated_cooled_zones = []
    district_cooled_zones = []
    comp_room_svav_zones = []
    comp_room_psz_zones = []
    dist_comp_room_svav_zones = []
    dist_comp_room_psz_zones = []
    lab_zones = []

    total_area_ft2 = 0
    zones.each do |zn|
      if OpenstudioStandards::ThermalZone.thermal_zone_heated?(zn['zone']) && !OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zn['zone'])
        # this will occur when there is no cooling tstat, or when min cooling setpoint is above 91 F
        heated_only_zones << zn['zone']
      elsif comp_room_loads[zn['zone'].name.get] > 0
        # This is a computer room zone
        if bldg_comp_room_load > 3_000_000 || comp_room_loads[zn['zone'].name.get] > 600_000
          # System 11
          if zn['fuel'].include?('DistrictCooling')
            dist_comp_room_svav_zones << zn['zone']
          else
            comp_room_svav_zones << zn['zone']
          end
        else
          # PSZ
          if zn['fuel'].include?('DistrictCooling')
            dist_comp_room_psz_zones << zn['zone']
          else
            comp_room_psz_zones << zn['zone']
          end
        end

      elsif has_lab_spaces[zn['zone'].name.get] && lab_exhaust_cfm > 15_000
        lab_zones << zn['zone']
      elsif zn['fuel'].include?('DistrictCooling')
        district_cooled_zones << zn['zone']
      else
        heated_cooled_zones << zn['zone']
      end
      # Collect total floor area of all zones for this building area type
      area_m2 = zn['zone'].floorArea * zn['zone'].multiplier
      total_area_ft2 += OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
    end

    # Build final_groups array
    unless heated_only_zones.empty?
      htd_only_group = {}
      htd_only_group['occ'] = 'heated-only storage'
      htd_only_group['fuel'] = 'any'
      htd_only_group['zone_group_type'] = 'heated_only_zones'
      area_m2 = 0
      heated_only_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      htd_only_group['group_area_ft2'] = area_ft2
      htd_only_group['building_area_type_ft2'] = total_area_ft2
      htd_only_group['zones'] = heated_only_zones
      final_groups << htd_only_group
    end
    unless district_cooled_zones.empty?
      district_cooled_group = {}
      district_cooled_group['occ'] = hvac_building_type
      district_cooled_group['fuel'] = 'districtcooling'
      district_cooled_group['zone_group_type'] = 'district_cooled_zones'
      area_m2 = 0
      district_cooled_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      district_cooled_group['group_area_ft2'] = area_ft2
      district_cooled_group['building_area_type_ft2'] = total_area_ft2
      district_cooled_group['zones'] = district_cooled_zones
      # store info if any zone has district, fuel, or electric heating
      district_cooled_group['fuel'] = get_group_heat_types(model, district_cooled_zones)
      final_groups << district_cooled_group
    end
    unless heated_cooled_zones.empty?
      heated_cooled_group = {}
      heated_cooled_group['occ'] = hvac_building_type
      heated_cooled_group['fuel'] = 'any'
      heated_cooled_group['zone_group_type'] = 'heated_cooled_zones'
      area_m2 = 0
      heated_cooled_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      heated_cooled_group['group_area_ft2'] = area_ft2
      heated_cooled_group['building_area_type_ft2'] = total_area_ft2
      heated_cooled_group['zones'] = heated_cooled_zones
      # store info if any zone has district, fuel, or electric heating
      heated_cooled_group['fuel'] = get_group_heat_types(model, heated_cooled_zones)
      final_groups << heated_cooled_group
    end
    unless lab_zones.empty?
      lab_group = {}
      lab_group['occ'] = hvac_building_type
      lab_group['fuel'] = 'any'
      lab_group['zone_group_type'] = 'lab_zones'
      area_m2 = 0
      lab_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      lab_group['group_area_ft2'] = area_ft2
      lab_group['building_area_type_ft2'] = total_area_ft2
      lab_group['zones'] = lab_zones
      # store info if any zone has district, fuel, or electric heating
      lab_group['fuel'] = get_group_heat_types(model, lab_zones)
      final_groups << lab_group
    end
    unless comp_room_svav_zones.empty?
      comp_room_svav_group = {}
      comp_room_svav_group['occ'] = 'computer room szvav'
      comp_room_svav_group['fuel'] = 'any'
      comp_room_svav_group['zone_group_type'] = 'computer_zones'
      area_m2 = 0
      comp_room_svav_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      comp_room_svav_group['group_area_ft2'] = area_ft2
      comp_room_svav_group['building_area_type_ft2'] = total_area_ft2
      comp_room_svav_group['zones'] = comp_room_svav_zones
      # store info if any zone has district, fuel, or electric heating
      comp_room_svav_group['fuel'] = get_group_heat_types(model, comp_room_svav_zones)
      final_groups << comp_room_svav_group
    end
    unless comp_room_psz_zones.empty?
      comp_room_psz_group = {}
      comp_room_psz_group['occ'] = 'computer room psz'
      comp_room_psz_group['fuel'] = 'any'
      comp_room_psz_group['zone_group_type'] = 'computer_zones'
      area_m2 = 0
      comp_room_psz_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      comp_room_psz_group['group_area_ft2'] = area_ft2
      comp_room_psz_group['building_area_type_ft2'] = total_area_ft2
      comp_room_psz_group['zones'] = comp_room_psz_zones
      # store info if any zone has district, fuel, or electric heating
      comp_room_psz_group['fuel'] = get_group_heat_types(model, comp_room_psz_zones)
      final_groups << comp_room_psz_group
    end
    unless dist_comp_room_svav_zones.empty?
      dist_comp_room_svav_group = {}
      dist_comp_room_svav_group['occ'] = hvac_building_type
      dist_comp_room_svav_group['fuel'] = 'districtcooling'
      dist_comp_room_svav_group['zone_group_type'] = 'computer_zones'
      area_m2 = 0
      dist_comp_room_svav_zones.each do |zone|
        area_m2 += zone.floorArea * zone.multiplier
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      dist_comp_room_svav_group['group_area_ft2'] = area_ft2
      dist_comp_room_svav_group['building_area_type_ft2'] = total_area_ft2
      dist_comp_room_svav_group['zones'] = dist_comp_room_svav_zones
      # store info if any zone has district, fuel, or electric heating
      dist_comp_room_svav_group['fuel'] = get_group_heat_types(model, dist_comp_room_svav_zones)
      final_groups << dist_comp_room_svav_group
    end
    unless dist_comp_room_psz_zones.empty?
      dist_comp_room_psz_group = {}
      dist_comp_room_psz_group['occ'] = hvac_building_type
      dist_comp_room_psz_group['fuel'] = 'districtcooling'
      dist_comp_room_psz_group['zone_group_type'] = 'computer_zones'
      area_m2 = 0
      dist_comp_room_psz_zones.each do |zone|
      end
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      dist_comp_room_psz_group['group_area_ft2'] = area_ft2
      dist_comp_room_psz_group['building_area_type_ft2'] = total_area_ft2
      dist_comp_room_psz_group['zones'] = dist_comp_room_psz_zones
      # store info if any zone has district, fuel, or electric heating
      dist_comp_room_psz_group['fuel'] = get_group_heat_types(model, dist_comp_room_psz_zones)
      final_groups << dist_comp_room_psz_group
    end

    ngrps = final_groups.count
    # Determine the number of stories spanned by each group and report out info.
    final_groups.each do |group|
      # Determine the number of stories this group spans
      group['stories'] = OpenstudioStandards::Geometry.thermal_zones_get_number_of_stories_spanned(group['zones'])
      # Report out the final grouping
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Final system type group: occ = #{group['occ']}, fuel = #{group['fuel']}, area = #{group['group_area_ft2'].round} ft2, num stories = #{group['stories']}, zones:")
      group['zones'].sort.each_slice(5) do |zone_list|
        zone_names = []
        zone_list.each do |zone|
          zone_names << zone.name.get.to_s
        end
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{zone_names.join(', ')}")
      end
    end

    return final_groups
  end

  # Alternate method for 2016 and later stable baseline
  # Limits for each building area type are taken from data table
  # Heating fuel is based on climate zone, unless district heat is in proposed
  #
  # @note Select system type from data table base on key parameters
  # @param climate_zone [String] id code for the climate
  # @param sys_group [Hash] Hash defining a group of zones that have the same Appendix G system type
  # @param custom [String] included here for backwards compatibility (not used here)
  # @param hvac_building_type [String] Chosen by user via measure interface or user data files
  # @param district_heat_zones [Hash] of zone name => true for has district heat, false for has not
  # @return [String] The system type.  Possibilities are PTHP, PTAC, PSZ_AC, PSZ_HP, PVAV_Reheat, PVAV_PFP_Boxes,
  #   VAV_Reheat, VAV_PFP_Boxes, Gas_Furnace, Electric_Furnace
  def model_prm_baseline_system_type(model, climate_zone, sys_group, custom, hvac_building_type, district_heat_zones)
    area_type = sys_group['occ']
    fuel_type = sys_group['fuel']
    area_ft2 = sys_group['building_area_type_ft2']
    num_stories = sys_group['stories']

    #             [type, central_heating_fuel, zone_heating_fuel, cooling_fuel]
    system_type = [nil, nil, nil, nil]

    # Find matching record from prm baseline hvac table
    # First filter by number of stories
    i_story_group = 0
    props = {}
    0.upto(9) do |i|
      i_story_group += 1
      props = model_find_object(standards_data['prm_baseline_hvac'],
                                'template' => template,
                                'hvac_building_type' => area_type,
                                'flrs_range_group' => i_story_group,
                                'area_range_group' => 1)

      prm_raise(props, @sizing_run_dir, "Could not find baseline HVAC type for: #{template}-#{area_type}.")
      if num_stories <= props['bldg_flrs_max']
        # Story Group Is found
        break
      end
    end

    # Next filter by floor area
    i_area_group = 0
    loop do
      i_area_group += 1
      props = model_find_object(standards_data['prm_baseline_hvac'],
                                'template' => template,
                                'hvac_building_type' => area_type,
                                'flrs_range_group' => i_story_group,
                                'area_range_group' => i_area_group)

      prm_raise(props && i_area_group <= 9, @sizing_run_dir, "Could not find baseline HVAC type for: #{template}-#{area_type}.")
      below_max = false
      above_min = false
      # check if actual building floor area is within range for this area group
      if props['max_area_qual'] == 'LT'
        if area_ft2 < props['bldg_area_max']
          below_max = true
        end
      elsif props['max_area_qual'] == 'LE'
        if area_ft2 <= props['bldg_area_max']
          below_max = true
        end
      end
      if props['min_area_qual'] == 'GT'
        if area_ft2 > props['bldg_area_min']
          above_min = true
        end
      elsif props['min_area_qual'] == 'GE'
        if area_ft2 >= props['bldg_area_min']
          above_min = true
        end
      end
      if above_min && below_max
        # break condition.
        break
      end
    end

    heat_type = find_prm_heat_type(hvac_building_type, climate_zone)

    # hash to relate apx G systype categories to sys types for model
    sys_hash = {}
    if heat_type == 'fuel'
      sys_hash['PTAC'] = 'PTAC'
      sys_hash['PSZ'] = 'PSZ_AC'
      sys_hash['SZ-CV'] = 'SZ_CV'
      sys_hash['Heating and ventilation'] = 'Gas_Furnace'
      sys_hash['PSZ-AC'] = 'PSZ_AC'
      sys_hash['Packaged VAV'] = 'PVAV_Reheat'
      sys_hash['VAV'] = 'VAV_Reheat'
      sys_hash['Unconditioned'] = 'None'
      sys_hash['SZ-VAV'] = 'SZ_VAV'
    else
      sys_hash['PTAC'] = 'PTHP'
      sys_hash['PSZ'] = 'PSZ_HP'
      sys_hash['SZ-CV'] = 'SZ_CV'
      sys_hash['Heating and ventilation'] = 'Electric_Furnace'
      sys_hash['PSZ-AC'] = 'PSZ_HP'
      sys_hash['Packaged VAV'] = 'PVAV_PFP_Boxes'
      sys_hash['VAV'] = 'VAV_PFP_Boxes'
      sys_hash['Unconditioned'] = 'None'
      sys_hash['SZ-VAV'] = 'SZ_VAV'
    end

    model_sys_type = sys_hash[props['system_type']]

    if /districtheating/i =~ fuel_type
      central_heat = 'DistrictHeating'
    elsif heat_type =~ /fuel/i
      central_heat = 'NaturalGas'
    else
      central_heat = 'Electricity'
    end
    if /districtheating/i =~ fuel_type && /elec/i !~ fuel_type && /fuel/i !~ fuel_type
      # if no zone has fuel or elect, set default to district for zones
      zone_heat = 'DistrictHeating'
    elsif heat_type =~ /fuel/i
      zone_heat = 'NaturalGas'
    else
      zone_heat = 'Electricity'
    end
    if /districtcooling/i =~ fuel_type
      cool_type = 'DistrictCooling'
    elsif props['system_type'] =~ /Heating and ventilation/i || props['system_type'] =~ /unconditioned/i
      cool_type = nil
    end

    system_type = [model_sys_type, central_heat, zone_heat, cool_type]
    return system_type
  end

  # For a multizone system, create the fan schedule based on zone occupancy/fan schedules
  # @author Doug Maddox, PNNL
  # @param model [OpenStudio::Model::Model] openstudio model
  # @param zone_op_hrs [Hash] of hash of zoneName zone_op_hrs
  # @param pri_zones [Array<String>] names of zones served by the multizone system
  # @param system_name [String] name of air loop
  def model_create_multizone_fan_schedule(model, zone_op_hrs, pri_zones, system_name)
    # Create fan schedule for multizone system
    fan_8760 = []
    # If any zone is on for an hour, then the system fan must be on for that hour
    pri_zones.each do |zone|
      zone_name = zone.name.get.to_s
      if fan_8760.empty?
        fan_8760 = zone_op_hrs[zone_name]
      else
        (0..fan_8760.size - 1).each do |ihr|
          if zone_op_hrs[zone_name][ihr] > 0
            fan_8760[ihr] = 1
          end
        end
      end
    end

    # Convert 8760 array to schedule ruleset
    fan_sch_limits = model.getScheduleTypeLimitsByName('fan schedule limits for prm')
    if fan_sch_limits.empty?
      fan_sch_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
      fan_sch_limits.setName('fan schedule limits for prm')
      fan_sch_limits.setNumericType('DISCRETE')
      fan_sch_limits.setUnitType('Dimensionless')
      fan_sch_limits.setLowerLimitValue(0)
      fan_sch_limits.setUpperLimitValue(1)
    else
      fan_sch_limits = fan_sch_limits.get
    end
    sch_name = "#{system_name} fan schedule"
    make_ruleset_sched_from_8760(model, fan_8760, sch_name, fan_sch_limits)

    air_loop = model.getAirLoopHVACByName(system_name).get
    air_loop.additionalProperties.setFeature('fan_sched_name', sch_name)
  end

  # For a multizone system, identify any zones to isolate to separate PSZ systems
  # isolated zones are on the 'secondary' list
  # This version of the method applies to standard years 2016 and later (stable baseline)
  # @author Doug Maddox, PNNL
  # @param model
  # @param zones [Array<Object>]
  # @param zone_fan_scheds [Hash] hash of zoneName 8760FanSchedPerZone
  # @return [Hash] A hash of two arrays of ThermalZones,
  #   where the keys are 'primary' and 'secondary'
  def model_differentiate_primary_secondary_thermal_zones(model, zones, zone_fan_scheds)
    pri_zones = []
    sec_zones = []
    pri_zone_names = []
    sec_zone_names = []
    zone_op_hrs = {} # hash of zoneName: 8760 array of operating hours

    # If there is only one zone, then set that as primary
    if zones.size == 1
      zones.each do |zone|
        pri_zones << zone
        pri_zone_names << zone.name.get.to_s
        zone_name = zone.name.get.to_s
        if zone_fan_scheds.key?(zone_name)
          zone_fan_sched = zone_fan_scheds[zone_name]
        else
          zone_fan_sched = nil
        end
        zone_op_hrs[zone.name.get.to_s] = thermal_zone_get_annual_operating_hours(model, zone, zone_fan_sched)
      end
      # Report out the primary vs. secondary zones
      unless sec_zone_names.empty?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Secondary system zones = #{sec_zone_names.join(', ')}.")
      end

      return { 'primary' => pri_zones, 'secondary' => sec_zones, 'zone_op_hrs' => zone_op_hrs }
    end

    zone_eflh = {} # hash of zoneName: eflh for zone
    zone_max_load = {}  # hash of zoneName: coincident max internal load
    load_limit = 10     # differ by 10 Btu/hr-sf or more
    eflh_limit = 40     # differ by more than 40 EFLH/week from average of other zones
    zone_area = {} # hash of zoneName:area

    # Get coincident peak internal load for each zone
    zones.each do |zone|
      zone_name = zone.name.get.to_s
      if zone_fan_scheds.key?(zone_name)
        zone_fan_sched = zone_fan_scheds[zone_name]
      else
        zone_fan_sched = nil
      end
      zone_op_hrs[zone_name] = thermal_zone_get_annual_operating_hours(model, zone, zone_fan_sched)
      zone_eflh[zone_name] = thermal_zone_occupancy_eflh(zone, zone_op_hrs[zone_name])
      zone_max_load_w = thermal_zone_peak_internal_load(model, zone)
      zone_max_load_w_m2 = zone_max_load_w / zone.floorArea
      zone_max_load[zone_name] = OpenStudio.convert(zone_max_load_w_m2, 'W/m^2', 'Btu/hr*ft^2').get
      zone_area[zone_name] = zone.floorArea
    end

    # Eliminate all zones for which both max load and EFLH exceed limits
    zones.each do |zone|
      zone_name = zone.name.get.to_s
      max_load = zone_max_load[zone_name]
      avg_max_load = get_wtd_avg_of_other_zones(zone_max_load, zone_area, zone_name)
      max_load_diff = (max_load - avg_max_load).abs
      avg_eflh = get_avg_of_other_zones(zone_eflh, zone_name)
      eflh_diff = (avg_eflh - zone_eflh[zone_name]).abs

      if max_load_diff >= load_limit && eflh_diff > eflh_limit
        # Add zone to secondary list, and remove from hashes
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Zone moved to PSZ due to load AND eflh: #{zone_name}; load limit = #{load_limit}, eflh_limit = #{eflh_limit}")
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "load diff = #{max_load_diff}, this zone load = #{max_load}, avg zone load = #{avg_max_load}")
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "eflh diff = #{eflh_diff}, this zone load = #{zone_eflh[zone_name]}, avg zone eflh = #{avg_eflh}")

        sec_zones << zone
        sec_zone_names << zone_name
        zone_eflh.delete(zone_name)
        zone_max_load.delete(zone_name)
      end
    end

    # Eliminate worst zone where EFLH exceeds limit
    # Repeat until all zones are within limit
    num_zones = zone_eflh.size
    avg_eflh_save = 0
    max_zone_name = ''
    max_eflh_diff = 0
    max_zone = nil
    (1..num_zones).each do |izone|
      # This loop is to iterate to eliminate one zone at a time
      max_eflh_diff = 0
      zones.each do |zone|
        # This loop finds the worst remaining zone to eliminate if above threshold
        zone_name = zone.name.get.to_s
        next if !zone_eflh.key?(zone_name)

        avg_eflh = get_avg_of_other_zones(zone_eflh, zone_name)
        eflh_diff = (avg_eflh - zone_eflh[zone_name]).abs
        if eflh_diff > max_eflh_diff
          max_eflh_diff = eflh_diff
          max_zone_name = zone_name
          max_zone = zone
          avg_eflh_save = avg_eflh
        end
      end

      # All zones are now within the limit, exit the iteration
      break unless max_eflh_diff > eflh_limit

      # Move the max Zone to the secondary list
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Zone moved to PSZ due to eflh: #{max_zone_name}; limit = #{eflh_limit}")
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "eflh diff = #{max_eflh_diff}, this zone load = #{zone_eflh[max_zone_name]}, avg zone eflh = #{avg_eflh_save}")
      sec_zones << max_zone
      sec_zone_names << max_zone_name
      zone_eflh.delete(max_zone_name)
      zone_max_load.delete(max_zone_name)
    end

    # Eliminate worst zone where max load exceeds limit and repeat until all pass
    num_zones = zone_eflh.size
    highest_max_load_diff = -1
    highest_zone = nil
    highest_zone_name = ''
    highest_max_load = 0
    avg_max_load_save = 0

    (1..num_zones).each do |izone|
      # This loop is to iterate to eliminate one zone at a time
      highest_max_load_diff = 0
      zones.each do |zone|
        # This loop finds the worst remaining zone to eliminate if above threshold
        zone_name = zone.name.get.to_s
        next if !zone_max_load.key?(zone_name)

        max_load = zone_max_load[zone_name]
        avg_max_load = get_wtd_avg_of_other_zones(zone_max_load, zone_area, zone_name)
        max_load_diff = (max_load - avg_max_load).abs
        if max_load_diff >= highest_max_load_diff
          highest_max_load_diff = max_load_diff
          highest_zone_name = zone_name
          highest_zone = zone
          highest_max_load = max_load
          avg_max_load_save = avg_max_load
        end
      end

      # All zones are now within the limit, exit the iteration
      break unless highest_max_load_diff > load_limit

      # Move the max Zone to the secondary list
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Zone moved to PSZ due to load: #{highest_zone_name}; load limit = #{load_limit}")
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "load diff = #{highest_max_load_diff}, this zone load = #{highest_max_load}, avg zone load = #{avg_max_load_save}")
      sec_zones << highest_zone
      sec_zone_names << highest_zone_name
      zone_eflh.delete(highest_zone_name)
      zone_max_load.delete(highest_zone_name)
    end

    # Place remaining zones in multizone system list
    zone_eflh.each_key do |key|
      zones.each do |zone|
        if key == zone.name.get.to_s
          pri_zones << zone
          pri_zone_names << key
        end
      end
    end

    # Report out the primary vs. secondary zones
    unless pri_zone_names.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Primary system zones = #{pri_zone_names.join(', ')}.")
    end
    unless sec_zone_names.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Secondary system zones = #{sec_zone_names.join(', ')}.")
    end

    return { 'primary' => pri_zones, 'secondary' => sec_zones, 'zone_op_hrs' => zone_op_hrs }
  end

  # This method is a catch-all run at the end of create-baseline to make final adjustements to HVAC capacities
  # to account for recent model changes
  # @author Doug Maddox, PNNL
  # @param model
  # @return [Boolean] returns true if successful, false if not
  def model_refine_size_dependent_values(model, sizing_run_dir)
    # Final sizing run before refining size-dependent values
    if model_run_sizing_run(model, "#{sizing_run_dir}/SR3") == false
      return false
    end

    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      # Reset secondary design secondary flow rate based on updated primary flow
      air_loop_hvac.demandComponents.each do |dc|
        next if dc.to_AirTerminalSingleDuctParallelPIUReheat.empty?

        pfp_term = dc.to_AirTerminalSingleDuctParallelPIUReheat.get
        sec_flow_frac = 0.5

        # Get the maximum flow rate through the terminal
        max_primary_air_flow_rate = nil
        if pfp_term.maximumPrimaryAirFlowRate.is_initialized
          max_primary_air_flow_rate = pfp_term.maximumPrimaryAirFlowRate.get
        elsif pfp_term.autosizedMaximumPrimaryAirFlowRate.is_initialized
          max_primary_air_flow_rate = pfp_term.autosizedMaximumPrimaryAirFlowRate.get
        end

        max_sec_flow_rate_m3_per_s = max_primary_air_flow_rate * sec_flow_frac
        pfp_term.setMaximumSecondaryAirFlowRate(max_sec_flow_rate_m3_per_s)
      end
    end
    return true
  end

  # Determine whether heating type is fuel or electric
  # @param hvac_building_type [String] Key for lookup of baseline system type
  # @param climate_zone [String] full name of climate zone
  # @return [String] fuel or electric
  def find_prm_heat_type(hvac_building_type, climate_zone)
    climate_code = climate_zone.split('-')[-1]
    heat_type_props = model_find_object(standards_data['prm_heat_type'],
                                        'template' => template,
                                        'hvac_building_type' => hvac_building_type,
                                        'climate_zone' => climate_code)
    if !heat_type_props
      # try again with wild card for climate
      heat_type_props = model_find_object(standards_data['prm_heat_type'],
                                          'template' => template,
                                          'hvac_building_type' => hvac_building_type,
                                          'climate_zone' => 'any')
    end

    if !heat_type_props
      # try again with wild card for building type
      heat_type_props = model_find_object(standards_data['prm_heat_type'],
                                          'template' => template,
                                          'hvac_building_type' => 'all others',
                                          'climate_zone' => climate_code)
    end
    prm_raise(heat_type_props, @sizing_run_dir, "Could not find baseline heat type for: #{template}-#{hvac_building_type}-#{climate_zone}.")
    return heat_type_props['heat_type']
  end

  def has_space_conditioning_category
    true
  end

  private

  # Check if the PRM process uses user data. The function returns a hash when
  # 1. There is a matching user data
  # 2. The matching user data is not nil saved in the @standards_data
  # 3. The matching user data hash is not empty
  # The function returns nil if none of the above matched.
  #
  # @param user_data_csv [String] the name of the user data csv file
  # @return [hash | nil] Returns hash or nil.
  def get_userdata(user_data_csv)
    return @standards_data.key?(user_data_csv) && @standards_data[user_data_csv].length >= 1 ? @standards_data[user_data_csv] : nil
  end
end
