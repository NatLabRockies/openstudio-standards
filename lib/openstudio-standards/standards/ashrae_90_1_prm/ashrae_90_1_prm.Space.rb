class ASHRAE901PRM < Standard
  # @!group Space

  # Set the infiltration rate for this space to include the impact of air leakage requirements in the standard.
  #
  # @param space [OpenStudio::Model::Space] space object
  # @param tot_infil_m3_per_s [Float] total infiltration in m3/s
  # @param infil_method [String] infiltration method
  # @param infil_coefficients [Array] Array of 4 items
  #       [Constant Term Coefficient, Temperature Term Coefficient,
  #         Velocity Term Coefficient, Velocity Squared Term Coefficient]
  # @return [Boolean] returns true if successful, false if not
  def space_apply_infiltration_rate(space, tot_infil_m3_per_s, infil_method, infil_coefficients)
    # Calculate infiltration rate
    case infil_method.to_s
      when 'Flow/ExteriorWallArea'
        # Spread the total infiltration rate
        total_exterior_wall_area = 0
        space.model.getSpaces.each do |spc|
          # Get the space conditioning type
          space_cond_type = space_conditioning_category(spc)
          total_exterior_wall_area += spc.exteriorWallArea * spc.multiplier unless space_cond_type == 'Unconditioned'
        end
        prm_raise(total_exterior_wall_area > 0, @sizing_run_dir, 'Total exterior wall area in the model is 0. Check your model inputs')
        adj_infil_flow_ext_wall_area = tot_infil_m3_per_s / total_exterior_wall_area
        OpenStudio.logFree(OpenStudio::Debug, 'prm.log', "For #{space.name}, adj infil = #{adj_infil_flow_ext_wall_area.round(8)} m^3/s*m^2 of above grade wall area.")
      when 'Flow/Area'
        # Spread the total infiltration rate
        total_floor_area = 0
        space.model.getSpaces.each do |spc|
          # Get the space conditioning type
          space_cond_type = space_conditioning_category(spc)
          total_floor_area += spc.floorArea * spc.multipler unless space_cond_type == 'Unconditioned' || space.exteriorArea == 0
        end
        prm_raise(total_floor_area > 0, @sizing_run_dir, 'Sum of the floor area in exterior spaces in the model is 0. Check your model inputs')
        adj_infil_flow_area = tot_infil_m3_per_s / total_floor_area
        OpenStudio.logFree(OpenStudio::Debug, 'prm.log', "For #{space.name}, adj infil = #{adj_infil_flow_area.round(8)} m^3/s*m^2 of space floor area.")
    end

    # Get any infiltration schedule already assigned to this space or its space type
    # If not, the always on schedule will be applied.
    # @todo Infiltration schedules should be based on HVAC operation
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
    else
      # Add specific schedule type object to insure compatibility with the OpenStudio infiltration object
      infil_sch_limit_type = OpenstudioStandards::Schedules.create_schedule_type_limits(space.model,
                                                                                        name: 'Infiltration Schedule Type Limits',
                                                                                        lower_limit_value: 0.0,
                                                                                        upper_limit_value: 1.0,
                                                                                        numeric_type: 'Continuous',
                                                                                        unit_type: 'Dimensionless')
      infil_sch.setScheduleTypeLimits(infil_sch_limit_type)
    end

    # Remove all pre-existing space infiltration objects
    space.spaceInfiltrationDesignFlowRates.each(&:remove)

    # Get the space conditioning type
    space_cond_type = space_conditioning_category(space)
    if space_cond_type != 'Unconditioned'
      # Create an infiltration rate object for this space
      infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space.model)
      infiltration.setName("#{space.name} Infiltration")
      case infil_method.to_s
        when 'Flow/ExteriorWallArea'
          infiltration.setFlowperExteriorWallArea(adj_infil_flow_ext_wall_area.round(13)) if space.exteriorWallArea > 0
        when 'Flow/Area'
          infiltration.setFlowperSpaceFloorArea(adj_infil_flow_area.round(13)) if space.exteriorArea > 0
      end
      infiltration.setSchedule(infil_sch)
      infiltration.setConstantTermCoefficient(infil_coefficients[0]) unless infil_coefficients[0].nil?
      infiltration.setTemperatureTermCoefficient(infil_coefficients[1]) unless infil_coefficients[1].nil?
      infiltration.setVelocityTermCoefficient(infil_coefficients[2]) unless infil_coefficients[2].nil?
      infiltration.setVelocitySquaredTermCoefficient(infil_coefficients[3]) unless infil_coefficients[3].nil?
      infiltration.setSpace(space)
    end

    return true
  end

  # For stable baseline, remove all daylighting controls (sidelighting and toplighting)
  # @param space [OpenStudio::Model::Space] the space with daylighting
  # @param remove_existing [Boolean] if true, will remove existing controls then add new ones
  # @param draw_areas_for_debug [Boolean] If this argument is set to true,
  # @return [Boolean] returns true if successful, false if not
  def space_set_baseline_daylighting_controls(space, remove_existing = false, draw_areas_for_debug = false)
    removed = space_remove_daylighting_controls(space)
    return removed
  end

  # Create and assign PRM computer room electric equipment schedule
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [Boolean] returns true if successful, false if not
  def space_add_prm_computer_room_equipment_schedule(space)
    # Get proposed or baseline model
    model = space.model

    # Get space type associated with the space
    standard_space_type = prm_get_optional_handler(space, @sizing_run_dir, 'spaceType', 'standardsSpaceType').delete(' ').downcase

    # Check if the PRM computer room schedule is already in the model
    schedule_name = 'ASHRAE 90.1 Appendix G - Computer Room Equipment Schedule'
    schedule_found = model.getScheduleRulesetByName(schedule_name)

    # Create and assign the the electric equipment schedule
    if standard_space_type == 'computerroom'
      space.spaceType.get.electricEquipment.each do |elec_equipment|
        # Only create the schedule if it could not be found
        if schedule_found.is_initialized
          computer_room_equipment_schedule_ruleset = model.getScheduleRulesetByName(schedule_name).get
        else
          computer_room_equipment_schedule_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
          computer_room_equipment_schedule_ruleset.setName(schedule_name)
          schedule_fractions = [0.25, 0.5, 0.75, 1.0, 0.25, 0.5, 0.75, 1.0, 0.25, 0.5, 0.75, 1.0]
          # Weekdays and weekends schedules
          schedule_fractions.each_with_index do |frac, i|
            sch_rule = OpenStudio::Model::ScheduleRule.new(computer_room_equipment_schedule_ruleset)
            sch_rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(i.to_i + 1), 1))
            # No leap year according to PRM-RM
            sch_rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(i.to_i + 1), Date.new(2006, i.to_i + 1, -1).day))
            day_sch = sch_rule.daySchedule
            day_sch.setName("#{schedule_name} - Month #{i + 1} - Fraction #{frac}")
            model_add_vals_to_sch(model, day_sch, 'Constant', [frac])
            sch_rule.setApplyAllDays(true)
          end
          # Special days schedules
          equipment_on = OpenStudio::Model::ScheduleDay.new(model)
          model_add_vals_to_sch(model, equipment_on, 'Constant', [1])
          equipment_off = OpenStudio::Model::ScheduleDay.new(model)
          model_add_vals_to_sch(model, equipment_off, 'Constant', [0])
          computer_room_equipment_schedule_ruleset.setHolidaySchedule(equipment_on)
          computer_room_equipment_schedule_ruleset.setCustomDay1Schedule(equipment_on)
          computer_room_equipment_schedule_ruleset.setCustomDay2Schedule(equipment_on)
          computer_room_equipment_schedule_ruleset.setSummerDesignDaySchedule(equipment_on)
          computer_room_equipment_schedule_ruleset.setWinterDesignDaySchedule(equipment_off)
        end
        elec_equipment.setSchedule(computer_room_equipment_schedule_ruleset)
      end
    end

    return true
  end
end
