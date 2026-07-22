class NECB2011
  def add_sys1_unitary_ac_baseboard_heating(model:,
                                            necb_reference_hp:false,
                                            necb_reference_hp_supp_fuel:'DefaultFuel',
                                            zones:,
                                            mau_type:,
                                            mau_heating_coil_type:,
                                            baseboard_type:,
                                            hw_loop:,
                                            multispeed: false)
    if multispeed
      add_sys1_unitary_ac_baseboard_heating_multi_speed(model: model,
                                                        zones: zones,
                                                        mau_type: mau_type,
                                                        mau_heating_coil_type: mau_heating_coil_type,
                                                        baseboard_type: baseboard_type,
                                                        hw_loop: hw_loop)
    else
      add_sys1_unitary_ac_baseboard_heating_single_speed(model: model,
                                                         necb_reference_hp: necb_reference_hp,
                                                         necb_reference_hp_supp_fuel: necb_reference_hp_supp_fuel,
                                                         zones: zones,
                                                         mau_type: mau_type,
                                                         mau_heating_coil_type: mau_heating_coil_type,
                                                         baseboard_type: baseboard_type,
                                                         hw_loop: hw_loop)
    end
  end

  def add_sys1_unitary_ac_baseboard_heating_single_speed(model:,
                                                         necb_reference_hp:false,
                                                         necb_reference_hp_supp_fuel:'DefaultFuel',
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
    system_data[:CentralCoolingDesignSupplyAirHumidityRatio] = 0.0085
    system_data[:CentralHeatingDesignSupplyAirHumidityRatio] = 0.0080
    system_data[:CentralCoolingDesignSupplyAirTemperature] = 13.0
    system_data[:CentralHeatingDesignSupplyAirTemperature] = 43.0
    system_data[:AllOutdoorAirinCooling] = true
    system_data[:AllOutdoorAirinHeating] = true
    # DOAS systems should always size on ventilation requirement, not total load
    system_data[:TypeofLoadtoSizeOn] = 'VentilationRequirement'
    system_data[:MinimumSystemAirFlowRatio] = 1.0
    # Zone Sizing data
    system_data[:system_supply_air_temperature] = 20.0
    system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference] = 11.0
    system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference] = 21.0
    system_data[:ZoneDXCoolingSizingFactor] = 1.0
    system_data[:ZoneDXHeatingSizingFactor] = 1.3
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
    # "NaturalGas","Electricity","PropaneGas","FuelOilNo1","FuelOilNo2","Coal","Diesel","Gasoline","OtherFuel1"

    # If reference_hp = true, NECB 8.4.4.13 Heat Pump System Type 1: CAV Packaged rooftop heat pump with
    # zone baseboard (electric or hot water depending on argument baseboard_type)

    # Some system parameters are set after system is set up; by applying method 'apply_hvac_efficiency_standard'

    always_on = model.alwaysOnDiscreteSchedule
    always_off = BTAP::Resources::Schedules::StandardSchedules::ON_OFF.always_off(model)

    # Create MAU
    # TO DO: MAU sizing, characteristics (fan operation schedules, temperature setpoints, outdoor air, etc)



    if mau_type == true
      mau_air_loop = common_air_loop(model: model, system_data: system_data)

      #if reference_hp
        # AirLoopHVACUnitaryHeatPumpAirToAir needs FanOnOff in order for the fan to turn off during off hours
      #  mau_fan = OpenStudio::Model::FanOnOff.new(model, always_on)
      #else
        mau_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
      #end
      # MAU Heating type selection.
      raise("Flag 'necb_reference_hp' is true while 'mau_heating_coil_type' is not set to type DX") if (necb_reference_hp && (mau_heating_coil_type != 'DX'))
      if mau_heating_coil_type == 'Electric' || mau_heating_coil_type == 'Electricity' || mau_heating_coil_type == 'FuelOilNo2' # electric coil
        mau_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      elsif  mau_heating_coil_type == 'Hot Water' || mau_heating_coil_type == 'HotWater'
        mau_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
        hw_loop.addDemandBranchForComponent(mau_htg_coil)
      elsif mau_heating_coil_type == 'DX'
        mau_htg_coil = add_onespeed_htg_DX_coil(model, always_on)
        mau_htg_coil.setName('CoilHeatingDXSingleSpeed_ashp')
      elsif mau_heating_coil_type == 'Gas' || mau_heating_coil_type == "NaturalGas"
        mau_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
      else
        raise('Invalid fuel type selected for mau heating coil')
      end

      # Set up Single Speed DX coil with
      mau_clg_coil = add_onespeed_DX_coil(model, always_on)
      mau_clg_coil.setName('CoilCoolingDXSingleSpeed_dx')
      mau_clg_coil.setName('CoilCoolingDXSingleSpeed_ashp') if necb_reference_hp

      # Set up OA system
      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.autosizeMinimumOutdoorAirFlowRate

      # Set mechanical ventilation controller outdoor air to ZoneSum (used to be defaulted to ZoneSum but now should be
      # set explicitly)
      oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('ZoneSum')

      oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

      # Add the components to the air loop
      # in order from closest to zone to furthest from zone
      supply_inlet_node = mau_air_loop.supplyInletNode
      mau_fan.addToNode(supply_inlet_node)
      if necb_reference_hp
        #create supplemental heating coil based on default regional fuel type
        if necb_reference_hp_supp_fuel == 'DefaultFuel'
          epw = OpenStudio::EpwFile.new(model.weatherFile.get.path.get)
          necb_reference_hp_supp_fuel = @standards_data['regional_fuel_use'].detect { |fuel_sources| fuel_sources['state_province_regions'].include?(epw.stateProvinceRegion) }['fueltype_set']
        end
        if necb_reference_hp_supp_fuel == 'NaturalGas' || necb_reference_hp_supp_fuel == 'Gas'
          supplemental_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
        elsif necb_reference_hp_supp_fuel == 'Electricity' || necb_reference_hp_supp_fuel == 'Electric' || necb_reference_hp_supp_fuel == 'FuelOilNo2'
          supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
        elsif necb_reference_hp_supp_fuel == 'Hot Water' || necb_reference_hp_supp_fuel == "HotWater"
          supplemental_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
          hw_loop.addDemandBranchForComponent(supplemental_htg_coil)
        else
          raise('Invalid fuel type selected for heat pump supplemental coil')
        end
        supplemental_htg_coil.addToNode(supply_inlet_node)
      end
      mau_htg_coil.addToNode(supply_inlet_node)
      mau_clg_coil.addToNode(supply_inlet_node)

      oa_system.addToNode(supply_inlet_node)

      # Add a setpoint manager to control the supply air temperature
      sat_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      sat_sch.setName('Makeup-Air Unit Supply Air Temp')
      sat_sch.defaultDaySchedule.setName('Makeup Air Unit Supply Air Temp Default')
      sat_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), system_data[:system_supply_air_temperature])
      setpoint_mgr = OpenStudio::Model::SetpointManagerScheduled.new(model, sat_sch)
      setpoint_mgr.addToNode(mau_air_loop.supplyOutletNode)
    end

    zones.each do |zone|
      # Zone sizing temperature difference
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod])
      sizing_zone.setZoneCoolingDesignSupplyAirTemperatureDifference(system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference])
      sizing_zone.setZoneHeatingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod])
      sizing_zone.setZoneHeatingDesignSupplyAirTemperatureDifference(system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference])
      sizing_zone.setZoneCoolingSizingFactor(system_data[:ZoneCoolingSizingFactor])
      sizing_zone.setZoneHeatingSizingFactor(system_data[:ZoneHeatingSizingFactor])

      # Create a PTAC for each zone:
      # PTAC DX Cooling with electric heating coil; electric heating coil is always off
      # TO DO: need to apply this system to space types:
      # (1) data processing area: control room, data centre
      # when cooling capacity <= 20kW and
      # (2) residential/accommodation: murb, hotel/motel guest room
      # when building/space heated only (this as per NECB; apply to
      # all for initial work? CAN-QUEST limitation)

      # TO DO: PTAC characteristics: sizing, fan schedules, temperature setpoints, interaction with MAU

      # htg_coil_elec = OpenStudio::Model::CoilHeatingElectric.new(model,always_on)
      zero_outdoor_air = true # flag to set outside air flow to 0.0
      # Create PTAC for all systems - DOAS handles outdoor air, PTAC handles comfort
      add_ptac_dx_cooling(model, zone, zero_outdoor_air)

      # add zone baseboards
      add_zone_baseboards(baseboard_type: baseboard_type,
                          hw_loop: hw_loop,
                          model: model,
                          zone: zone)

      #  # Create a diffuser and attach the zone/diffuser pair to the MAU air loop, if applicable
      # Heat pump systems use PTAC only - no CAV terminals created

      if mau_type == true
        diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
        mau_air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
        # components for MAU
      end
      # of zone loop
    end
    if mau_type
      sys_name_pars = {}
      sys_name_pars['sys_hr'] = 'none'
      sys_name_pars['sys_clg'] = 'dx'
      sys_name_pars['sys_clg'] = 'ashp' if necb_reference_hp
      sys_name_pars['sys_htg'] = mau_heating_coil_type
      sys_name_pars['sys_htg'] = 'ashp' if necb_reference_hp
      sys_name_pars['sys_htg'] = 'ashp>c-g' if (necb_reference_hp && (necb_reference_hp_supp_fuel == "NaturalGas" || necb_reference_hp_supp_fuel == "Gas"))
      sys_name_pars['sys_htg'] = 'ashp>c-e' if necb_reference_hp && necb_reference_hp_supp_fuel == "Electricity"
      sys_name_pars['sys_htg'] = 'ashp>c-hw' if necb_reference_hp && (necb_reference_hp_supp_fuel == "Hot Water" || necb_reference_hp_supp_fuel == "HotWater")
      sys_name_pars['sys_sf'] = 'cv'
      sys_name_pars['zone_htg'] = baseboard_type
      # All systems use PTAC for zone cooling and DOAS for outdoor air
      sys_name_pars['zone_clg'] = 'ptac'
      sys_oa = 'doas'
      sys_name_pars['sys_rf'] = 'none'
      return assign_base_sys_name(air_loop: mau_air_loop,
                           sys_abbr: 'sys_1',
                           sys_oa: sys_oa,
                           sys_name_pars: sys_name_pars)
    end

    return true
  end
end
