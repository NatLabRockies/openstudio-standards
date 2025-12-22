class NECB2011
  # At this point the only way to implement multi-stage cooling and heating in OS is through the use
  # of object "AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed". This component uses as an argument a control
  # zone and then it responds to a call for heating or cooling for that control zone. This aspect of this
  # component makes it incompatible with how a system_1 make up air unit works where a constant supply air
  # temperature is delivered to the spaces. It is therefore not recommended to use this method and to use
  # the single speed implementation of systems_1.
  def add_sys1_unitary_ac_baseboard_heating_multi_speed(model:,
                                                        zones:,
                                                        mau_type:,
                                                        mau_heating_coil_type:,
                                                        baseboard_type:,
                                                        hw_loop:)

    # Keep all data and assumptions for both systems on the top here for easy reference.
    system_data = {}
    system_data[:name] = 'Sys_1_Make-up air unit'
    system_data[:PreheatDesignTemperature] = 7.0
    system_data[:PreheatDesignHumidityRatio] = 0.008
    system_data[:PrecoolDesignTemperature] = 13.0
    system_data[:PrecoolDesignHumidityRatio] = 0.008
    system_data[:SizingOption] = 'NonCoincident'
    system_data[:CoolingDesignAirFlowMethod] = 'DesignDay'
    system_data[:CoolingDesignAirFlowRate] = 0.0
    system_data[:HeatingDesignAirFlowMethod] = 'DesignDay'
    system_data[:HeatingDesignAirFlowRate] = 0.0
    system_data[:SystemOutdoorAirMethod] = 'ZoneSum'
    # Set outdoor air method to Standard62.1VentilationRateProcedure if ventilation efficiency is being applied
    system_data[:SystemOutdoorAirMethod] = 'Standard62.1VentilationRateProcedure' if self.fuel_type_set.apply_ventilation_efficiency
    system_data[:CentralCoolingDesignSupplyAirHumidityRatio] = 0.0085
    system_data[:CentralHeatingDesignSupplyAirHumidityRatio] = 0.0080
    system_data[:CentralCoolingDesignSupplyAirTemperature] = 13.0
    system_data[:CentralHeatingDesignSupplyAirTemperature] = 43.0
    system_data[:AllOutdoorAirinCooling] = true
    system_data[:AllOutdoorAirinHeating] = true
    system_data[:TypeofLoadtoSizeOn] = 'VentilationRequirement'
    system_data[:MinimumSystemAirFlowRatio] = 1.0
    system_data[:MinimumOutdoorDryBulbTemperatureforCompressorOperation] = -10.0
    # Zone data
    system_data[:system_supply_air_temperature] = 20.0
    system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference] = 11.0
    system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference] = 21.0
    system_data[:ZoneCoolingSizingFactor] = 1.1
    system_data[:ZoneHeatingSizingFactor] = 1.3

    # System Type 1: PTAC with no heating (unitary AC)
    # Zone baseboards, electric or hot water depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # PSZ to represent make-up air unit (if present)
    # This measure creates:
    # a PTAC  unit for each zone in the building; DX cooling coil
    # and heating coil that is always off
    # Baseboards ("Hot Water or "Electric") in zones connected to hot water loop
    # MAU is present if argument mau == true, not present if argument mau == false
    # MAU is PSZ; DX cooling
    # MAU heating coil: hot water coil or electric, depending on argument mau_heating_coil_type
    # mau_heating_coil_type choices are "Hot Water", "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOil#1","FuelOil#2","Coal","Diesel","Gasoline","OtherFuel1"

    # Some system parameters are set after system is set up; by applying method 'apply_hvac_efficiency_standard'

    always_on = model.alwaysOnDiscreteSchedule

    # define always off schedule for ptac heating coil
    always_off = BTAP::Resources::Schedules::StandardSchedules::ON_OFF.always_off(model)

    # Create MAU
    # TO DO: MAU sizing, characteristics (fan operation schedules, temperature setpoints, outdoor air, etc)

    if mau_type == true

      mau_air_loop = common_air_loop(model: model, system_data: system_data)
      mau_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

      # Setup heating and cooling coils
      mau_clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
      mau_clg_coil.setFuelType('Electricity')
      mau_clg_stage_1 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      mau_clg_stage_2 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      mau_clg_coil.addStage(mau_clg_stage_1)
      mau_clg_coil.addStage(mau_clg_stage_2)
      mau_clg_coil.setApplyPartLoadFractiontoSpeedsGreaterthan1(false)
      mau_htg_coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
      mau_htg_stage_1 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      mau_htg_coil.addStage(mau_htg_stage_1)
      mau_htg_stage_1.setNominalCapacity(0.001)
      if mau_heating_coil_type == 'Electric'
        mau_supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      elsif mau_heating_coil_type == 'Hot Water'
        mau_supplemental_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
        hw_loop.addDemandBranchForComponent(mau_supplemental_htg_coil)
      else
        raise("#{mau_heating_coil_type} is not a valid heating coil type.)")
      end

      # @todo other fuel-fired heating coil types? (not available in OpenStudio/E+ - may need to play with efficiency to mimic other fuel types)

      # This method will seem like an error in number of args..but this is due to swig voodoo.
      air_to_air_heatpump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(model,
                                                                                                mau_fan,
                                                                                                mau_htg_coil,
                                                                                                mau_clg_coil,
                                                                                                mau_supplemental_htg_coil)
      air_to_air_heatpump.setName("#{zones[0].name} ASHP")
      air_to_air_heatpump.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(system_data[:MinimumOutdoorDryBulbTemperatureforCompressorOperation])
      air_to_air_heatpump.setControllingZoneorThermostatLocation(zones[0])
      air_to_air_heatpump.setSupplyAirFanOperatingModeSchedule(always_on)
      air_to_air_heatpump.setNumberofSpeedsforHeating(1)
      air_to_air_heatpump.setNumberofSpeedsforCooling(2)

      # oa_controller
      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.autosizeMinimumOutdoorAirFlowRate

      # Set mechanical ventilation controller outdoor air to ZoneSum (used to be defaulted to ZoneSum but now should be
      # set explicitly)
      oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('ZoneSum')
      oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('Standard62.1VentilationRateProcedure') if self.fuel_type_set.apply_ventilation_efficiency

      # oa_system
      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

      # Add the components to the air loop
      # in order from closest to zone to furthest from zone
      supply_inlet_node = mau_air_loop.supplyInletNode
      air_to_air_heatpump.addToNode(supply_inlet_node)
      oa_system.addToNode(supply_inlet_node)

      # Add a setpoint manager to control the supply air temperature
      sat_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      sat_sch.setName('Makeup-Air Unit Supply Air Temp')
      sat_sch.defaultDaySchedule.setName('Makeup Air Unit Supply Air Temp Default')
      sat_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), system_data[:system_supply_air_temperature])
      setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, sat_sch)
      setpoint_mgr.addToNode(mau_air_loop.supplyOutletNode)
      # Create MAU
    end

    zones.each do |zone|
      # Zone sizing temperature difference
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperatureInputMethod('TemperatureDifference')
      sizing_zone.setZoneCoolingDesignSupplyAirTemperatureDifference(11.0)
      sizing_zone.setZoneHeatingDesignSupplyAirTemperatureInputMethod('TemperatureDifference')
      sizing_zone.setZoneHeatingDesignSupplyAirTemperatureDifference(21.0)
      sizing_zone.setZoneCoolingSizingFactor(1.1)
      sizing_zone.setZoneHeatingSizingFactor(1.3)
      sizing_zone.setDesignZoneAirDistributionEffectivenessinHeatingMode(0.8) if self.fuel_type_set.apply_ventilation_efficiency

      # Set up PTAC heating coil; apply always off schedule

      # htg_coil_elec = OpenStudio::Model::CoilHeatingElectric.new(model,always_on)
      zero_outdoor_air = true # flag to set outside air flow to zero
      add_ptac_dx_cooling(model, zone, zero_outdoor_air)

      # add zone baseboards
      add_zone_baseboards(baseboard_type: baseboard_type, hw_loop: hw_loop, model: model, zone: zone)

      #  # Create a diffuser and attach the zone/diffuser pair to the MAU air loop, if applicable
      if mau_type == true

        diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
        mau_air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
        # components for MAU
      end
      # of zone loop
    end
    return true
  end
end
