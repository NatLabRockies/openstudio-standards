class ASHRAE901PRM < Standard
  # @!group SpaceType

  # Sets the selected internal loads to standards-based or typical values.
  # For each category that is selected get all load instances. Remove all
  # but the first instance if multiple instances.  Add a new instance/definition
  # if no instance exists. Modify the definition for the remaining instance
  # to have the specified values. This method does not alter any
  # loads directly assigned to spaces.  This method skips plenums.
  #
  # @param space_type [OpenStudio::Model::SpaceType] space type object
  # @param set_people [Boolean] if true, set the people density.
  #   Also, assign reasonable clothing, air velocity, and work efficiency inputs
  #   to allow reasonable thermal comfort metrics to be calculated.
  # @param set_lights [Boolean] if true, set the lighting density, lighting fraction
  #   to return air, fraction radiant, and fraction visible.
  # @param set_electric_equipment [Boolean] if true, set the electric equipment density
  # @param set_gas_equipment [Boolean] if true, set the gas equipment density
  # @param set_ventilation [Boolean] if true, set the ventilation rates (per-person and per-area)
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_internal_loads(space_type, set_people: false, set_lights: true, set_electric_equipment: false, set_gas_equipment: false, set_ventilation: false)
    # Skip plenums
    # Check if the space type name
    # contains the word plenum.
    if space_type.name.get.to_s.downcase.include?('plenum')
      return false
    end

    if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')
      return false
    end

    # Save information about lighting exceptions before removing extra lights objects
    # First get list of all lights objects that are exempt
    regulated_lights = []
    unregulated_lights = []
    user_lights = @standards_data.key?('userdata_lights') ? @standards_data['userdata_lights'] : nil
    if user_lights && user_lights.length >= 1
      user_lights.each do |user_data|
        lights_name = user_data['name']
        lights_obj = space_type.model.getLightsByName(lights_name).get

        if user_data['has_retail_display_exception'].to_s.downcase == 'yes' || user_data['has_unregulated_exception'].to_s.downcase == 'yes'
          # If either exception is applicable
          # Put this one on the unregulated list
          unregulated_lights.push(lights_name)
        end
      end
    end

    # Get all lights objects that are not exempt
    space_type.lights.sort.each do |lights_obj|
      lights_name = lights_obj.name.get
      if !unregulated_lights.include? lights_name
        regulated_lights << lights_obj
      end
    end

    # Pre-process the light instances in the space type
    # Remove all regulated instances but leave one in the space type
    if regulated_lights.empty?
      definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
      definition.setName("#{space_type.name} Lights Definition")
      instance = OpenStudio::Model::Lights.new(definition)
      lights_name = "#{space_type.name} Lights"
      instance.setName(lights_name)
      instance.setSpaceType(space_type)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no lights, one has been created.")
      space_type.additionalProperties.setFeature('regulated_lights_name', lights_name)
      regulated_lights << instance
    else
      regulated_lights.each_with_index do |inst, i|
        if i.zero?
          # Save the name of the first instance to use as the baseline lights object
          lights_name = inst.name.get
          space_type.additionalProperties.setFeature('regulated_lights_name', lights_name)
          next
        end

        # Remove all other lights objects that have not been identified as unregulated
        if i == 1
          ref_name = space_type.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
          OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Multiple lights objects found in user model for #{space_type.name}. Baseline schedule will be determined from #{ref_name}")
        end

        OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Removed lighting object #{inst.name} from #{space_type.name}. ")
        inst.remove
      end
    end

    # Get userdata from userdata_space and userdata_spacetype
    user_spaces = @standards_data.key?('userdata_space') ? @standards_data['userdata_space'] : nil
    user_spacetypes = @standards_data.key?('userdata_spacetype') ? @standards_data['userdata_spacetype'] : nil
    if user_spaces && user_spaces.length >= 1 && has_user_lpd_values(user_spaces)
      # if space type has user data & data has lighting data for user space
      # call this function to enforce space-space_type one on one relationship
      new_space_array = space_to_space_type_apply_lighting(user_spaces, user_spacetypes, space_type)
      # process power equipment with new spaces.
      space_to_space_type_apply_power_equipment(user_spacetypes, user_spaces, new_space_array)
      # remove the old space
      space_type.remove
    else
      if user_spacetypes && user_spacetypes.length >= 1 && has_user_lpd_values(user_spacetypes)
        # if space type has user data & data has lighting data for user space type
        user_space_type_index = user_spacetypes.index { |user_spacetype| user_spacetype['name'] == space_type.name.get }
        if user_space_type_index.nil?
          # cannot find a matched user_spacetype to space_type, use space_type to set LPD
          set_lpd_on_space_type(space_type, user_spaces, user_spacetypes)
          space_type_apply_power_equipment(space_type)
        else
          user_space_type = user_spacetypes[user_space_type_index]
          # If multiple LPD value exist - then enforce space-space_type one on one relationship
          if has_multi_lpd_values_user_data(user_space_type, space_type)
            new_space_array = space_to_space_type_apply_lighting(user_spaces, user_spacetypes, space_type)
            space_to_space_type_apply_power_equipment(user_spacetypes, user_spaces, new_space_array)
            space_type.remove
          else
            # Process the user_space type data - at this point, we are sure there is no lighting per length
            # So all the LPD should be identical by space
            # Loop because we need to assign the occupancy control credit to each space for
            # Schedule processing.
            space_type_lighting_per_area = 0.0
            space_type.spaces.each do |space|
              space_lighting_per_area = calculate_lpd_from_userdata(user_space_type, space)
              space_type_lighting_per_area = space_lighting_per_area
            end
            if space_type.hasAdditionalProperties && space_type.additionalProperties.hasFeature('regulated_lights_name')
              lights_name = space_type.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
              lights_obj = space_type.model.getLightsByName(lights_name).get
              lights_obj.lightsDefinition.setWattsperSpaceFloorArea(OpenStudio.convert(space_type_lighting_per_area.to_f, 'W/ft^2', 'W/m^2').get)
            end
          end
          # process power equipment
          space_type_apply_power_equipment(space_type)
        end
      else
        # no user data, set space_type LPD
        set_lpd_on_space_type(space_type, user_spaces, user_spacetypes)
        # process power equipment
        space_type_apply_power_equipment(space_type)
      end
    end
  end

  # A function to calculate electric value for an electric equipment.
  # The function will check whether this electric equipment is motor, refrigeration, elevator or generic electric equipment
  # and decide actions based on the equipment types
  #
  # @param user_equip_data [Hash] user equipment data
  # @param power_equipment [OpenStudio::Model::ElectricEquipment] equipment
  # @param power_schedule_hash [Hash] equipment operation schedule hash
  # @param space_type [OpenStudio::Model:SpaceType] space type
  # @param user_space_data [Hash] user space data
  # @return [Boolean] returns true if successful, false if not
  def calculate_electric_value_by_userdata(user_equip_data, power_equipment, power_schedule_hash, space_type, user_space_data = nil)
    # Check if the plug load represents a motor (check if motorhorsepower exist), if so, record the motor HP and efficiency.
    if !user_equip_data['motor_horsepower'].nil?
      # Pre-processing will ensure these three user data are added correctly (float, float, boolean)
      # @todo move this part to user data processing.
      power_equipment.additionalProperties.setFeature('motor_horsepower', user_equip_data['motor_horsepower'].to_f)
      power_equipment.additionalProperties.setFeature('motor_efficiency', user_equip_data['motor_efficiency'].to_f)
      power_equipment.additionalProperties.setFeature('motor_is_exempt', user_equip_data['motor_is_exempt'])
    elsif !(user_equip_data['fraction_of_controlled_receptacles'].nil? && user_equip_data['receptacle_power_savings'].nil?)
      # If not a motor - update.
      # Update the electric equipment occupancy credit (if it has)
      update_power_equipment_credits(power_equipment, user_equip_data, power_schedule_hash, space_type, user_space_data)
    else
      # The electric equipment is either an elevator or refrigeration
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ElectricEquipment', "#{power_equipment.name} is an elevator or refrigeration according to the user data provided. Skip receptacle power credit.")
      return false
    end
    return true
  end

  # Apply power equipment to space type
  # This is utility function for applying user data to space type
  #
  # @param space_type [OpenStudio::Model:SpaceType]
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_power_equipment(space_type)
    # save schedules in a hash in case it is needed for new electric equipment
    power_schedule_hash = {}
    # @todo move this part to user data processing
    user_electric_equipment_data = @standards_data.key?('userdata_electric_equipment') ? @standards_data['userdata_electric_equipment'] : nil
    user_gas_equipment_data = @standards_data.key?('userdata_gas_equipment') ? @standards_data['userdata_gas_equipment'] : nil
    if user_electric_equipment_data && user_electric_equipment_data.length >= 1
      space_type_electric_equipments = space_type.electricEquipment
      space_type_electric_equipments.each do |sp_electric_equipment|
        electric_equipment_name = sp_electric_equipment.name.get
        select_user_electric_equipment_array = user_electric_equipment_data.select { |elec| elec['name'].casecmp(electric_equipment_name) == 0 }
        unless select_user_electric_equipment_array.empty?
          select_user_electric_equipment = select_user_electric_equipment_array[0]
          calculate_electric_value_by_userdata(select_user_electric_equipment, sp_electric_equipment, power_schedule_hash, space_type, nil)
        end
      end
    elsif user_gas_equipment_data && user_gas_equipment_data.length >= 1
      space_type_gas_equipments = space_type.gasEquipment
      space_type_gas_equipments.each do |sp_gas_equipment|
        gas_equipment_name = sp_gas_equipment.name.get
        select_user_gas_equipment_array = user_gas_equipment_data.select { |gas| gas['name'].casecmp(gas_equipment_name) == 0 }
        unless select_user_gas_equipment_array.empty?
          select_user_gas_equipment = select_user_gas_equipment_array[0]
          # Update the gas equipment occupancy credit (if it has)
          update_power_equipment_credits(sp_gas_equipment, select_user_gas_equipment, power_schedule_hash, space_type.model, nil)
        end
      end
    end
    return true
  end

  # Apply space to space type power equipment adjustment.
  # NOTE! this function shall only be used if the space to space type is one to one relationship.
  # This function can process both electric equipment and gas equipment
  # and this function will process user data from electric equipment and gas equipment user data
  #
  # @param user_spacetypes [Hash] spacetype user data
  # @param user_spaces [Hash] space user data
  # @param space_array [Array OpenStudio::Model:Space] list of spaces need for process
  # @return [Boolean] returns true if successful, false if not
  def space_to_space_type_apply_power_equipment(user_spacetypes, user_spaces, space_array)
    # Step 1: Set electric / gas equipment
    # save schedules in a hash in case it is needed for new electric equipment
    power_schedule_hash = {}
    # check if electric equipment data is available.
    user_electric_equipment_data = @standards_data.key?('userdata_electric_equipment') ? @standards_data['userdata_electric_equipment'] : nil
    user_gas_equipment_data = @standards_data.key?('userdata_gas_equipment') ? @standards_data['userdata_gas_equipment'] : nil
    if user_electric_equipment_data && user_electric_equipment_data.length >= 1
      space_array.each do |space|
        # Each space has a unique space type
        space_type = space.spaceType.get
        user_spacestypes_index = user_spacetypes.index { |user_spacetype| /#{user_spacetype['name']}/i =~ space_type.name.get }
        user_space_index = user_spaces.index { |user_space| user_space['name'] == space.name.get }
        # Initialize with standard space_type
        user_space_data = space_type.name.get
        unless user_spacestypes_index.nil?
          # override with user space type if specified
          user_space_data = user_spacetypes[user_spacestypes_index]
        end
        unless user_space_index.nil?
          # override with user space if specified
          user_space_data = user_spaces[user_space_index]
        end
        space_type_electric_equipments = space_type.electricEquipment
        space_type_electric_equipments.each do |sp_electric_equipment|
          electric_equipment_name = sp_electric_equipment.name.get
          select_user_electric_equipment_array = user_electric_equipment_data.select { |elec| /#{elec['name']}/i =~ electric_equipment_name }
          unless select_user_electric_equipment_array.empty?
            select_user_electric_equipment = select_user_electric_equipment_array[0]
            calculate_electric_value_by_userdata(select_user_electric_equipment, sp_electric_equipment, power_schedule_hash, space_type, user_space_data)
          end
        end
      end
    elsif user_gas_equipment_data && user_gas_equipment_data.length >= 1
      space_array.each do |space|
        space_type = space.spaceType.get
        user_spacestypes_index = user_spacetypes.index { |user_spacetype| user_spacetype['name'] == space_type.name.get }
        user_space_index = user_spaces.index { |user_space| user_space['name'] == space.name.get }
        user_space_data = space_type.name.get
        unless user_spacestypes_index.nil?
          user_space_data = user_spacetypes[user_spacestypes_index]
        end
        unless user_space_index.nil?
          user_space_data = user_spaces[user_space_index]
        end
        space_type_gas_equipments = space_type.gasEquipment
        space_type_gas_equipments.each do |sp_gas_equipment|
          gas_equipment_name = sp_gas_equipment.name.get
          select_user_gas_equipment_array = user_gas_equipment_data.select { |gas| gas['name'].casecmp(gas_equipment_name) == 0 }
          unless select_user_gas_equipment_array.empty?
            select_user_gas_equipment = select_user_gas_equipment_array[0]
            # Update the gas equipment occupancy credit (if it has)
            update_power_equipment_credits(sp_gas_equipment, select_user_gas_equipment, power_schedule_hash, space_type.model, user_space_data)
          end
        end
      end
    end
    return true
  end

  # Function update a power equipment schedule based on user data.
  # This function works with both electric equipment and gas equipment and applies the ruleset on power equipment
  # The function process user data including the fraction of controlled receptacles and receptacle power savings.
  #
  # @param power_equipment [OpenStudio::Model::ElectricEquipment] or [OpenStudio::Model:GasEquipment]
  # @param user_power_equipment [Hash] user data for the power equipment
  # @param schedule_hash [Hash] power equipment operation schedules in a hash
  # @param space_type [OpenStudio::Model:SpaceType] space type
  # @param user_data [Hash] user space data
  # @return [Boolean] returns true it adjusted, false if not
  def update_power_equipment_credits(power_equipment, user_power_equipment, schedule_hash, space_type, user_data = nil)
    exception_list = ['office - enclosed <= 250 sf', 'conference/meeting/multipurpose', 'copy/print',
                      'lounge/breakroom - all other', 'lounge/breakroom - healthcare facility', 'classroom/lecture/training - all other',
                      'classroom/lecture/training - preschool to 12th', 'office - open']

    receptacle_power_credits = 0.0
    # Check fraction_of_controlled_receptacles or receptacle_power_savings exist
    if user_power_equipment.key?('fraction_of_controlled_receptacles') && !user_power_equipment['fraction_of_controlled_receptacles'].nil?
      rc = user_power_equipment['fraction_of_controlled_receptacles'].to_f
      # receptacle power credits = percent of all controlled receptacles * 10%
      receptacle_power_credits = rc * 0.1
    elsif user_power_equipment.key?('receptacle_power_savings') && !user_power_equipment['receptacle_power_savings'].nil?
      receptacle_power_credits = user_power_equipment['receptacle_power_savings'].to_f
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ElectricEquipment', "#{power_equipment.name.get} has a user specified receptacle power saving credit #{receptacle_power_credits}. The modeler needs to make sure the credit is approved by a rating authority per Table G3.1 section 12.")
    end

    # process user space data
    if user_data.is_a?(Hash)
      if user_data.key?('num_std_ltg_types') && user_data['num_std_ltg_types'].to_f > 0
        adjusted_receptacle_power_credits = 0.0
        num_std_space_types = user_data['num_std_ltg_types'].to_i
        std_space_index = 0 # loop index
        # Loop through standard lighting type in a space
        while std_space_index < num_std_space_types
          std_space_index += 1
          # Retrieve data from user_data
          type_key = format('std_ltg_type%02d', std_space_index)
          frac_key = format('std_ltg_type_frac%02d', std_space_index)
          sub_space_type = user_data[type_key]
          next if exception_list.include?(sub_space_type)

          adjusted_receptacle_power_credits += user_data[frac_key].to_f * receptacle_power_credits
          # Adjust while loop condition factors
        end
        receptacle_power_credits = adjusted_receptacle_power_credits
      end
    elsif user_data.is_a?(String)
      if exception_list.include?(space_type.standardsSpaceType.get)
        # the space type is in the exception list, no credit to the space type
        receptacle_power_credits = 0.0
      end
    end

    # return false if no receptacle power credits
    unless receptacle_power_credits > 0.0
      return false
    end

    # Step 2: check if need to adjust the electric equipment schedule. - apply credit if needed.
    # get current schedule
    power_schedule = power_equipment.schedule.get
    power_schedule_name = power_schedule.name.get
    new_power_schedule_name = format("#{power_schedule_name}_%.4f", receptacle_power_credits)
    if schedule_hash.key?(new_power_schedule_name)
      # In this case, there is a schedule created, can retrieve the schedule object and reset in this space type.
      schedule_rule = schedule_hash[new_power_schedule_name]
      power_equipment.setSchedule(schedule_rule)
    else
      # In this case, create a new schedule
      # 1. Clone the existing schedule
      new_rule_set_schedule = deep_copy_schedule(new_power_schedule_name, power_schedule, receptacle_power_credits, space_type.model)
      if power_equipment.setSchedule(new_rule_set_schedule)
        schedule_hash[new_power_schedule_name] = new_rule_set_schedule
      end
    end
    return true
  end

  # Function to test LPD on default space type. The function assigns lighting power density to an light object.
  # @param space_type [OpenStudio::Model::SpaceType]
  # @param user_spaces [Hash]
  # @param user_spacetypes [Hash]
  # @return [Boolean] returns true if successful, false if not
  def set_lpd_on_space_type(space_type, user_spaces, user_spacetypes)
    if has_multi_lpd_values_space_type(space_type)
      # If multiple LPD value exist - then enforce space-space_type one on one relationship
      space_to_space_type_apply_lighting(user_spaces, user_spacetypes, space_type)
    else
      # use default - loop through space to assign occupancy credit to each space.
      space_type_lighting_per_area = 0.0
      space_type.spaces.each do |space|
        space_lighting_per_area = calculate_lpd_by_space(space_type, space)
        space_type_lighting_per_area = space_lighting_per_area
      end
      if space_type.hasAdditionalProperties && space_type.additionalProperties.hasFeature('regulated_lights_name')
        lights_name = space_type.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
        lights_obj = space_type.model.getLightsByName(lights_name).get
        OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Setting lighting object #{lights_obj.name.get} lighting per area to #{space_type_lighting_per_area} W/ft^2")
        lights_obj.lightsDefinition.setWattsperSpaceFloorArea(OpenStudio.convert(space_type_lighting_per_area.to_f, 'W/ft^2', 'W/m^2').get)
      end
    end
    return true
  end

  # Function that applies user LPD to each space by duplicating space types
  # This function is used when there are user space data available or
  # the spaces under space type has lighting per length value which may cause multiple
  # lighting power densities under one space_type.
  # @param user_spaces [Hash] hash data contained in the user space
  # @param user_spacetypes [Hash] hash data contained in the user spacetypes
  # @param space_type [OpenStudio::Model::SpaceType] object
  # @return [ArrayOpenStudio::Model::Space] List of Spaces
  def space_to_space_type_apply_lighting(user_spaces, user_spacetypes, space_type)
    space_lighting_per_area_hash = {}
    # first priority - user_space data
    if user_spaces && user_spaces.length >= 1
      space_type.spaces.each do |space|
        user_space_index = user_spaces.index { |user_space| user_space['name'] == space.name.get }
        unless user_space_index.nil?
          user_space_data = user_spaces[user_space_index]
          if user_space_data.key?('num_std_ltg_types') && user_space_data['num_std_ltg_types'].to_f > 0
            space_lighting_per_area = calculate_lpd_from_userdata(user_space_data, space)
            space_lighting_per_area_hash[space.name.get] = space_lighting_per_area
          end
        end
      end
    end
    # second priority - user_spacetype
    if user_spacetypes && user_spacetypes.length >= 1
      # if space type has user data
      user_space_type_index = user_spacetypes.index { |user_spacetype| user_spacetype['name'] == space_type.name.get }
      unless user_space_type_index.nil?
        user_space_type_data = user_spacetypes[user_space_type_index]
        if user_space_type_data.key?('num_std_ltg_types') && user_space_type_data['num_std_ltg_types'].to_f > 0
          space_type.spaces.each do |space|
            # unless the space is in the hash, we will add lighting per area to the space
            space_name = space.name.get
            unless space_lighting_per_area_hash.key?(space_name)
              space_lighting_per_area = calculate_lpd_from_userdata(user_space_type_data, space)
              space_lighting_per_area_hash[space_name] = space_lighting_per_area
            end
          end
        end
      end
    end
    # Third priority
    # set space type to every space in the space_type, third priority
    # will also be assigned from the default space type
    space_type.spaces.each do |space|
      space_name = space.name.get
      unless space_lighting_per_area_hash.key?(space_name)
        space_lighting_per_area = calculate_lpd_by_space(space_type, space)
        space_lighting_per_area_hash[space_name] = space_lighting_per_area
      end
    end
    # All space is explored.
    # Now rewrite the space type in each space - might need to change the logic
    space_array = []
    space_type.spaces.each do |space|
      space_name = space.name.get
      new_space_type = space_type.clone.to_SpaceType.get
      space.setSpaceType(new_space_type)
      lighting_per_area = space_lighting_per_area_hash[space_name]
      new_space_type.lights.each do |inst|
        lights_name = inst.name.get
        new_space_type.additionalProperties.setFeature('regulated_lights_name', lights_name)
        definition = inst.lightsDefinition
        unless lighting_per_area.zero?
          new_definition = definition.clone.to_LightsDefinition.get
          new_definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area.to_f, 'W/ft^2', 'W/m^2').get)
          inst.setLightsDefinition(new_definition)
          OpenStudio.logFree(OpenStudio::Info, 'log.prm', "#{space_type.name} set LPD to #{lighting_per_area} W/ft^2.")
        end
      end
      space_array.push(space)
    end
    return space_array
  end

  # Modify the lighting schedules for Appendix G PRM for 2016 and later
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def space_type_light_sch_change(model)
    # set schedule for lighting
    schedule_hash = {}
    model.getSpaces.each do |space|
      space_type = prm_get_optional_handler(space, @sizing_run_dir, 'spaceType')
      if space_type.hasAdditionalProperties && space_type.additionalProperties.hasFeature('regulated_lights_name')
        lights_name = space_type.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
        ltg_option = space_type.model.getLightsByName(lights_name)
        if ltg_option.is_initialized
          ltg = ltg_option.get
        else
          # raise exception if we cannot find the lights in the model
          prm_raise(false, @sizing_run_dir, "Cannot find the lights #{lights_name} in the model")
        end
        # this will raise exception if the ltg has no schedule assigned.
        if ltg.schedule.is_initialized
          ltg_schedule = ltg.schedule.get
        else
          # case such as Attic may have light object but no light schedule assigned
          # Eplus use default 0 so in here we raise Error but continue processing.
          ltg_schedule = nil
          OpenStudio.logFree(OpenStudio::Warn, 'prm.log',
                             "schedule is not available in component #{ltg.name.get}. Skip processing")
        end

        if ltg_schedule
          ltg_schedule_name = ltg_schedule.name.get
          occupancy_sensor_credit = get_additional_property_as_double(space, 'occ_control_credit', 0.0)
          if schedule_hash.key?(ltg_schedule_name)
            # In this case, there is a schedule created, can retrieve the schedule object and reset in this space type
            schedule_rule = schedule_hash[ltg_schedule_name]
            ltg.setSchedule(schedule_rule)
          else
            # In this case, create a new schedule
            # 1. Clone the existing schedule
            new_ltg_schedule_name = format("#{ltg_schedule_name}_%.4f", occupancy_sensor_credit)
            new_rule_set_schedule = deep_copy_schedule(new_ltg_schedule_name, ltg_schedule, occupancy_sensor_credit, model)
            if ltg.setSchedule(new_rule_set_schedule)
              schedule_hash[new_ltg_schedule_name] = new_rule_set_schedule
            end
          end
        end
      end
    end
  end

  def deep_copy_schedule(new_schedule_name, schedule, adjustment_factor, model)
    OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Creating a new lighting schedule that applies occupancy sensor adjustment factor: #{adjustment_factor} based on #{schedule.name.get} schedule")
    sch = OpenstudioStandards::Schedules
    multiplier = 1.0 / (1.0 - adjustment_factor.to_f)
    case schedule.iddObjectType.valueName.to_s
    when 'OS_Schedule_Constant'
      schedule_constant = schedule.to_ScheduleConstant.get
      schedule_value = schedule_constant.value
      return sch.create_constant_schedule_ruleset(model, schedule_value * multiplier, name: new_schedule_name)
    when 'OS_Schedule_Ruleset'
      new_schedule = schedule.clone(model)
      new_schedule.setName(new_schedule_name)
      schedule_ruleset = new_schedule.to_ScheduleRuleset.get
      return sch.schedule_ruleset_simple_value_adjust(schedule_ruleset, multiplier, modification_type = 'Multiplier')
    when 'OS_Schedule_Compact'
      prm_raise(false, @sizing_run_dir, 'PRM does not support using Compact schedule for lighting schedules. Please update it to ruleset based or constant schedules.')
    else
      prm_raise(false, @sizing_run_dir, 'PRM only supports ruleset based or constant schedules for lighting schedules')
    end
  end

  # calculate the lighting power density per area based on space type
  # The function will calculate the LPD based on the space type (STRING)
  # It considers lighting per area, lighting per length as well as occupancy factors in the database.
  # @param space_type [OpenStudio::Model::SpaceType]
  # @param space [OpenStudio::Model::Space]
  # @return [Double] lighting power density in the space
  def calculate_lpd_by_space(space_type, space)
    # get interior lighting data
    space_type_properties = interior_lighting_get_prm_data(space_type)
    OpenStudio.logFree(OpenStudio::Info, 'prm.log', "The lighting properties for space: #{space.name.get} is based on lighting_space_type: #{space_type_properties['lpd_space_type']}, primary_space_type: #{space_type_properties['primary_space_type']}, secondary_space_type: #{space_type_properties['secondary_space_type']}.")
    space_lighting_per_area = 0.0
    # Assign data
    lights_have_info = false
    lighting_per_area = space_type_properties['w/ft^2'].to_f
    lighting_per_length = space_type_properties['w/ft'].to_f
    manon_or_partauto = space_type_properties['manon_or_partauto'].to_i
    lights_have_info = true unless lighting_per_area.zero? && lighting_per_length.zero?
    occ_control_reduction_factor = 0.0

    if lights_have_info
      # Space height
      space_volume = space.volume
      space_area = space.floorArea
      space_height = OpenStudio.convert(space_volume / space_area, 'm', 'ft').get
      # calculate the new lpd values
      space_lighting_per_area = ((lighting_per_length * space_height) / space_area) + lighting_per_area

      # Adjust the occupancy control sensor reduction factor from dataset
      if manon_or_partauto == 1
        occ_control_reduction_factor = space_type_properties['occup_sensor_savings'].to_f
      else
        occ_control_reduction_factor = space_type_properties['occup_sensor_auto_on_svgs'].to_f
      end
    end
    # add calculated occupancy control credit for later ltg schedule adjustment
    space.additionalProperties.setFeature('occ_control_credit', occ_control_reduction_factor)
    return space_lighting_per_area
  end

  # Function checks whether the user data contains lighting data
  # @param user_space_data [Hash] space data extracted from user csv.
  # @return [Boolean] True if there are user lpd values, False otherwise.
  def has_user_lpd_values(user_space_data)
    user_space_data.each do |user_data|
      if user_data.key?('num_std_ltg_types') && user_data['num_std_ltg_types'].to_f > 0
        return true
      end
    end
    return false
  end

  # Function checks whether there are multi lpd values in the space type
  # multi-lpd value means there are multiple spaces and the lighting_per_length > 0
  # @param space_type [OpenStudio::Model::SpaceType]
  # @return [Boolean] True if there is lighting power defined by w/ft, False otherwise.
  def has_multi_lpd_values_space_type(space_type)
    space_type_properties = interior_lighting_get_prm_data(space_type)
    lighting_per_length = space_type_properties['w/ft'].to_f

    return space_type.spaces.size > 1 && lighting_per_length > 0
  end

  # Function checks whether there are multi lpd values in the space type from user's data
  # The sum of each space fraction in the user_data is assumed to be 1.0
  # multi-lpd value means lighting per area > 0 and lighting_per_length > 0
  # @param user_data [Hash] user data from the user csv
  # @param space_type [OpenStudio::Model::SpaceType]
  # @return [Boolean]
  def has_multi_lpd_values_user_data(user_data, space_type)
    num_std_ltg_types = user_data['num_std_ltg_types'].to_i
    std_ltg_index = 0 # loop index
    # Loop through standard lighting type in a space
    sum_lighting_per_area = 0
    sum_lighting_per_length = 0
    while std_ltg_index < num_std_ltg_types
      # Retrieve data from user_data
      type_key = format('std_ltg_type%02d', (std_ltg_index + 1))
      sub_space_type = user_data[type_key]
      # Adjust while loop condition factors
      std_ltg_index += 1
      # get interior lighting data
      sub_space_type_properties = interior_lighting_get_prm_data(sub_space_type)
      # Assign data
      lighting_per_length = sub_space_type_properties['w/ft'].to_f
      sum_lighting_per_length += lighting_per_length
    end
    return space_type.spaces.size > 1 && sum_lighting_per_length > 0
  end

  # Calculate the lighting power density per area based on user data (space_based)
  # The function will calculate the LPD based on the space type (STRING)
  # It considers lighting per area, lighting per length as well as occupancy factors in the database.
  # The sum of each space fraction in the user_data is assumed to be 1.0
  # @param user_data [Hash] user data from the user csv
  # @param space [OpenStudio::Model::Space]
  # @return [Double] space lighting per area in W per m2
  def calculate_lpd_from_userdata(user_data, space)
    num_std_ltg_types = user_data['num_std_ltg_types'].to_i
    space_lighting_per_area = 0.0
    occupancy_control_credit_sum = 0.0
    std_ltg_index = 0 # loop index
    # Loop through standard lighting type in a space
    while std_ltg_index < num_std_ltg_types
      # Retrieve data from user_data
      type_key = format('std_ltg_type%02d', (std_ltg_index + 1))
      frac_key = format('std_ltg_type_frac%02d', (std_ltg_index + 1))
      sub_space_type = user_data[type_key]
      sub_space_type_frac = user_data[frac_key].to_f
      # Adjust while loop condition factors
      std_ltg_index += 1
      # get interior lighting data
      sub_space_type_properties = interior_lighting_get_prm_data(sub_space_type)
      # Assign data
      lights_have_info = false
      lighting_per_area = sub_space_type_properties['w/ft^2'].to_f
      lighting_per_length = sub_space_type_properties['w/ft'].to_f
      lights_have_info = true unless lighting_per_area.zero? && lighting_per_length.zero?
      manon_or_partauto = sub_space_type_properties['manon_or_partauto'].to_i

      if lights_have_info
        # Space height
        space_volume = space.volume
        space_area = space.floorArea
        space_height = OpenStudio.convert(space_volume / space_area, 'm', 'ft').get
        # calculate and add new lpd values
        user_space_type_lighting_per_area = (((lighting_per_length * space_height) / space_area) + lighting_per_area) * sub_space_type_frac
        space_lighting_per_area += user_space_type_lighting_per_area

        # Adjust the occupancy control sensor reduction factor from dataset
        occ_control_reduction_factor = 0.0
        if manon_or_partauto == 1
          occ_control_reduction_factor = sub_space_type_properties['occup_sensor_savings'].to_f
        else
          occ_control_reduction_factor = sub_space_type_properties['occup_sensor_auto_on_svgs'].to_f
        end
        # Now calculate the occupancy control credit factor (weighted by frac_lpd)
        occupancy_control_credit_sum += occ_control_reduction_factor * user_space_type_lighting_per_area
      end
    end
    # add calculated occupancy control credit for later ltg schedule adjustment
    # If space_lighting_per_area = 0, it means there is no lights_have_info, and subsequently, the occupancy_control_credit_sum should be 0
    space.additionalProperties.setFeature('occ_control_credit', space_lighting_per_area > 0 ? occupancy_control_credit_sum / space_lighting_per_area : occupancy_control_credit_sum)
    return space_lighting_per_area
  end
end
