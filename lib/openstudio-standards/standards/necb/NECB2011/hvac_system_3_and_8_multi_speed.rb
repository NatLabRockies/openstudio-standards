class NECB2011
  # Some tests still require a simple way to set up a system without sizing.. so we are keeping the auto_zoner flag for this  method.
  def add_sys3and8_single_zone_packaged_rooftop_unit_with_baseboard_heating_multi_speed(model:,
                                                                                        zones:,
                                                                                        heating_coil_type:,
                                                                                        baseboard_type:,
                                                                                        hw_loop:,
                                                                                        new_auto_zoner: true)
    system_data = {}
    system_data[:name] = 'Sys_3_PSZ'
    system_data[:CentralCoolingDesignSupplyAirTemperature] = 13.0
    system_data[:CentralHeatingDesignSupplyAirTemperature] = 43.0
    system_data[:AllOutdoorAirinCooling] = false
    system_data[:AllOutdoorAirinHeating] = false
    system_data[:TypeofLoadtoSizeOn] = 'Sensible'
    system_data[:MinimumSystemAirFlowRatio] = 1.0

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
    system_data[:CentralCoolingDesignSupplyAirHumidityRatio] = 0.0085
    system_data[:CentralHeatingDesignSupplyAirHumidityRatio] = 0.0080

    # System 3 Zone data
    system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference] = 11.0
    system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference] = 21.0
    system_data[:SetpointManagerSingleZoneReheatSupplyTempMin] = 13.0
    system_data[:SetpointManagerSingleZoneReheatSupplyTempMax] = 43.0
    system_data[:ZoneDXCoolingSizingFactor] = 1.0
    system_data[:ZoneDXHeatingSizingFactor] = 1.3
    system_data[:ZoneCoolingSizingFactor] = 1.1
    system_data[:ZoneHeatingSizingFactor] = 1.3
    system_data[:MinimumOutdoorDryBulbTemperatureforCompressorOperation] = -10.0

    if new_auto_zoner == true
      # Create system airloop

      # Add Air Loop
      air_loop = add_system_3_and_8_airloop_multi_speed(heating_coil_type,
                                                        model,
                                                        system_data,
                                                        determine_control_zone(zones))
      # Add Zone equipment
      zones.each do |zone| # Zone sizing temperature difference
        sizing_zone = zone.sizingZone
        sizing_zone.setZoneCoolingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod])
        sizing_zone.setZoneCoolingDesignSupplyAirTemperatureDifference(system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference])
        sizing_zone.setZoneHeatingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod])
        sizing_zone.setZoneHeatingDesignSupplyAirTemperatureDifference(system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference])
        sizing_zone.setZoneCoolingSizingFactor(system_data[:ZoneCoolingSizingFactor])
        sizing_zone.setZoneHeatingSizingFactor(system_data[:ZoneHeatingSizingFactor])
        add_sys3_and_8_zone_equip(air_loop,
                                  baseboard_type,
                                  hw_loop,
                                  model,
                                  zone)
      end
      return true
    else
      zones.each do |zone|
        air_loop = add_system_3_and_8_airloop_multi_speed(heating_coil_type, model, system_data, zone, hw_loop)
        add_sys3_and_8_zone_equip(air_loop,
                                  baseboard_type,
                                  hw_loop,
                                  model,
                                  zone)
      end
      return true
    end
  end

  def add_system_3_and_8_airloop_multi_speed(heating_coil_type, model, system_data, control_zone, hw_loop)
    # System Type 3: PSZ-AC
    # This measure creates:
    # -a constant volume packaged single-zone A/C unit
    # for each zone in the building; DX cooling with
    # heating coil: fuel-fired or electric, depending on argument heating_coil_type
    # heating_coil_type choices are "Electric", "Gas", "DX"
    # zone baseboards: hot water or electric, depending on argument baseboard_type
    # baseboard_type choices are "Hot Water" or "Electric"
    # boiler_fueltype choices match OS choices for Boiler component fuel type, i.e.
    # "NaturalGas","Electricity","PropaneGas","FuelOilNo1","FuelOilNo2","Coal","Diesel","Gasoline","OtherFuel1"

    always_on = model.alwaysOnDiscreteSchedule
    air_loop = common_air_loop(model: model, system_data: system_data)
    air_loop.setName("#{system_data[:name]} #{control_zone.name}")

    # Zone sizing temperature difference
    sizing_zone = control_zone.sizingZone
    sizing_zone.setZoneCoolingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod])
    sizing_zone.setZoneCoolingDesignSupplyAirTemperatureDifference(system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference])
    sizing_zone.setZoneHeatingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod])
    sizing_zone.setZoneHeatingDesignSupplyAirTemperatureDifference(system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference])
    sizing_zone.setZoneCoolingSizingFactor(system_data[:ZoneCoolingSizingFactor])
    sizing_zone.setZoneHeatingSizingFactor(system_data[:ZoneHeatingSizingFactor])

    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

    # Setup heating and cooling coils
    if (heating_coil_type == 'Gas') || (heating_coil_type == 'Electric')
      clg_coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
      clg_coil.setFuelType('Electricity')
      clg_stage_1 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      clg_stage_2 = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      clg_coil.addStage(clg_stage_1)
      clg_coil.addStage(clg_stage_2)
      clg_coil.setApplyPartLoadFractiontoSpeedsGreaterthan1(false)
      htg_coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
      htg_stage_1 = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      htg_coil.addStage(htg_stage_1)
      if heating_coil_type == 'Gas'
        supplemental_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
        supplemental_htg_coil.setNominalCapacity(0.001)
      elsif heating_coil_type == 'Electric'
        supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
        htg_stage_1.setNominalCapacity(0.001)
      end
    # Single stage DX and Electric heating
    elsif heating_coil_type == 'DX'
      clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
      clg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(system_data[:MinimumOutdoorDryBulbTemperatureforCompressorOperation])
      htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
      supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
    else
      raise("#{heating_coil_type} is not a valid heating coil type.)")
    end

    # oa_controller
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate

    # Set mechanical ventilation controller outdoor air to ZoneSum (used to be defaulted to ZoneSum but now should be
    # set explicitly)
    oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('ZoneSum')

    # oa_system
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

    # Add the components to the air loop
    # in order from closest to zone to furthest from zone
    supply_inlet_node = air_loop.supplyInletNode

    if (heating_coil_type == 'Gas') || (heating_coil_type == 'Electric')
      # This method will seem like an error in number of args..but this is due to swig voodoo.
      air_to_air_heatpump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.new(model, fan, htg_coil, clg_coil, supplemental_htg_coil)
      air_to_air_heatpump.setControllingZoneorThermostatLocation(control_zone)
      air_to_air_heatpump.setNumberofSpeedsforHeating(1)
      air_to_air_heatpump.setNumberofSpeedsforCooling(2)
      air_to_air_heatpump.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(system_data[:MinimumOutdoorDryBulbTemperatureforCompressorOperation])
    elsif heating_coil_type == 'DX'
      # This method will seem like an error in number of args..but this is due to swig voodoo.
      air_to_air_heatpump = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(model, always_on, fan, htg_coil, clg_coil, supplemental_htg_coil)
      air_to_air_heatpump.setControllingZone(zone)
    end
    air_to_air_heatpump.setName("#{control_zone.name} ASHP")
    air_to_air_heatpump.setSupplyAirFanOperatingModeSchedule(always_on)
    air_to_air_heatpump.addToNode(supply_inlet_node)

    oa_system.addToNode(supply_inlet_node)

    # Add a setpoint manager single zone reheat to control the
    # supply air temperature based on the needs of this zone
    setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
    setpoint_mgr_single_zone_reheat.setControlZone(control_zone)
    setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(system_data[:SetpointManagerSingleZoneReheatSupplyTempMin])
    setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(system_data[:SetpointManagerSingleZoneReheatSupplyTempMax])
    setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

    return air_loop
  end
end
