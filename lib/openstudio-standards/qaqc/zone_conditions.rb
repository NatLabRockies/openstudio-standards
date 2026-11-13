# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group Zone Conditions

    # Check that there are no people or lights in plenums.
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_plenum_loads(category, target_standard, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Plenum Loads')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that the plenums do not have people or lights.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        @model.getThermalZones.sort.each do |zone|
          next unless OpenstudioStandards::ThermalZone.thermal_zone_plenum?(zone)

          # people
          num_people = zone.numberOfPeople
          if num_people > 0
            check_elems << OpenStudio::Attribute.new('flag', "#{zone.name} is a plenum, but has #{num_people.round(1)} people.  Plenums should not contain people.")
          end
          # lights
          lights_w = zone.lightingPower
          if lights_w > 0
            check_elems << OpenStudio::Attribute.new('flag', "#{zone.name} is a plenum, but has #{lights_w.round(1)} W of lights.  Plenums should not contain lights.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check for excess simulataneous heating and cooling
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_delta [Double] threshold for throwing an error for temperature difference
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_supply_air_and_thermostat_temperature_difference(category, target_standard, max_delta: 2.0, name_only: false)
      # G3.1.2.9 requires a 20 degree F delta between supply air temperature and zone temperature.
      target_clg_delta = 20.0

      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Supply and Zone Air Temperature')
      check_elems << OpenStudio::Attribute.new('category', category)
      if @utility_name.nil?
        check_elems << OpenStudio::Attribute.new('description', "Check if fans modeled to ASHRAE 90.1 2013 Section G3.1.2.9 requirements. Compare the supply air temperature for each thermal zone against the thermostat setpoints. Throw flag if temperature difference excedes threshold of #{target_clg_delta}F plus the selected tolerance.")
      else
        check_elems << OpenStudio::Attribute.new('description', "Check if fans modeled to ASHRAE 90.1 2013 Section G3.1.2.9 requirements. Compare the supply air temperature for each thermal zone against the thermostat setpoints. Throw flag if temperature difference excedes threshold set by #{@utility_name}.")
      end

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        # loop through thermal zones
        @model.getThermalZones.sort.each do |thermal_zone|
          # skip plenums
          next if OpenstudioStandards::ThermalZone.thermal_zone_plenum?(thermal_zone)

          # skip zones without thermostats
          next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized

          # populate thermostat ranges
          model_clg_min = nil
          thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
          if thermostat.coolingSetpointTemperatureSchedule.is_initialized
            clg_sch = thermostat.coolingSetpointTemperatureSchedule.get
            schedule_values = nil
            if clg_sch.to_ScheduleRuleset.is_initialized
              schedule_values = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(clg_sch.to_ScheduleRuleset.get)
            elsif clg_sch.to_ScheduleConstant.is_initialized
              schedule_values = OpenstudioStandards::Schedules.schedule_constant_get_min_max(clg_sch.to_ScheduleConstant.get)
            end

            unless schedule_values.nil?
              model_clg_min = schedule_values['min']
            end
          end

          # flag if there is setpoint schedule can't be inspected (isn't ruleset)
          if model_clg_min.nil?
            check_elems << OpenStudio::Attribute.new('flag', "Can't inspect thermostat schedules for #{thermal_zone.name}")
          else

            # get supply air temps from thermal zone sizing
            sizing_zone = thermal_zone.sizingZone
            clg_supply_air_temp = sizing_zone.zoneCoolingDesignSupplyAirTemperature

            # convert model values to IP
            model_clg_min_ip = OpenStudio.convert(model_clg_min, 'C', 'F').get
            clg_supply_air_temp_ip = OpenStudio.convert(clg_supply_air_temp, 'C', 'F').get

            # check supply air against zone temperature (only check against min setpoint, assume max is night setback)
            if model_clg_min_ip - clg_supply_air_temp_ip > target_clg_delta + max_delta
              check_elems << OpenStudio::Attribute.new('flag', "For #{thermal_zone.name} the delta temp between the cooling supply air temp of #{clg_supply_air_temp_ip.round(2)} (F) and the minimum thermostat cooling temp of #{model_clg_min_ip.round(2)} (F) is more than #{max_delta} (F) larger than the expected delta of #{target_clg_delta} (F)")
            elsif model_clg_min_ip - clg_supply_air_temp_ip < target_clg_delta - max_delta
              check_elems << OpenStudio::Attribute.new('flag', "For #{thermal_zone.name} the delta temp between the cooling supply air temp of #{clg_supply_air_temp_ip.round(2)} (F) and the minimum thermostat cooling temp of #{model_clg_min_ip.round(2)} (F) is more than #{max_delta} (F) smaller than the expected delta of #{target_clg_delta} (F)")
            end

          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check that all zones with people are conditioned (have a thermostat with setpoints)
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_occupied_zones_conditioned(category, target_standard, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Conditioned Zones')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that all zones with people have thermostats.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        @model.getThermalZones.sort.each do |zone|
          # only check zones with people
          num_ppl = zone.numberOfPeople
          next unless zone.numberOfPeople > 0

          # Check that the zone is heated (at a minimum) by checking that the heating setpoint is at least 41F.
          # Sometimes people include thermostats but use setpoints such that the system never comes on.
          unless OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone)
            check_elems << OpenStudio::Attribute.new('flag', "#{zone.name} has #{num_ppl} people but is not heated.  Zones containing people are expected to be conditioned, heated-only at a minimum.  Heating setpoint must be at least 41F to be considered heated.")
          end
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # Check unmet hours
    #
    # @param category [String] category to bin this check into
    # @param target_standard [String] standard template, e.g. '90.1-2013'
    # @param max_unmet_hrs [Double] threshold for unmet hours reporting
    # @param expect_clg_unmet_hrs [Bool] boolean on whether to expect unmet cooling hours for a model without a cooling system
    # @param expect_htg_unmet_hrs [Bool] boolean on whether to expect unmet heating hours for a model without a heating system
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_unmet_hours(category, target_standard,
                               max_unmet_hrs: 550.0,
                               expect_clg_unmet_hrs: false,
                               expect_htg_unmet_hrs: false,
                               name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Unmet Hours')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check model unmet hours.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      std = Standard.build(target_standard)

      begin
        unmet_heating_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours(@model)
        unmet_cooling_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours(@model)
        unmet_hrs = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(@model)
        if unmet_hrs
          if unmet_hrs > max_unmet_hrs
            if expect_clg_unmet_hrs && expect_htg_unmet_hrs
              check_elems << OpenStudio::Attribute.new('flag', "Warning: Unmet heating and cooling hours expected.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}).")
            elsif expect_clg_unmet_hrs && !expect_htg_unmet_hrs && unmet_heating_hrs >= max_unmet_hrs
              check_elems << OpenStudio::Attribute.new('flag', "Major Error: Unmet cooling hours expected, but unmet heating hours exceeds limit of #{max_unmet_hrs}.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}).")
            elsif expect_clg_unmet_hrs && !expect_htg_unmet_hrs && unmet_heating_hrs < max_unmet_hrs
              check_elems << OpenStudio::Attribute.new('flag', "Warning: Unmet cooling hours expected.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}).")
            elsif expect_htg_unmet_hrs && !expect_clg_unmet_hrs && unmet_cooling_hrs >= max_unmet_hrs
              check_elems << OpenStudio::Attribute.new('flag', "Major Error: Unmet heating hours expected, but unmet cooling hours exceeds limit of #{max_unmet_hrs}.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}).")
            elsif expect_htg_unmet_hrs && !expect_clg_unmet_hrs && unmet_cooling_hrs < max_unmet_hrs
              check_elems << OpenStudio::Attribute.new('flag', "Warning: Unmet heating hours expected.  There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}).")
            else
              check_elems << OpenStudio::Attribute.new('flag', "Major Error: There were #{unmet_heating_hrs.round(1)} unmet occupied heating hours and #{unmet_cooling_hrs.round(1)} unmet occupied cooling hours (total: #{unmet_hrs.round(1)}), more than the limit of #{max_unmet_hrs}.")
            end
          end
        else
          check_elems << OpenStudio::Attribute.new('flag', 'Warning: Could not determine unmet hours; simulation may have failed.')
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end
  end
end
