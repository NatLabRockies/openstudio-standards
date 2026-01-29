class AppendixGPRMTests < Minitest::Test
  #
  # this checks the PRM baseline sizing requirement of supply air temperature delta T
  #
  # @param model [OpenStudio::Model::model] openstudio model object
  # @param building_type [String]  building type
  # @param template [String] template name
  # @param climate_zone [<Type>] climate zone name
  #
  def check_sizing_delta_t(model, building_type, template, climate_zone)
    std = Standard.build('90.1-PRM-2019')
    model.getThermalZones.each do |thermal_zone|
      delta_t_r = 20
      thermal_zone.spaces.each do |space|
        space_std_type = space.spaceType.get.standardsSpaceType.get
        if space_std_type == 'laboratory'
          delta_t_r = 17
        end
      end

      # cooling delta t
      if OpenstudioStandards::ThermalZone.thermal_zone_cooled?(thermal_zone)
        case thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperatureInputMethod
        when 'SupplyAirTemperatureDifference'
          assert((thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperatureDifference - delta_t_r).abs < 0.001, "supply to room cooling temperature difference for #{thermal_zone.name} in the #{building_type}, #{template}, #{climate_zone} model is incorrect. It is #{thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperatureDifference}, but should be #{delta_t_r}")
        when 'SupplyAirTemperature'
          setpoint_c = nil
          tstat = thermal_zone.thermostatSetpointDualSetpoint
          if tstat.is_initialized
            tstat = tstat.get
            setpoint_sch = tstat.coolingSetpointTemperatureSchedule
            if setpoint_sch.is_initialized
              setpoint_c = OpenstudioStandards::Schedules.schedule_get_min_max(setpoint_sch.get)['min']
            end
          end
          if setpoint_c.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "#{thermal_zone.name} does not have a valid cooling supply air temperature setpoint identified .")
          else
            assert(((thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperature - setpoint_c).abs - delta_t_r / 9.0 * 5).abs < 0.001, "supply to room cooling temperature difference for #{thermal_zone.name} in the #{building_type} #{template}, #{climate_zone} model is incorrect. It is #{(thermal_zone.sizingZone.zoneCoolingDesignSupplyAirTemperature - setpoint_c).abs}, but should be #{delta_t_r}.")
          end
        end
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ThermalZone', "#{thermal_zone.name} is not a cooled zone, skip cooling supply air temperature set point difference test.")
      end

      thermal_zone.equipment.each do |eqt|
        if eqt.to_ZoneHVACUnitHeater.is_initialized
          next # skip checking the heating delta t if the zone has a unit heater.
        end
      end

      # heating delta t
      if OpenstudioStandards::ThermalZone.thermal_zone_heated?(thermal_zone)
        has_unit_heater = false
        # 90.1 Appendix G G3.1.2.8.2
        thermal_zone.equipment.each do |eqt|
          if eqt.to_ZoneHVACUnitHeater.is_initialized
            setpoint_c = OpenStudio.convert(105, 'F', 'C').get
            has_unit_heater = true
          end
        end
        if has_unit_heater
          assert((thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperature - setpoint_c).abs < 0.001, "heating design supply air temperature for #{thermal_zone.name} in the #{building_type} #{template}, #{climate_zone} model is incorrect. For zones with unit heaters, heating design supply air temperature should be #{setpoint_c} (90.1 Appendix G3.1.2.8.2)")
        else
          case thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperatureInputMethod
          when 'SupplyAirTemperatureDifference'
            assert((thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperatureDifference - delta_t_r).abs < 0.001, "supply to room heating temperature difference for #{thermal_zone.name} in the #{building_type}, #{template}, #{climate_zone} model is incorrect. It is #{thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperatureDifference}, but should be #{delta_t_r}.")
          when 'SupplyAirTemperature'
            setpoint_c = nil
            tstat = thermal_zone.thermostatSetpointDualSetpoint
            if tstat.is_initialized
              tstat = tstat.get
              setpoint_sch = tstat.heatingSetpointTemperatureSchedule
              if setpoint_sch.is_initialized
                setpoint_c = OpenstudioStandards::Schedules.schedule_get_min_max(setpoint_sch.get)['max']
              end
            end
            if setpoint_c.nil?
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.ThermalZone', "#{thermal_zone.name} does not have a valid heating supply air temperature setpoint identified.")
            else
              assert(((thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperature - setpoint_c).abs - delta_t_r / 9.0 * 5).abs < 0.001, "supply to room heating temperature difference for #{thermal_zone.name} in the #{building_type} #{template}, #{climate_zone} model is incorrect. It is #{(thermal_zone.sizingZone.zoneHeatingDesignSupplyAirTemperature - setpoint_c).abs}, but should be #{delta_t_r}.")
            end
          end
        end
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.ThermalZone', "#{thermal_zone.name} is not a heated zone, skip heating supply air temperature set point difference test.")
      end
    end
  end

  #
  # this check uses very similar code to the one that implements this requirement
  #
  # @param model [OpenStudio::Model::Model] openstudio model object
  # @param building_type [String]  building type
  # @param template [String] template name
  # @param climate_zone [<Type>] climate zone name
  #
  def check_sizing_values(model, building_type, template, climate_zone)
    space_loads = model.getSpaceLoads
    loads = []
    space_loads.sort.each do |space_load|
      load_type = space_load.iddObjectType.valueName.sub('OS_', '').strip.sub('_', '')
      casting_method_name = "to_#{load_type}"
      if space_load.respond_to?(casting_method_name)
        casted_load = space_load.public_send(casting_method_name).get
        loads << casted_load
      else
        p 'Need Debug, casting method not found @JXL'
      end
    end

    std_prm = ASHRAE901PRM.build('90.1-PRM-2019')

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
      next unless !load_schedule_name.nil?

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
        load_schmode = std_prm.get_weekday_values_from_8760(model,
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

        summer_dd_schedule = load_schedule.summerDesignDaySchedule
        assert((summer_dd_schedule.times[0] == OpenStudio::Time.new(1.0) && (summer_dd_schedule.values[0] - summer_value).abs < 0.001), "Baseline cooling sizing schedule for load #{load.name} in the #{building_type}, #{template}, #{climate_zone} model is incorrect.")

        winter_dd_schedule = load_schedule.winterDesignDaySchedule
        assert((winter_dd_schedule.times[0] == OpenStudio::Time.new(1.0) && (winter_dd_schedule.values[0] - winter_value).abs < 0.001), "Baseline heating sizing schedule for load #{load.name} in the #{building_type}, #{template}, #{climate_zone} model is incorrect.")

      when 'ScheduleConstant'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Space load #{load.name} has schedule type of ScheduleConstant. Nothing to be done for ScheduleConstant")
        next
      end
    end
  end

  def dcv_is_on(thermal_zone, air_loop_hvac)
    # check air loop level DCV enabled
    return false unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized

    oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
    controller_oa = oa_system.getControllerOutdoorAir
    controller_mv = controller_oa.controllerMechanicalVentilation
    return false unless controller_mv.demandControlledVentilation == true

    # check zone OA flow per person > 0
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

    return zone_dcv
  end

  def remove_zone_oa_per_person_spec(model, arguments)
    # argument contains a list of zone names to remove oa per person specification
    arguments.each do |zone_name|
      thermal_zone = model.getThermalZoneByName(zone_name).get
      OpenstudioStandards::ThermalZone.thermal_zone_convert_outdoor_air_to_per_area(thermal_zone)
    end
    return model
  end

  # Check whether heat type meets expectations
  # Electric if warm CZ, fuel if cold
  # Also check HP vs electric resistance depending on baseline system type
  # @param model, climate_zone, mz_or_sz, expected_elec_heat_type
  # mz_or_sz = MZ or SZ or PTU
  # expected_elec_heat_type = Electric or HeatPump
  def check_heat_type(model, climate_zone, mz_or_sz, expected_elec_heat_type)
    return false unless !model.getAirLoopHVACs.empty?

    model.getAirLoopHVACs.each do |air_loop|
      num_zones = air_loop.thermalZones.size
      if (num_zones > 1 && mz_or_sz == 'MZ') || (num_zones == 1 && mz_or_sz == 'SZ')
        # This is a multizone system, do the test

        # error if Loop app G heating fuels method is not available
        if air_loop.model.version < OpenStudio::VersionString.new('3.6.0')
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.test_appendix_g_prm', 'Required Loop method .appGHeatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
        end

        heat_types = air_loop.appGHeatingFuelTypes.map(&:valueName)
        if climate_zone =~ /0A|0B|1A|1B|2A|2B|3A/
          # Heat type is electric or heat pump
          assert(heat_types.include?(expected_elec_heat_type), "Incorrect heat type for #{air_loop.name.get}; expected #{expected_elec_heat_type}")
        else
          # Heat type is Fuel
          assert(heat_types.include?('Fuel'), "Incorrect heat type for #{air_loop.name.get}; expected Fuel")
        end
      end
    end

    # TODO: Also check zone equipment
    # if mz_or_sz == 'PTU' || mz_or_sz == 'SZ'
    # end
  end

  # Check if the system type is heat only and
  # check fan power for non mechanically cooled
  # system
  def check_if_heat_only(model, climate_zone, building_type)
    model.getAirLoopHVACs.each do |air_loop|
      system_type = air_loop.additionalProperties.getFeatureAsString('baseline_system_type').get
      assert(system_type == 'Electric_Furnace', "Baseline system for #{building_type} in climate zone #{climate_zone} should be Electric_Furnace, not #{system_type}.")
    end

    # check baseline system fan power
    model.getFanOnOffs.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      assert(fan_power_ip.round(3) == 0.054, "Fan power (nmc system) for #{building_type} in climate zone #{climate_zone} is #{fan_power_ip.round(1)} instead of 0.054.")
    end
    model.getFanConstantVolumes.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      assert(fan_power_ip.round(1) == 0.3, "Fan power for #{building_type} in climate zone #{climate_zone} is #{fan_power_ip.round(1)} instead of 0.3.")
    end
  end

  # Check if all baseline system types are PSZ
  # @param model, sub_text for error messages
  def check_if_psz(model, sub_text, zone: nil)
    num_zones = 0
    num_dx_coils = 0
    num_dx_coils += model.getCoilCoolingDXSingleSpeeds.size
    num_dx_coils += model.getCoilCoolingDXTwoSpeeds.size
    num_dx_coils += model.getCoilCoolingDXMultiSpeeds.size
    has_chiller = model.getPlantLoopByName('Chilled Water Loop').is_initialized
    model.getAirLoopHVACs.each do |air_loop|
      if zone.nil?
        num_zones = air_loop.thermalZones.size
        # if num zones is greater than 1 for any system, then set as multizone
        assert(num_zones = 1 && num_dx_coils > 0 && has_chiller == false, "Baseline system selection failed for #{air_loop.name}; should be PSZ for " + sub_text)
      else
        th_zones = []
        air_loop.thermalZones.each { |th_zone| th_zones << th_zone.name.to_s }
        if th_zones.include? zone
          # If multizone system
          return false if air_loop.thermalZones.size > 1

          zone_system_check = false
          model.getAirLoopHVACUnitarySystems.each do |unit_system|
            # Check if airloop includes a unitary system with constant volume fan single speed DX cooling coil
            zone_system_check = true if unit_system.controllingZoneorThermostatLocation.get.name.to_s == zone.name.to_s &&
                                        unit_system.controlType == 'Load' &&
                                        unit_system.coolingCoil.get.to_CoilCoolingDXSingleSpeed.is_initialized &&
                                        unit_system.supplyFan.get.to_FanOnOff.is_initialized
          end
          return zone_system_check
        end
      end
    end

    # check baseline system fan power
    model.getFanOnOffs.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      fan_bhp_ip = fan_power_ip * fan.motorEfficiency / 746.0
      assert(fan_bhp_ip.round(5) == 0.00094, "Fan power for #{sub_text} is #{fan_bhp_ip.round(5)} instead of 0.00094.")
      if fan_bhp_ip * OpenStudio.convert(OpenstudioStandards::HVAC.fan_design_air_flow(fan), 'm^3/s', 'cfm').get <= 1.0
        assert(fan.motorEfficiency == 0.825, "Fan motor efficiency for #{fan.name} in #{sub_text} is #{fan.motorEfficiency}, 0.825 is expected.")
      end
    end
  end

  # Check if any baseline system type is PVAV
  # @param model, sub_text for error messages
  def check_if_pvav(model, sub_text)
    num_zones = 0
    num_dx_coils = 0
    num_dx_coils += model.getCoilCoolingDXSingleSpeeds.size
    num_dx_coils += model.getCoilCoolingDXTwoSpeeds.size
    num_dx_coils += model.getCoilCoolingDXMultiSpeeds.size
    has_chiller = model.getPlantLoopByName('Chilled Water Loop').is_initialized
    has_multizone = false
    model.getAirLoopHVACs.each do |air_loop|
      num_zones = air_loop.thermalZones.size
      # if num zones is greater than 1 for any system, then set as multizone
      if num_zones > 1
        has_multizone = true
      end
    end
    assert(has_multizone && num_dx_coils > 0 && has_chiller == false, 'Baseline system selection failed; should be PVAV for ' + sub_text)

    # check baseline system fan power
    # central fans
    model.getFanVariableVolumes.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      fan_bhp_ip = fan_power_ip * fan.motorEfficiency / 746.0
      assert(fan_bhp_ip.round(4) == 0.0013, "Fan power for central fan in #{sub_text} is #{fan_bhp_ip.round(4)} instead of 0.0013.")
      fan_bhp_ip *= OpenStudio.convert(OpenstudioStandards::HVAC.fan_design_air_flow(fan), 'm^3/s', 'cfm').get
      if fan_bhp_ip <= 20.0 && fan_bhp_ip > 15.0
        assert(fan.motorEfficiency == 0.91, "Fan motor efficiency for #{fan.name} in #{sub_text} is #{fan.motorEfficiency}, 0.91 is expected.")
      end
    end

    # PFP fans
    model.getFanConstantVolumes.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      assert(fan_power_ip.round(2) == 0.35, "Fan power for terminal fan in #{sub_text} is #{fan_power_ip.round(1)} instead of 0.35.")
    end
  end

  def check_return_reflief_fan_pwr_dist(model)
    std = Standard.build('90.1-PRM-2019')
    model.getAirLoopHVACs.each do |air_loop|
      # Get supply fan
      supply_fan = air_loop.supplyFan.get
      if supply_fan.to_FanConstantVolume.is_initialized
        supply_fan = supply_fan.to_FanConstantVolume.get
      elsif supply_fan.to_FanVariableVolume.is_initialized
        supply_fan = supply_fan.to_FanVariableVolume.get
      elsif supply_fan.to_FanOnOff.is_initialized
        supply_fan = supply_fan.to_FanOnOff.get
      elsif supply_fan.to_FanSystemModel.is_initialized
        supply_fan = supply_fan.to_FanSystemModel.get
      end

      # Get return fan
      return_fan = air_loop.returnFan.get
      if return_fan.to_FanConstantVolume.is_initialized
        return_fan = return_fan.to_FanConstantVolume.get
      elsif return_fan.to_FanVariableVolume.is_initialized
        return_fan = return_fan.to_FanVariableVolume.get
      elsif return_fan.to_FanOnOff.is_initialized
        return_fan = return_fan.to_FanOnOff.get
      elsif return_fan.to_FanSystemModel.is_initialized
        return_fan = return_fan.to_FanSystemModel.get
      end

      # Get relief fan
      relief_fan = air_loop.reliefFan.get
      if relief_fan.to_FanConstantVolume.is_initialized
        relief_fan = relief_fan.to_FanConstantVolume.get
      elsif relief_fan.to_FanVariableVolume.is_initialized
        relief_fan = relief_fan.to_FanVariableVolume.get
      elsif relief_fan.to_FanOnOff.is_initialized
        relief_fan = relief_fan.to_FanOnOff.get
      elsif relief_fan.to_FanSystemModel.is_initialized
        relief_fan = relief_fan.to_FanSystemModel.get
      end

      # Fan power ratios
      return_to_supply_fan_power_ratio = OpenstudioStandards::HVAC.fan_fanpower(return_fan) / OpenstudioStandards::HVAC.fan_fanpower(supply_fan)
      relief_to_supply_fan_power_ratio = OpenstudioStandards::HVAC.fan_fanpower(relief_fan) / OpenstudioStandards::HVAC.fan_fanpower(supply_fan)

      assert(return_to_supply_fan_power_ratio.round(0) == 2, "Fan power ratio between return and supply is incorrect, got #{return_to_supply_fan_power_ratio.round(0)} instead 2.")
      assert(relief_to_supply_fan_power_ratio.round(0) == 3, "Fan power ratio between relief and supply is incorrect, got #{relief_to_supply_fan_power_ratio.round(0)} instead 3.")
    end
  end

  # Check if building has baseline VAV/chiller for at least one air loop
  # @param model, sub_text for error messages
  def check_if_vav_chiller(model, sub_text)
    num_zones = 0
    num_dx_coils = 0
    has_chiller = model.getPlantLoopByName('Chilled Water Loop').is_initialized
    has_multizone = false
    model.getAirLoopHVACs.each do |air_loop|
      num_zones = air_loop.thermalZones.size
      # if num zones is greater than 1 for any system, then set as multizone
      if num_zones > 1
        has_multizone = true
      end
    end
    assert(has_multizone && has_chiller, 'Baseline system selection failed; should be VAV/chiller for ' + sub_text)

    # check baseline system fan power
    # central fans
    model.getFanVariableVolumes.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      fan_bhp_ip = fan_power_ip * fan.motorEfficiency / 746.0
      assert(fan_bhp_ip.round(4) == 0.0013, "Fan power for central fan in #{sub_text} is #{fan_power_ip.round(4)} instead of 0.0013.")
      fan_bhp_ip *= OpenStudio.convert(OpenstudioStandards::HVAC.fan_design_air_flow(fan), 'm^3/s', 'cfm').get
      if fan_bhp_ip <= 20.0 && fan_bhp_ip > 15.0
        assert(fan.motorEfficiency == 0.91, "Fan motor efficiency for #{fan.name} in #{sub_text} is #{fan.motorEfficiency}, 0.91 is expected.")
      end
    end

    # PFP fans
    model.getFanConstantVolumes.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      assert(fan_power_ip.round(2) == 0.35, "Fan power for terminal fan in #{sub_text} is #{fan_power_ip.round(1)} instead of 0.35.")
    end
  end

  # Check if model uses standard VAV boxes of FP boxes
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @param energy_source [String] Energy source used for heating
  def check_terminal_type(model, energy_source, mod_str)
    model.getAirLoopHVACs.each do |airloop|
      airloop.thermalZones.each do |zone|
        zone.equipment.each do |equip|
          expected_results = false
          if equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
            expected_results = true if energy_source != 'Electric'
            assert(expected_results, "Standard VAV boxes are not expected for #{mod_str}.")
          elsif equip.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized
            expected_results = true if energy_source == 'Electric'
            terminal = equip.to_AirTerminalSingleDuctParallelPIUReheat.get
            assert(expected_results, "Fan powered boxes are not expected for #{mod_str}.")
            # check secondary flow fraction
            check_secondary_flow_fraction(terminal, mod_str)
          end
        end
      end
    end
  end

  # Check the model's secondary flow fraction
  # @param terminal [OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat] Parallel PIU terminal
  # @param mod_str [String] Run description
  def check_secondary_flow_fraction(terminal, mod_str)
    if terminal.maximumSecondaryAirFlowRate.is_initialized
      secondary_flow = terminal.maximumSecondaryAirFlowRate.get.to_f
    else
      secondary_flow = terminal.autosizedMaximumSecondaryAirFlowRate.get.to_f
    end
    if terminal.maximumPrimaryAirFlowRate.is_initialized
      primary_flow = terminal.maximumPrimaryAirFlowRate.get.to_f
    else
      primary_flow = terminal.autosizedMaximumPrimaryAirFlowRate.get.to_f
    end
    secondary_flow_frac = secondary_flow / primary_flow
    err = (secondary_flow_frac - 0.5).abs
    # need to allow some tolerance due to secondary flow getting set before final sizing run
    assert(err < 0.01, "Expected secondary flow fraction should be 0.5 but #{secondary_flow_frac} is used for #{mod_str}.")
  end

  # Check if baseline system type is PTAC or PTHP
  # @param model, sub_text for error messages
  def check_if_pkg_terminal(model, climate_zone, sub_text)
    pass_test = true
    # building fails if any zone is not packaged terminal unit
    # or if heat type is incorrect
    model.getThermalZones.sort.each do |thermal_zone|
      has_ptac = false
      has_pthp = false
      has_unitheater = false
      thermal_zone.equipment.each do |equip|
        # Skip HVAC components
        next unless equip.to_HVACComponent.is_initialized

        equip = equip.to_HVACComponent.get
        if equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          has_ptac = true
        elsif equip.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
          has_pthp = true
        elsif equip.to_ZoneHVACUnitHeater.is_initialized
          has_unitheater = true
        end
      end
      # Test for hvac type by climate
      if climate_zone =~ /0A|0B|1A|1B|2A|2B|3A/
        if has_pthp == false
          pass_test = false
        end
      else
        if has_ptac == false
          pass_test = false
        end
      end
    end
    if climate_zone =~ /0A|0B|1A|1B|2A|2B|3A/
      assert(pass_test, "Baseline system selection failed for climate #{climate_zone}: should be PTHP for " + sub_text)
    else
      assert(pass_test, "Baseline system selection failed for climate #{climate_zone}: should be PTAC for " + sub_text)
    end

    # check baseline system fan power
    model.getFanConstantVolumes.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      assert(fan_power_ip.round(1) == 0.3, "Fan power for #{sub_text} is #{fan_power_ip.round(1)} instead of 0.3.")
    end
  end

  # Check if baseline system type is four pipe fan coil/ constant speed
  # @param model, sub_text for error messages
  def check_if_sz_cv(model, climate_zone, sub_text)
    # building fails if any zone is not packaged terminal unit
    # or if heat type is incorrect
    model.getThermalZones.sort.each do |thermal_zone|
      pass_test = false
      is_fpfc = false
      heat_type = ''
      thermal_zone.equipment.each do |equip|
        # Skip HVAC components
        next unless equip.to_HVACComponent.is_initialized

        equip = equip.to_HVACComponent.get
        is_fpfc = equip.to_ZoneHVACFourPipeFanCoil.is_initialized

        if is_fpfc
          # pass test for FPFC if at least one zone equip is FPFC; others may be exhaust fan, or possibly something else
          pass_test = true
        end
        if is_fpfc
          # Also check heat type
          equip = equip.to_ZoneHVACFourPipeFanCoil.get

          # error if HVACComponent app G heating fuels method is not available
          if equip.model.version < OpenStudio::VersionString.new('3.6.0')
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.test_appendix_g_prm', 'Required HVACComponent method .appGHeatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
          end

          heat_types = equip.heatingCoil.appGHeatingFuelTypes.map(&:valueName)
          if climate_zone =~ /0A|0B|1A|1B|2A|2B|3A/
            assert(heat_types.include?('Electric'), "Baseline system selection failed for climate #{climate_zone}: FPFC should have electric heat for " + sub_text)
          else
            assert(heat_types.include?('Fuel'), "Baseline system selection failed for climate #{climate_zone}: FPFC should have hot water heat for " + sub_text)
          end
        end
      end
      assert(pass_test, 'Baseline system selection failed: should be FPFC for ' + sub_text)
    end

    # check baseline system fan power
    model.getFanOnOffs.sort.each do |fan|
      fan_power_si = OpenstudioStandards::HVAC.fan_fanpower(fan) / OpenstudioStandards::HVAC.fan_design_air_flow(fan)
      fan_power_ip = fan_power_si / OpenStudio.convert(1, 'm^3/s', 'cfm').get
      fan_bhp_ip = fan_power_ip * fan.motorEfficiency / 746.0
      assert(fan_bhp_ip.round(5) == 0.00094, "Fan power for #{sub_text} is #{fan_bhp_ip.round(5)} instead of 0.00094.")
      if fan_bhp_ip * OpenStudio.convert(OpenstudioStandards::HVAC.fan_design_air_flow(fan), 'm^3/s', 'cfm').get <= 1.0
        assert(fan.motorEfficiency == 0.825, "Fan motor efficiency for #{fan.name} in #{sub_text} is #{fan.motorEfficiency}, 0.825 is expected.")
      end
    end
  end

  # Check if baseline system type is a single-zone system with variable-air-volume fan
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def check_cmp_dtctr_system_type(model)
    zone_load_s = 0
    # Individual zone load check
    model.getThermalZones.each do |zone|
      # Get design cooling load of computer rooms
      zone.spaces.each do |space|
        if space.spaceType.get.standardsSpaceType.get == 'computer room'
          # error if zone design load methods are not available
          if zone.model.version < OpenStudio::VersionString.new('3.6.0')
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.test_appendix_g_prm', 'Required ThermalZone method .autosizedCoolingDesignLoad is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
          end
          zone_load_w = zone.autosizedCoolingDesignLoad.get
          zone_load_w *= zone.multiplier
          zone_load = OpenStudio.convert(zone_load_w, 'W', 'Btu/hr').get
          zone_load_s += zone_load
          if zone_load >= 600000
            # System 11 (PSZ-VAV) is required
            assert(check_if_sz_vav(model, zone), "Zone #{zone.name} should be served by a packaged single zone VAV system (system 11).")
          elsif zone_load < 600000
            # System 3 or 4 is required
            assert(check_if_psz(model, '', zone: zone), "Zone #{zone.name} should be served by a packaged single zone CAV system (system 3 or 4).")
          end
        end
      end
    end

    # Building load check
    return false unless zone_load_s > 3000000

    model.getThermalZones.each do |zone|
      zone.spaces.each do |space|
        if space.spaceType.get.standardsSpaceType.get == 'computer room'
          # System 11 is required
          assert(check_if_sz_vav(model, zone), "Zone #{zone.name} should be served by a packaged single zone VAV system (system 11) because building computer rooms peak load exceed 3,000, 000 Btu/h.")
        end
      end
    end
  end

  def check_if_sz_vav(model, zone)
    zone_system_check = false
    model.getAirLoopHVACUnitarySystems.each do |unit_system|
      # Check if the system is system 11 by checking if the load control type is SingleZoneVAV
      zone_system_check = true if unit_system.controllingZoneorThermostatLocation.get.name.to_s == zone.name.to_s &&
                                  unit_system.controlType == 'SingleZoneVAV' &&
                                  unit_system.coolingCoil.get.to_CoilCoolingWater.is_initialized
    end
    return zone_system_check
  end

  def get_fan_hours_per_week(model, air_loop)
    fan_schedule = air_loop.availabilitySchedule
    fan_hours_8760 = OpenstudioStandards::Schedules.schedule_get_hourly_values(fan_schedule)
    fan_hours_52 = []

    hr_of_yr = -1
    (0..51).each do |iweek|
      week_sum = 0
      (0..167).each do |hr_of_wk|
        hr_of_yr += 1
        week_sum += fan_hours_8760[hr_of_yr]
      end
      fan_hours_52 << week_sum
    end
    max_fan_hours = fan_hours_52.max
    return max_fan_hours
  end

  # Placeholder method to indicate that we want to check unmet
  # load hours
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param arguments [Array] Not used
  def unmet_load_hours(model, arguments)
    return model
  end

  def helper_add_window_to_wwr_with_door(target_wwr, surface, construction, door_list, model)
    if target_wwr > 0.0
      new_window = surface.setWindowToWallRatio(target_wwr, 0.6, true).get
      new_window.setConstruction(construction) unless construction.nil?
    end
    # add door back.
    unless door_list.empty?
      door_list.each do |door|
        os_door = OpenStudio::Model::SubSurface.new(door['vertices'], model)
        os_door.setName(door['name'])
        os_door.setConstruction(door['construction'])
        os_door.setSurface(surface)
      end
    end
  end

  def reduce_lpd(model, arguments)
    space = model.getSpaceByName('Room_1_Flr_3').get
    space.setLightingPowerPerFloorArea(2)
    space = model.getSpaceByName('Room_4_Mult19_Flr_3').get
    space.setLightingPowerPerFloorArea(2)

    return model
  end
end
