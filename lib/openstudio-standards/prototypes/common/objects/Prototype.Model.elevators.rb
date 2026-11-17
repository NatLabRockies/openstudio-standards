class Standard
  # Add an elevator the the specified space
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param space [OpenStudio::Model::Space] the space that contains the elevators
  # @param number_of_elevators [Integer] the number of elevators
  # @param elevator_type [String] valid choices are Traction, Hydraulic
  # @param elevator_schedule [String] the name of the elevator schedule
  # @param elevator_fan_schedule [String] the name of the elevator fan schedule
  # @param elevator_lights_schedule [String] the name of the elevator lights schedule
  # @param building_type [String] the building type
  # @return [OpenStudio::Model::ElectricEquipment] the resulting elevator
  def model_add_elevator(model,
                         space,
                         number_of_elevators,
                         elevator_type,
                         elevator_schedule,
                         elevator_fan_schedule,
                         elevator_lights_schedule,
                         building_type = nil)
    # Lift motor assumptions
    lift_pwr_w = model_elevator_lift_power(model, elevator_type, building_type)

    # Size assumptions
    length_ft = 6.66
    width_ft = 4.25
    height_ft = 8.0
    area_ft2 = length_ft * width_ft
    volume_ft3 = area_ft2 * height_ft

    # Ventilation assumptions
    vent_rate_acm = 1 # air changes per minute
    vent_rate_cfm = volume_ft3 / vent_rate_acm
    vent_pwr_w = model_elevator_fan_pwr(model, vent_rate_cfm)

    # Heating fraction radiant assumptions
    elec_equip_frac_radiant = 0.5

    # Lighting assumptions
    design_ltg_lm_per_ft2 = 30
    light_loss_factor = 0.75
    pct_incandescent = model_elevator_lighting_pct_incandescent(model)
    pct_led = 1.0 - pct_incandescent

    incandescent_efficacy_lm_per_w = 10.0
    led_efficacy_lm_per_w = 35.0
    target_ltg_lm_per_ft2 = design_ltg_lm_per_ft2 / light_loss_factor # 40
    target_ltg_lm = target_ltg_lm_per_ft2 * area_ft2 # 1132.2
    lm_incandescent = target_ltg_lm * pct_incandescent # 792.54
    lm_led = target_ltg_lm * pct_led # 339.66
    w_incandescent = lm_incandescent / incandescent_efficacy_lm_per_w # 79.254
    w_led = lm_led / led_efficacy_lm_per_w # 9.7
    lighting_pwr_w = w_incandescent + w_led

    # Elevator lift motor
    elevator_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elevator_definition.setName('Elevator Lift Motor')
    elevator_definition.setDesignLevel(lift_pwr_w)
    elevator_definition.setFractionRadiant(elec_equip_frac_radiant)

    elevator_equipment = OpenStudio::Model::ElectricEquipment.new(elevator_definition)
    elevator_equipment.setName("#{number_of_elevators.round} Elevator Lift Motors")
    elevator_equipment.setEndUseSubcategory('Elevators')
    elevator_sch = model_add_schedule(model, elevator_schedule)
    elevator_equipment.setSchedule(elevator_sch)
    elevator_equipment.setSpace(space)
    elevator_equipment.setMultiplier(number_of_elevators)

    # Elevator fan
    elevator_fan_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elevator_fan_definition.setName('Elevator Fan')
    elevator_fan_definition.setDesignLevel(vent_pwr_w)
    elevator_fan_definition.setFractionRadiant(elec_equip_frac_radiant)

    elevator_fan_equipment = OpenStudio::Model::ElectricEquipment.new(elevator_fan_definition)
    elevator_fan_equipment.setName("#{number_of_elevators.round} Elevator Fans")
    elevator_fan_equipment.setEndUseSubcategory('Elevators')
    elevator_fan_sch = model_add_schedule(model, elevator_fan_schedule)
    elevator_fan_equipment.setSchedule(elevator_fan_sch)
    elevator_fan_equipment.setSpace(space)
    elevator_fan_equipment.setMultiplier(number_of_elevators)

    # Elevator lights
    elevator_lights_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
    elevator_lights_definition.setName('Elevator Lights')
    elevator_lights_definition.setDesignLevel(lighting_pwr_w)
    elevator_lights_definition.setFractionRadiant(elec_equip_frac_radiant)

    elevator_lights_equipment = OpenStudio::Model::ElectricEquipment.new(elevator_lights_definition)
    elevator_lights_equipment.setName("#{number_of_elevators.round} Elevator Lights")
    elevator_lights_equipment.setEndUseSubcategory('Elevators')
    elevator_lights_sch = model_add_schedule(model, elevator_lights_schedule)
    elevator_lights_equipment.setSchedule(elevator_lights_sch)
    elevator_lights_equipment.setSpace(space)
    elevator_lights_equipment.setMultiplier(number_of_elevators)

    return elevator_equipment
  end

  # Determines the power required by an individual elevator of a given type.
  # Defaults to the values used by the DOE prototype buildings.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param elevator_type [String] valid choices are Traction, Hydraulic
  # @param building_type [String] the building type
  # @return [Double] lift power in watts
  def model_elevator_lift_power(model, elevator_type, building_type)
    lift_pwr_w = 0
    if elevator_type == 'Traction'
      lift_pwr_w += 20_370.0
    elsif elevator_type == 'Hydraulic'
      lift_pwr_w += 16_055.0
    else
      lift_pwr_w += 16_055.0
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Elevator type '#{elevator_type}', not recognized, will assume Hydraulic elevator, #{lift_pwr_w} W.")
    end

    return lift_pwr_w
  end

  # Determines the percentage of the elevator cab lighting that is incandescent.
  # The remainder is assumed to be LED.
  # Defaults to 70% incandescent, representing older elevators.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Double] incandescent lighting percentage
  def model_elevator_lighting_pct_incandescent(model)
    pct_incandescent = 0.7
    return pct_incandescent
  end

  # Determines the power of the elevator ventilation fan.
  # Defaults to 90.1-2010, which had no requirement for ventilation fan efficiency.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param vent_rate_cfm [Double] the ventilation rate in ft^3/min
  # @return [Double] the ventilation fan power in watts
  def model_elevator_fan_pwr(model, vent_rate_cfm)
    vent_pwr_per_flow_w_per_cfm = 0.33
    vent_pwr_w = vent_pwr_per_flow_w_per_cfm * vent_rate_cfm

    return vent_pwr_w
  end

  # Add elevators to the model based on the building size, number of stories, and building type.
  # Logic was derived from the DOE prototype buildings.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [OpenStudio::Model::ElectricEquipment] the resulting elevator
  def model_add_elevators(model)
    # determine effective number of stories
    effective_num_stories = model_effective_num_stories(model)

    # determine elevator type
    # todo add logic here or upstream to have some multi-story buildings without elevators (e.g. small multi-family and small hotels)
    if effective_num_stories[:below_grade] + effective_num_stories[:above_grade] < 2
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', 'The building only has 1 story, no elevators will be added.')
      return nil # don't add elevators
    elsif effective_num_stories[:below_grade] + effective_num_stories[:above_grade] < 6
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', 'The building has fewer than 6 effective stories; assuming Hydraulic elevators.')
      elevator_type = 'Hydraulic'
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', 'The building has 6 or more effective stories; assuming Traction elevators.')
      elevator_type = 'Traction'
    end

    # determine space to put elevator load in
    # largest bottom story (including basement) space that has multiplier of 1
    bottom_spaces = {}
    bottom_story = effective_num_stories[:story_hash].keys.first
    bottom_story.spaces.each do |space|
      next if space.multiplier > 1

      bottom_spaces[space] = space.floorArea
    end
    target_space = bottom_spaces.key(bottom_spaces.values.max)

    building_types = []

    # determine number of elevators
    number_of_pass_elevators = 0.0
    number_of_freight_elevators = 0.0
    building_type_hash = {}

    # apply building type specific log to add to number of elevators based on Beyer (2009) rules of thumb
    space_type_hash = model_create_space_type_hash(model)
    space_type_hash.each do |space_type, hash|
      # update building_type_hash
      if building_type_hash.key?(hash[:stds_bldg_type])
        building_type_hash[hash[:stds_bldg_type]] += hash[:floor_area]
      else
        building_type_hash[hash[:stds_bldg_type]] = hash[:floor_area]
      end

      building_type = hash[:stds_bldg_type]
      building_types << building_type

      # store floor area ip
      floor_area_ip = OpenStudio.convert(hash[:floor_area], 'm^2', 'ft^2').get

      # load elevator_data
      search_criteria = {
        'building_type' => building_type,
        'template' => template
      }
      elevator_data_lookup = model_find_object(standards_data['elevators'], search_criteria)
      if elevator_data_lookup.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.elevators', "Could not find elevator data for #{building_type}, elevator counts will not account for serving this portion of the building area.")
        next
      end

      # determine number of passenger elevators
      if !elevator_data_lookup['area_per_passenger_elevator'].nil?
        pass_elevs = floor_area_ip / elevator_data_lookup['area_per_passenger_elevator'].to_f
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "For #{space_type.name}, adding #{pass_elevs.round(1)} passenger elevators at 1 per #{elevator_data_lookup['area_per_passenger_elevator']} ft^2.")
      elsif !elevator_data_lookup['units_per_passenger_elevator'].nil?
        pass_elevs = hash[:num_units] / elevator_data_lookup['units_per_passenger_elevator'].to_f
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "For #{space_type.name}, adding #{pass_elevs.round(1)} passenger elevators at 1 per #{elevator_data_lookup['units_per_passenger_elevator']} units.")
      elsif !elevator_data_lookup['beds_per_passenger_elevator'].nil?
        pass_elevs = hash[:num_beds] / elevator_data_lookup['beds_per_passenger_elevator'].to_f
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "For #{space_type.name}, adding #{pass_elevs.round(1)} passenger elevators at 1 per #{elevator_data_lookup['beds_per_passenger_elevator']} beds.")
      else
        pass_elevs = 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "Unexpected key, can't calculate number of passenger elevators from #{elevator_data_lookup.keys.first}.")
      end

      # determine number of freight elevators
      if !elevator_data_lookup['area_per_freight_elevator'].nil?
        freight_elevs = floor_area_ip / elevator_data_lookup['area_per_freight_elevator'].to_f
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "For #{space_type.name}, adding #{freight_elevs.round(1)} freight/service elevators at 1 per #{elevator_data_lookup['area_per_freight_elevator']} ft^2.")
      elsif !elevator_data_lookup['units_per_freight_elevator'].nil?
        freight_elevs = hash[:num_units] / elevator_data_lookup['units_per_freight_elevator'].to_f
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "For #{space_type.name}, adding #{freight_elevs.round(1)} freight/service elevators at 1 per #{elevator_data_lookup['units_per_freight_elevator']} units.")
      elsif !elevator_data_lookup['beds_per_freight_elevator'].nil?
        freight_elevs = hash[:num_beds] / elevator_data_lookup['beds_per_freight_elevator'].to_f
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "For #{space_type.name}, adding #{freight_elevs.round(1)} freight/service elevators at 1 per #{elevator_data_lookup['beds_per_freight_elevator']} beds.")
      else
        freight_elevs = 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "Unexpected key, can't calculate number of freight elevators from #{elevator_data_lookup.keys.first}.")
      end
      number_of_pass_elevators += pass_elevs
      number_of_freight_elevators += freight_elevs
    end

    # additional passenger elevators (applicable for DOE LargeHotel and DOE Hospital only)
    add_pass_elevs = 0.0
    building_types.uniq.each do |building_type|
      # load elevator_data
      search_criteria = { 'building_type' => building_type }
      elevator_data_lookup = model_find_object(standards_data['elevators'], search_criteria)
      if elevator_data_lookup.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.elevators', "Could not find elevator data for #{building_type}.")
        next
      end

      # determine number of additional passenger elevators
      if elevator_data_lookup['additional_passenger_elevators'].nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', 'No additional passenger elevators added to model.')
      else
        add_pass_elevs += elevator_data_lookup['additional_passenger_elevators']
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "Adding #{elevator_data_lookup['additional_passenger_elevators']} additional passenger elevators.")
      end
    end

    # adjust number of elevators (can be double but if not 0 must be at least 1.0)
    if (number_of_pass_elevators > 0.0) && (number_of_pass_elevators < 1.0)
      number_of_pass_elevators = 1.0
    end
    if (number_of_freight_elevators > 0.0) && (number_of_freight_elevators < 1.0)
      number_of_freight_elevators = 1.0
    end

    # determine total number of elevators (rounding up to nearest whole number)
    number_of_pass_elevators = number_of_pass_elevators.ceil + add_pass_elevs
    number_of_freight_elevators = number_of_freight_elevators.ceil
    number_of_elevators = number_of_pass_elevators + number_of_freight_elevators

    building_type = building_type_hash.key(building_type_hash.values.max)

    # determine blended occupancy schedule
    occ_schedule = OpenstudioStandards::Space.spaces_get_occupancy_schedule(model.getSpaces)

    # get total number of people in building
    max_occ_in_spaces = 0
    model.getSpaces.each do |space|
      # From the space type
      if space.spaceType.is_initialized
        space.spaceType.get.people.each do |people|
          num_ppl = people.getNumberOfPeople(space.floorArea)
          max_occ_in_spaces += num_ppl
        end
      end
      # From the space
      space.people.each do |people|
        num_ppl = people.getNumberOfPeople(space.floorArea)
        max_occ_in_spaces += num_ppl
      end
    end

    # make elevator schedule based on change in occupancy for each timestep
    day_schedules = []
    default_day_schedule = occ_schedule.defaultDaySchedule
    day_schedules << default_day_schedule
    occ_schedule.scheduleRules.each do |rule|
      day_schedules << rule.daySchedule
    end
    day_schedules.each do |day_schedule|
      elevator_hourly_fractions = []
      (0..23).each do |hr|
        t = OpenStudio::Time.new(0, hr, 0, 0)
        value = day_schedule.getValue(t)
        t_plus = OpenStudio::Time.new(0, hr + 1, 0, 0)
        value_plus = day_schedule.getValue(t_plus)
        change_occupancy_fraction = (value_plus - value).abs
        change_num_people = change_occupancy_fraction * max_occ_in_spaces * 1.2
        # multiplication factor or 1.2 to account for interfloor traffic

        # determine time per ride based on number of floors and elevator type
        if elevator_type == 'Hydraulic'
          time_per_ride = 8.7 + (effective_num_stories[:above_grade] * 5.6)
        elsif elevator_type == 'Traction'
          time_per_ride = 5.6 + (effective_num_stories[:above_grade] * 2.1)
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.elevators', "Elevator type #{elevator_type} not recognized.")
          return nil
        end

        # determine elevator operation fraction for each timestep
        people_per_ride = 5
        rides_per_elevator = (change_num_people / people_per_ride) / number_of_elevators
        operation_time = rides_per_elevator * time_per_ride
        elevator_operation_fraction = operation_time / 3600
        if elevator_operation_fraction > 1.00
          elevator_operation_fraction = 1.00
        end
        elevator_hourly_fractions << elevator_operation_fraction
      end

      # replace hourly occupancy values with operating fractions
      day_schedule.clearValues
      (0..23).each do |hr|
        t = OpenStudio::Time.new(0, hr, 0, 0)
        value = elevator_hourly_fractions[hr]
        value_plus = if hr <= 22
                       elevator_hourly_fractions[hr + 1]
                     else
                       elevator_hourly_fractions[0]
                     end
        next if value == value_plus

        day_schedule.addValue(t, elevator_hourly_fractions[hr])
      end
    end

    occ_schedule.setName('Elevator Schedule')

    # clone new elevator schedule and assign to elevator
    elev_sch = occ_schedule.clone(model)
    elevator_schedule = elev_sch.name.to_s

    # For elevator lights and fan, assume 100% operation during hours that elevator fraction > 0 (when elevator is in operation).
    # elevator lights
    lights_sch = occ_schedule.clone(model)
    lights_sch = lights_sch.to_ScheduleRuleset.get
    profiles = []
    profiles << lights_sch.defaultDaySchedule
    rules = lights_sch.scheduleRules
    rules.each do |rule|
      profiles << rule.daySchedule
    end
    profiles.each do |profile|
      times = profile.times
      values = profile.values
      values.each_with_index do |val, i|
        if val > 0
          profile.addValue(times[i], 1.0)
        end
      end
    end
    elevator_lights_schedule = lights_sch.name.to_s

    # elevator fan
    fan_sch = occ_schedule.clone(model)
    fan_sch = fan_sch.to_ScheduleRuleset.get
    profiles = []
    profiles << fan_sch.defaultDaySchedule
    rules = fan_sch.scheduleRules
    rules.each do |rule|
      profiles << rule.daySchedule
    end
    profiles.each do |profile|
      times = profile.times
      values = profile.values
      values.each_with_index do |val, i|
        if val > 0
          profile.addValue(times[i], 1.0)
        end
      end
    end
    elevator_fan_schedule = fan_sch.name.to_s

    # @todo currently add elevator doesn't allow me to choose the size of the elevator?
    # ref bldg pdf has formula for motor hp based on weight, speed, counterweight fraction and mech eff (in 5.1.4)

    # @todo should schedules change based on traction vs. hydraulic vs. just taking what is in prototype.

    # call add_elevator in Prototype.hvac_systems.rb to create elevator objects
    elevator = model_add_elevator(model,
                                  target_space,
                                  number_of_elevators,
                                  elevator_type,
                                  elevator_schedule,
                                  elevator_fan_schedule,
                                  elevator_lights_schedule,
                                  building_type)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.elevators', "Adding #{elevator.multiplier.round(1)} #{elevator_type} elevators to the model in #{target_space.name}.")

    # check fraction lost on heat from elevator if traction, change to 100% lost if not setup that way.
    if elevator_type == 'Traction'
      elevator.definition.to_ElectricEquipmentDefinition.get.setFractionLatent(0.0)
      elevator.definition.to_ElectricEquipmentDefinition.get.setFractionRadiant(0.0)
      elevator.definition.to_ElectricEquipmentDefinition.get.setFractionLost(1.0)
    end

    return elevator
  end
end
