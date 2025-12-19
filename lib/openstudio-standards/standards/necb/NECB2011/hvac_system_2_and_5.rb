class NECB2011
  def add_sys2_FPFC_sys5_TPFC(model:,
                              zones:,
                              chiller_type:,
                              fan_coil_type:,
                              mau_cooling_type:,
                              hw_loop:)

    # System 2 AHU data
    system_data = {}
    system_data[:name] = 'Sys_2_Make-up air unit'
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
    system_data[:CentralHeatingDesignSupplyAirTemperature] = 13.1
    system_data[:AllOutdoorAirinCooling] = false
    system_data[:AllOutdoorAirinHeating] = false
    system_data[:TypeofLoadtoSizeOn] = 'Sensible'
    system_data[:SetpointManagerSingleZoneReheatSupplyTempMax] = 13.0
    system_data[:SetpointManagerSingleZoneReheatSupplyTempMin] = 13.1
    system_data[:MinimumSystemAirFlowRatio] = 1.0

    # System 2 Zone data
    system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference] = 11.0
    system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod] = 'TemperatureDifference'
    system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference] = 21.0
    system_data[:ZoneCoolingSizingFactor] = 1.1
    system_data[:ZoneHeatingSizingFactor] = 1.3

    # System Type 2: FPFC or System 5: TPFC
    # This measure creates:
    # -a four pipe or a two pipe fan coil unit for each zone in the building;
    # -a make up air-unit to provide ventilation to each zone;
    # -a heating loop, cooling loop and condenser loop to serve four pipe fan coil units
    # Arguments:
    #   boiler_fueltype: "NaturalGas","Electricity","PropaneGas","FuelOilNo1","FuelOilNO2","Coal","Diesel","Gasoline","OtherFuel1"
    #   chiller_type: "Scroll";"Centrifugal";"Rotary Screw";"Reciprocating"
    #   mua_cooling_type: make-up air unit cooling type "DX";"Hydronic"
    #   fan_coil_type options are "TPFC" or "FPFC"

    # @todo Add arguments as needed when the sizing routine is finalized. For example we will need to know the
    # required size of the boilers to decide on how many units are needed based on NECB rules.

    always_on = model.alwaysOnDiscreteSchedule

    # schedule for two-pipe fan coil operation. 3 seasons for heating/cooling.
    tpfc_clg_availability_sch, tpfc_htg_availability_sch = create_heating_cooling_on_off_availability_schedule(model)

    # Create a chilled water loop
    chw_loop = OpenStudio::Model::PlantLoop.new(model)
    chiller1, chiller2 = setup_chw_loop_with_components(model, chw_loop, chiller_type)

    # Create a condenser Loop
    cw_loop = OpenStudio::Model::PlantLoop.new(model)
    ctower = setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)

    # Set up make-up air unit for ventilation
    # TO DO: Need to investigate characteristics of make-up air unit for NECB reference
    # and define them here

    air_loop = mau_air_loop = common_air_loop(model: model, system_data: system_data)
    air_loop.setName(system_data[:name])

    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

    # Assume direct-fired gas heating coil for now; need to add logic
    # to set up hydronic or electric coil depending on proposed?

    # Get Heating Coil from heating coil type sys2.  If set to DX use NECB reference HP supplemental fuel.
    # TODO: If set to DX incorporate DX heating coil and supplemental heating type.
    #if self.fuel_type_set.heating_coil_type_sys2 == "DX"
    #  htg_coil_fuel = self.fuel_type_set.necb_reference_hp_supp_fuel
    #else
    #  htg_coil_fuel = self.fuel_type_set.heating_coil_type_sys2
    #end
    htg_coil_fuel = self.fuel_type_set.heating_coil_type_sys2

    case htg_coil_fuel
    when 'Electric', 'Electricity', 'FuelOilNo2' # Electric Coil
      htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
    when 'Gas', 'NaturalGas'# Natural Gas Coil
      htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
    when 'Hot Water', 'HotWater' # Hot Water Coil
      htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
      hw_loop.addDemandBranchForComponent(htg_coil)
    when 'DX'
      htg_coil = add_onespeed_htg_DX_coil(model, always_on)
      htg_coil.setName('CoilHeatingDXSingleSpeed_ashp')
    else # Default to Natural Gas Coil
      htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
    end

    if htg_coil_fuel == 'DX'
      supplemental_htg_fuel = self.fuel_type_set.necb_reference_hp_supp_fuel
      case supplemental_htg_fuel
      when 'Electric', 'Electricity', 'FuelOilNo2'
        supp_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      when 'Gas', 'NaturalGas'
        supp_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      when 'Hot Water', 'HotWater'
        supp_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
        hw_loop.addDemandBranchForComponent(supp_htg_coil)
      else
        supp_htg_coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
      end
    end
    # Add DX or hydronic cooling coil
    if mau_cooling_type == 'DX'
      clg_coil = add_onespeed_DX_coil(model, tpfc_clg_availability_sch)
      clg_coil.setName('CoilCoolingDXSingleSpeed_dx')
    elsif mau_cooling_type == 'Hydronic' || mau_cooling_type == 'Hot Water' || mau_cooling_type == 'HotWater'
      clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, tpfc_clg_availability_sch)
      chw_loop.addDemandBranchForComponent(clg_coil)
    end

    # does MAU have an economizer?
    oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
    oa_controller.autosizeMinimumOutdoorAirFlowRate

    # Set mechanical ventilation controller outdoor air to ZoneSum (used to be defaulted to ZoneSum but now should be
    # set explicitly)
    oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('ZoneSum')

    # oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model,oa_controller)
    oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)

    # Add the components to the air loop
    # in order from closest to zone to furthest from zone
    supply_inlet_node = air_loop.supplyInletNode
    fan.addToNode(supply_inlet_node)
    supp_htg_coil.addToNode(supply_inlet_node) unless supp_htg_coil.nil?
    htg_coil.addToNode(supply_inlet_node)
    clg_coil.addToNode(supply_inlet_node)
    oa_system.addToNode(supply_inlet_node)

    # Add a setpoint manager single zone reheat to control the
    # supply air temperature based on the needs of default zone (OpenStudio picks one)
    # TO DO: need to have method to pick appropriate control zone?

    setpoint_mgr_single_zone_reheat = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
    setpoint_mgr_single_zone_reheat.setMinimumSupplyAirTemperature(system_data[:SetpointManagerSingleZoneReheatSupplyTempMin])
    setpoint_mgr_single_zone_reheat.setMaximumSupplyAirTemperature(system_data[:SetpointManagerSingleZoneReheatSupplyTempMax])
    setpoint_mgr_single_zone_reheat.addToNode(air_loop.supplyOutletNode)

    # Set up zonal FC (ZoneHVAC,cooling coil, heating coil, fan) in each zone
    zones.each do |zone|
      # Zone sizing temperature difference
      sizing_zone = zone.sizingZone
      sizing_zone.setZoneCoolingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneCoolingDesignSupplyAirTemperatureInputMethod])
      sizing_zone.setZoneCoolingDesignSupplyAirTemperatureDifference(system_data[:ZoneCoolingDesignSupplyAirTemperatureDifference])
      sizing_zone.setZoneHeatingDesignSupplyAirTemperatureInputMethod(system_data[:ZoneHeatingDesignSupplyAirTemperatureInputMethod])
      sizing_zone.setZoneHeatingDesignSupplyAirTemperatureDifference(system_data[:ZoneHeatingDesignSupplyAirTemperatureDifference])
      sizing_zone.setZoneCoolingSizingFactor(system_data[:ZoneCoolingSizingFactor])
      sizing_zone.setZoneHeatingSizingFactor(system_data[:ZoneHeatingSizingFactor])

      # fc supply fan
      fc_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)

      if fan_coil_type == 'FPFC'
        # heating coil
        fc_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)

        # cooling coil
        fc_clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, always_on)
      elsif fan_coil_type == 'TPFC'
        # heating coil
        fc_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, tpfc_htg_availability_sch)

        # cooling coil
        fc_clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, tpfc_clg_availability_sch)
      end

      # connect heating coil to hot water loop and cooling coil to chw loop.
      hw_loop.addDemandBranchForComponent(fc_htg_coil)
      chw_loop.addDemandBranchForComponent(fc_clg_coil)

      # add connections to FPFC.
      # This method will seem like an error in number of args..but this is due to swig voodoo.
      zone_fc = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, always_on, fc_fan, fc_clg_coil, fc_htg_coil)
      zone_fc.addToThermalZone(zone)

      # Create a diffuser and attach the zone/diffuser pair to the air loop (make-up air unit)
      diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
      # zone loop
    end
    sys_abbr = 'sys_2'
    sys_abbr = 'sys_5' if fan_coil_type == 'TPFC'
    sys_name_pars = {}
    sys_name_pars['sys_hr'] = 'none'
    sys_name_pars['sys_clg'] = 'Hydronic' if mau_cooling_type == 'Hydronic' || mau_cooling_type == 'Hot Water' || mau_cooling_type == 'HotWater'
    sys_name_pars['sys_clg'] = 'DX' if mau_cooling_type == 'DX' && htg_coil_fuel != 'DX'
    sys_name_pars['sys_clg'] = 'ashp' if mau_cooling_type == 'DX' && htg_coil_fuel == 'DX'
    sys_name_pars['sys_htg'] = 'g' if (htg_coil_fuel == 'Gas' || htg_coil_fuel == 'NaturalGas')
    sys_name_pars['sys_htg'] = 'e' if (htg_coil_fuel == 'Electric' || htg_coil_fuel == 'Electricity' || htg_coil_fuel == 'FuelOilNo2')
    sys_name_pars['sys_htg'] = 'ashp>c-g' if (htg_coil_fuel == 'DX' && (supplemental_htg_fuel == "NaturalGas" || supplemental_htg_fuel == "Gas"))
    sys_name_pars['sys_htg'] = 'ashp>c-e' if (htg_coil_fuel == 'DX' && (supplemental_htg_fuel == "Electricity" || supplemental_htg_fuel == "Electric" || supplemental_htg_fuel == "FuelOilNo2"))
    sys_name_pars['sys_htg'] = 'ashp>c-hw' if (htg_coil_fuel == 'DX' && (supplemental_htg_fuel == "Hot Water" || supplemental_htg_fuel == "HotWater"))
    sys_name_pars['sys_sf'] = 'cv'
    sys_name_pars['zone_htg'] = fan_coil_type
    sys_name_pars['zone_clg'] = fan_coil_type
    sys_name_pars['sys_rf'] = 'none'
    return assign_base_sys_name(air_loop: mau_air_loop,
                         sys_abbr: sys_abbr,
                         sys_oa: 'doas',
                         sys_name_pars: sys_name_pars)
  end
end
