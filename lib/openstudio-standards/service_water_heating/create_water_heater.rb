module OpenstudioStandards
  # The ServiceWaterHeating module provides methods to create, modify, and get information about service water heating
  module ServiceWaterHeating
    # @!group Create Water Heater
    # Methods to add service water heaters

    # Creates a water heater and attaches it to the supplied service water heating loop.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param water_heater_capacity [Double] water heater capacity, in W. Defaults to 58.6 kW / 200 kBtu/hr
    # @param water_heater_volume [Double] water heater volume, in m^3. Defaults to 0.378 m^3 / 100 gal
    # @param water_heater_fuel [String] water heating fuel. Valid choices are 'NaturalGas', 'Electricity', or 'HeatPump'
    # @param on_cycle_parasitic_fuel_consumption_rate [Double] water heater on cycle parasitic fuel consumption rate, in W
    # @param off_cycle_parasitic_fuel_consumption_rate [Double] water heater off cycle parasitic fuel consumption rate, in W
    # @param service_water_temperature [Double] water heater temperature, in degrees C. Default is 60 C / 140 F.
    # @param service_water_temperature_schedule [OpenStudio::Model::Schedule] the service water heating schedule.
    #   If nil, will be defaulted to a constant temperature schedule based on the service_water_temperature
    # @param set_peak_use_flowrate [Boolean] if true, the peak flow rate and flow rate schedule will be set.
    # @param peak_flowrate [Double] peak flow rate in m^3/s
    # @param flowrate_schedule [OpenStudio::Model::Schedule] the flow rate fraction schedule
    # @param water_heater_thermal_zone [OpenStudio::Model::ThermalZone] Thermal zone for ambient heat loss.
    #   If nil, will assume 71.6 F / 22 C ambient air temperature.
    # @param number_of_water_heaters [Integer] the number of water heaters represented by the capacity and volume inputs.
    #   Used to modify efficiencies for water heaters based on individual component size while avoiding having to model
    #   lots of individual water heaters (for runtime sake).
    # @param service_water_loop [OpenStudio::Model::PlantLoop] if provided, add the water heater to this loop
    # @return [OpenStudio::Model::WaterHeaterMixed] OpenStudio WaterHeaterMixed object
    def self.create_water_heater(model,
                                 water_heater_capacity: nil,
                                 water_heater_volume: nil,
                                 water_heater_fuel: 'Electricity',
                                 on_cycle_parasitic_fuel_consumption_rate: 0.0,
                                 off_cycle_parasitic_fuel_consumption_rate: 0.0,
                                 service_water_temperature: 60.0,
                                 service_water_temperature_schedule: nil,
                                 set_peak_use_flowrate: false,
                                 peak_flowrate: nil,
                                 flowrate_schedule: nil,
                                 water_heater_thermal_zone: nil,
                                 number_of_water_heaters: 1,
                                 service_water_loop: nil)
      # create water heater object
      # @todo Standards - Change water heater methodology to follow 'Model Enhancements Appendix A.'
      water_heater = OpenStudio::Model::WaterHeaterMixed.new(model)

      # default water heater capacity if nil
      if water_heater_capacity.nil?
        water_heater_capacity = OpenStudio.convert(200.0, 'kBtu/hr', 'W').get
      end
      water_heater_capacity_kbtu_per_hr = OpenStudio.convert(water_heater_capacity, 'W', 'kBtu/hr').get
      water_heater.setHeaterMaximumCapacity(water_heater_capacity)

      # default water heater volume if nil
      if water_heater_volume.nil?
        water_heater_volume = OpenStudio.convert(100.0, 'gal', 'm^3').get
      end
      water_heater_volume_gal = OpenStudio.convert(water_heater_volume, 'm^3', 'gal').get
      water_heater.setTankVolume(water_heater_volume)
      water_heating_sizing = water_heater.waterHeaterSizing

      # set the water heater fuel
      case water_heater_fuel
      when 'Natural Gas', 'NaturalGas', 'Gas'
        water_heater.setHeaterFuelType('Gas')
        water_heater.setHeaterThermalEfficiency(0.78)
        water_heater.setOnCycleParasiticFuelConsumptionRate(on_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOffCycleParasiticFuelConsumptionRate(off_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOnCycleParasiticFuelType('Gas')
        water_heater.setOffCycleParasiticFuelType('Gas')
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(6.0)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(6.0)
        # assume 0.5 hour recovery temperature for natural gas water heaters
        water_heating_sizing.setDesignMode('PeakDraw')
        water_heating_sizing.setTimeforTankRecovery(0.5)
      when 'Electricity', 'Electric', 'Elec'
        water_heater.setHeaterFuelType('Electricity')
        water_heater.setHeaterThermalEfficiency(1.0)
        water_heater.setOnCycleParasiticFuelConsumptionRate(on_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOffCycleParasiticFuelConsumptionRate(off_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOnCycleParasiticFuelType('Electricity')
        water_heater.setOffCycleParasiticFuelType('Electricity')
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(1.053)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(1.053)
        # assume 1.0 hour recovery temperature for electric water heaters
        water_heating_sizing.setDesignMode('PeakDraw')
        water_heating_sizing.setTimeforTankRecovery(1.0)
      when 'FuelOilNo2'
        water_heater.setHeaterFuelType('FuelOilNo2')
        water_heater.setHeaterThermalEfficiency(0.78)
        water_heater.setOnCycleParasiticFuelConsumptionRate(on_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOffCycleParasiticFuelConsumptionRate(off_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOnCycleParasiticFuelType('FuelOilNo2')
        water_heater.setOffCycleParasiticFuelType('FuelOilNo2')
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(6.0)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(6.0)
        # assume 0.5 hour recovery temperature for fuel oil water heaters
        water_heating_sizing.setDesignMode('PeakDraw')
        water_heating_sizing.setTimeforTankRecovery(0.5)
      when 'HeatPump', 'SimpleHeatPump'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ServiceWaterHeating', 'Simple workaround to represent heat pump water heaters without incurring significant runtime penalty associated with using correct objects.')
        # Make a part-load efficiency modifier curve with a value above 1, which is multiplied by the nominal efficiency of 100% to represent the COP of a HPWH.
        # @todo could make this workaround better by using EMS to modify this curve output in realtime based on the OA temperature.
        hpwh_cop = 2.8
        water_heater.setHeaterFuelType('Electricity')
        water_heater.setHeaterThermalEfficiency(1.0)
        eff_f_of_plr = OpenStudio::Model::CurveCubic.new(model)
        eff_f_of_plr.setName("HPWH_COP_#{hpwh_cop}")
        eff_f_of_plr.setCoefficient1Constant(hpwh_cop)
        eff_f_of_plr.setCoefficient2x(0.0)
        eff_f_of_plr.setCoefficient3xPOW2(0.0)
        eff_f_of_plr.setCoefficient4xPOW3(0.0)
        eff_f_of_plr.setMinimumValueofx(0.0)
        eff_f_of_plr.setMaximumValueofx(1.0)
        water_heater.setPartLoadFactorCurve(eff_f_of_plr)
        water_heater.setOnCycleParasiticFuelConsumptionRate(on_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOffCycleParasiticFuelConsumptionRate(off_cycle_parasitic_fuel_consumption_rate)
        water_heater.setOnCycleParasiticFuelType('Electricity')
        water_heater.setOffCycleParasiticFuelType('Electricity')
        water_heater.setOffCycleLossCoefficienttoAmbientTemperature(1.053)
        water_heater.setOnCycleLossCoefficienttoAmbientTemperature(1.053)
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.ServiceWaterHeating', "#{water_heater_fuel} is not a valid water heater fuel.  Valid choices are NaturalGas, Electricity, and HeatPump.")
      end

      # set water temperature properties
      water_heater.setDeadbandTemperatureDifference(2.0)
      water_heater.setDeadbandTemperatureDifference(OpenStudio.convert(3.6, 'R', 'K').get)
      water_heater.setHeaterControlType('Cycle')
      water_heater.setOffCycleParasiticHeatFractiontoTank(0.8)
      water_heater.setIndirectWaterHeatingRecoveryTime(1.5) # 1.5hrs

      # create service water temperature schedule based on the service_water_temperature if none provided
      if service_water_temperature_schedule.nil?
        swh_temp_c = service_water_temperature
        swh_temp_f = OpenStudio.convert(swh_temp_c, 'C', 'F').get
        service_water_temperature_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                             swh_temp_c,
                                                                                                             name: "Service Water Loop Temp - #{swh_temp_f.round}F",
                                                                                                             schedule_type_limit: 'Temperature')
      end
      water_heater.setMaximumTemperatureLimit(service_water_temperature)
      water_heater.setSetpointTemperatureSchedule(service_water_temperature_schedule)

      # set peak flow rate characteristics
      if set_peak_use_flowrate
        water_heater.setPeakUseFlowRate(peak_flowrate) unless peak_flowrate.nil?
        water_heater.setUseFlowRateFractionSchedule(flowrate_schedule) unless flowrate_schedule.nil?
      end

      # set the water heater ambient conditions
      if water_heater_thermal_zone.nil?
        # assume the water heater is indoors at 71.6F / 22C
        indoor_temp_f = 71.6
        indoor_temp_c = OpenStudio.convert(indoor_temp_f, 'F', 'C').get
        default_water_heater_ambient_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                                indoor_temp_c,
                                                                                                                name: "Water Heater Ambient Temp Schedule #{indoor_temp_f}F",
                                                                                                                schedule_type_limit: 'Temperature')
        water_heater.setAmbientTemperatureIndicator('Schedule')
        water_heater.setAmbientTemperatureSchedule(default_water_heater_ambient_temp_sch)
        water_heater.resetAmbientTemperatureThermalZone
      else
        water_heater.setAmbientTemperatureIndicator('ThermalZone')
        water_heater.setAmbientTemperatureThermalZone(water_heater_thermal_zone)
        water_heater.resetAmbientTemperatureSchedule
      end

      # assign a quantity to the water heater if it represents multiple water heaters
      if number_of_water_heaters > 1
        water_heater.setName("#{number_of_water_heaters}X #{(water_heater_volume_gal / number_of_water_heaters).round}gal #{water_heater_fuel} Water Heater - #{(water_heater_capacity_kbtu_per_hr / number_of_water_heaters).round}kBtu/hr")
        water_heater.additionalProperties.setFeature('component_quantity', number_of_water_heaters)
      else
        water_heater.setName("#{water_heater_volume_gal.round}gal #{water_heater_fuel} Water Heater - #{water_heater_capacity_kbtu_per_hr.round}kBtu/hr")
      end

      # add the water heater to the service water loop if provided
      unless service_water_loop.nil?
        service_water_loop.addSupplyBranchForComponent(water_heater)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Added water heater called #{water_heater.name}")

      return water_heater
    end

    # Creates a heatpump water heater and attaches it to the supplied service water heating loop.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param heat_pump_type [String] valid option are 'WrappedCondenser' or 'PumpedCondenser' (default).
    #   The 'WrappedCondenser' uses a WaterHeaterStratified tank, 'PumpedCondenser' uses a WaterHeaterMixed tank.
    # @param water_heater_capacity [Double] water heater capacity, in W. Defaults to 500 W / 3.41 kBtu/hr
    # @param water_heater_volume [Double] water heater volume, in m^3. Defaults to 0.303 m^3 / 80 gal
    # @param coefficient_of_performance [Double] rated coefficient_of_performance
    # @param electric_backup_capacity [Double] electric heating backup capacity, in W. Default is 4500 W.
    # @param on_cycle_parasitic_fuel_consumption_rate [Double] water heater on cycle parasitic fuel consumption rate, in W
    # @param off_cycle_parasitic_fuel_consumption_rate [Double] water heater off cycle parasitic fuel consumption rate, in W
    # @param service_water_temperature [Double] water heater temperature, in degrees C. Default is 51.67 C / 125 F.
    # @param service_water_temperature_schedule [OpenStudio::Model::Schedule] the service water heating schedule.
    #   If nil, will be defaulted to a constant temperature schedule based on the service_water_temperature
    # @param set_peak_use_flowrate [Boolean] if true, the peak flow rate and flow rate schedule will be set.
    # @param peak_flowrate [Double] peak flow rate in m^3/s
    # @param flowrate_schedule [OpenStudio::Model::Schedule] the flow rate fraction schedule
    # @param water_heater_thermal_zone [OpenStudio::Model::ThermalZone] Thermal zone for ambient heat loss.
    #   If nil, will assume 71.6 F / 22 C ambient air temperature.
    # @param service_water_loop [OpenStudio::Model::PlantLoop] if provided, add the water heater to this loop
    # @param use_ems_control [Boolean] if true, use ems control logic if using a 'WrappedCondenser' style HPWH.
    # @return [OpenStudio::Model::WaterHeaterMixed] OpenStudio WaterHeaterMixed object
    def self.create_heatpump_water_heater(model,
                                          heat_pump_type: 'PumpedCondenser',
                                          water_heater_capacity: 500.0,
                                          water_heater_volume: OpenStudio.convert(80.0, 'gal', 'm^3').get,
                                          coefficient_of_performance: 2.8,
                                          electric_backup_capacity: 4500.0,
                                          on_cycle_parasitic_fuel_consumption_rate: 0.0,
                                          off_cycle_parasitic_fuel_consumption_rate: 0.0,
                                          service_water_temperature: OpenStudio.convert(125.0, 'F', 'C').get,
                                          service_water_temperature_schedule: nil,
                                          set_peak_use_flowrate: false,
                                          peak_flowrate: nil,
                                          flowrate_schedule: nil,
                                          water_heater_thermal_zone: nil,
                                          service_water_loop: nil,
                                          use_ems_control: false)
      # create heat pump water heater
      if heat_pump_type == 'WrappedCondenser'
        hpwh = OpenStudio::Model::WaterHeaterHeatPumpWrappedCondenser.new(model)
      elsif heat_pump_type == 'PumpedCondenser'
        hpwh = OpenStudio::Model::WaterHeaterHeatPump.new(model)
      end

      # calculate tank height and radius
      water_heater_capacity_kbtu_per_hr = OpenStudio.convert(water_heater_capacity, 'W', 'kBtu/hr').get
      hpwh_vol_gal = OpenStudio.convert(water_heater_volume, 'm^3', 'gal').get
      tank_height = (0.0188 * hpwh_vol_gal) + 0.0935 # linear relationship that gets GE height at 50 gal and AO Smith height at 80 gal
      tank_radius = (0.9 * water_heater_volume / (Math::PI * tank_height))**0.5
      tank_surface_area = 2.0 * Math::PI * tank_radius * (tank_radius + tank_height)
      tank_ua = 3.9 # default ua assumption
      u_tank = (5.678 * tank_ua) / OpenStudio.convert(tank_surface_area, 'm^2', 'ft^2').get
      hpwh.setName("#{hpwh_vol_gal.round}gal Heat Pump Water Heater - #{water_heater_capacity_kbtu_per_hr.round(0)}kBtu/hr")

      # set min/max HPWH operating temperature limit
      hpwh_op_min_temp_c = OpenStudio.convert(45.0, 'F', 'C').get
      hpwh_op_max_temp_c = OpenStudio.convert(120.0, 'F', 'C').get

      if heat_pump_type == 'WrappedCondenser'
        hpwh.setMinimumInletAirTemperatureforCompressorOperation(hpwh_op_min_temp_c)
        hpwh.setMaximumInletAirTemperatureforCompressorOperation(hpwh_op_max_temp_c)
        # set sensor heights
        if hpwh_vol_gal <= 50.0
          hpwh.setDeadBandTemperatureDifference(0.5)
          h_ue = (1 - (3.5 / 12.0)) * tank_height # in the 4th node of the tank (counting from top)
          h_le = (1 - (10.5 / 12.0)) * tank_height # in the 11th node of the tank (counting from top)
          h_condtop = (1 - (5.5 / 12.0)) * tank_height # in the 6th node of the tank (counting from top)
          h_condbot = (1 - (10.99 / 12.0)) * tank_height # in the 11th node of the tank
          h_hpctrl = (1 - (2.5 / 12.0)) * tank_height # in the 3rd node of the tank
          hpwh.setControlSensor1HeightInStratifiedTank(h_hpctrl)
          hpwh.setControlSensor1Weight(1.0)
          hpwh.setControlSensor2HeightInStratifiedTank(h_hpctrl)
        else
          hpwh.setDeadBandTemperatureDifference(3.89)
          h_ue = (1 - (3.5 / 12.0)) * tank_height # in the 3rd node of the tank (counting from top)
          h_le = (1 - (9.5 / 12.0)) * tank_height # in the 10th node of the tank (counting from top)
          h_condtop = (1 - (5.5 / 12.0)) * tank_height # in the 6th node of the tank (counting from top)
          h_condbot = 0.01 # bottom node
          h_hpctrl_up = (1 - (2.5 / 12.0)) * tank_height # in the 3rd node of the tank
          h_hpctrl_low = (1 - (8.5 / 12.0)) * tank_height # in the 9th node of the tank
          hpwh.setControlSensor1HeightInStratifiedTank(h_hpctrl_up)
          hpwh.setControlSensor1Weight(0.75)
          hpwh.setControlSensor2HeightInStratifiedTank(h_hpctrl_low)
        end
        hpwh.setCondenserBottomLocation(h_condbot)
        hpwh.setCondenserTopLocation(h_condtop)
        hpwh.setTankElementControlLogic('MutuallyExclusive')
        hpwh.autocalculateEvaporatorAirFlowRate
      elsif heat_pump_type == 'PumpedCondenser'
        hpwh.setDeadBandTemperatureDifference(3.89)
        hpwh.autosizeEvaporatorAirFlowRate
      end

      # set heat pump water heater properties
      hpwh.setFanPlacement('DrawThrough')
      hpwh.setOnCycleParasiticElectricLoad(0.0)
      hpwh.setOffCycleParasiticElectricLoad(0.0)
      hpwh.setParasiticHeatRejectionLocation('Outdoors')

      # set temperature setpoint schedule
      if service_water_temperature_schedule.nil?
        # service water heating loop controls
        swh_temp_c = service_water_temperature
        swh_temp_f = OpenStudio.convert(swh_temp_c, 'C', 'F').get
        swh_delta_t_r = 9.0 # 9F delta-T
        swh_temp_c = OpenStudio.convert(swh_temp_f, 'F', 'C').get
        swh_delta_t_k = OpenStudio.convert(swh_delta_t_r, 'R', 'K').get
        service_water_temperature_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                             swh_temp_c,
                                                                                                             name: "Heat Pump Water Heater Temp - #{swh_temp_f.round}F",
                                                                                                             schedule_type_limit: 'Temperature')
      end
      hpwh.setCompressorSetpointTemperatureSchedule(service_water_temperature_schedule)

      # coil curves
      hpwh_cap = OpenStudio::Model::CurveBiquadratic.new(model)
      hpwh_cap.setName('HPWH-Cap-fT')
      hpwh_cap.setCoefficient1Constant(0.563)
      hpwh_cap.setCoefficient2x(0.0437)
      hpwh_cap.setCoefficient3xPOW2(0.000039)
      hpwh_cap.setCoefficient4y(0.0055)
      hpwh_cap.setCoefficient5yPOW2(-0.000148)
      hpwh_cap.setCoefficient6xTIMESY(-0.000145)
      hpwh_cap.setMinimumValueofx(0.0)
      hpwh_cap.setMaximumValueofx(100.0)
      hpwh_cap.setMinimumValueofy(0.0)
      hpwh_cap.setMaximumValueofy(100.0)

      hpwh_cop = OpenStudio::Model::CurveBiquadratic.new(model)
      hpwh_cop.setName('HPWH-COP-fT')
      hpwh_cop.setCoefficient1Constant(1.1332)
      hpwh_cop.setCoefficient2x(0.063)
      hpwh_cop.setCoefficient3xPOW2(-0.0000979)
      hpwh_cop.setCoefficient4y(-0.00972)
      hpwh_cop.setCoefficient5yPOW2(-0.0000214)
      hpwh_cop.setCoefficient6xTIMESY(-0.000686)
      hpwh_cop.setMinimumValueofx(0.0)
      hpwh_cop.setMaximumValueofx(100.0)
      hpwh_cop.setMinimumValueofy(0.0)
      hpwh_cop.setMaximumValueofy(100.0)

      # create DX coil object
      if heat_pump_type == 'WrappedCondenser'
        coil = hpwh.dXCoil.to_CoilWaterHeatingAirToWaterHeatPumpWrapped.get
        coil.setRatedCondenserWaterTemperature(48.89)
        coil.autocalculateRatedEvaporatorAirFlowRate
      elsif heat_pump_type == 'PumpedCondenser'
        coil = hpwh.dXCoil.to_CoilWaterHeatingAirToWaterHeatPump.get
        coil.autosizeRatedEvaporatorAirFlowRate
      end

      # set coil properties
      coil.setName("#{hpwh.name} Coil")
      coil.setRatedHeatingCapacity(water_heater_capacity)
      coil.setRatedCOP(coefficient_of_performance)
      coil.setRatedSensibleHeatRatio(0.88) # default sensible_heat_ratio assumption
      coil.setRatedEvaporatorInletAirDryBulbTemperature(OpenStudio.convert(67.5, 'F', 'C').get)
      coil.setRatedEvaporatorInletAirWetBulbTemperature(OpenStudio.convert(56.426, 'F', 'C').get)
      coil.setEvaporatorFanPowerIncludedinRatedCOP(true)
      coil.setEvaporatorAirTemperatureTypeforCurveObjects('WetBulbTemperature')
      coil.setHeatingCapacityFunctionofTemperatureCurve(hpwh_cap)
      coil.setHeatingCOPFunctionofTemperatureCurve(hpwh_cop)
      coil.setMaximumAmbientTemperatureforCrankcaseHeaterOperation(0.0)

      # set tank properties
      if heat_pump_type == 'WrappedCondenser'
        tank = hpwh.tank.to_WaterHeaterStratified.get
        tank.setTankHeight(tank_height)
        tank.setHeaterPriorityControl('MasterSlave')
        if hpwh_vol_gal <= 50.0
          tank.setHeater1DeadbandTemperatureDifference(25.0)
          tank.setHeater2DeadbandTemperatureDifference(30.0)
        else
          tank.setHeater1DeadbandTemperatureDifference(18.5)
          tank.setHeater2DeadbandTemperatureDifference(3.89)
        end
        hpwh_bottom_element_sp = OpenStudio::Model::ScheduleConstant.new(model)
        hpwh_bottom_element_sp.setName("#{hpwh.name} BottomElementSetpoint")
        hpwh_top_element_sp = OpenStudio::Model::ScheduleConstant.new(model)
        hpwh_top_element_sp.setName("#{hpwh.name} TopElementSetpoint")
        tank.setHeater1Capacity(electric_backup_capacity)
        tank.setHeater1Height(h_ue)
        tank.setHeater1SetpointTemperatureSchedule(hpwh_top_element_sp) # Overwritten later by EMS
        tank.setHeater2Capacity(electric_backup_capacity)
        tank.setHeater2Height(h_le)
        tank.setHeater2SetpointTemperatureSchedule(hpwh_bottom_element_sp)
        tank.setUniformSkinLossCoefficientperUnitAreatoAmbientTemperature(u_tank)
        tank.setNumberofNodes(12)
        tank.setAdditionalDestratificationConductivity(0)
        tank.setNode1AdditionalLossCoefficient(0)
        tank.setNode2AdditionalLossCoefficient(0)
        tank.setNode3AdditionalLossCoefficient(0)
        tank.setNode4AdditionalLossCoefficient(0)
        tank.setNode5AdditionalLossCoefficient(0)
        tank.setNode6AdditionalLossCoefficient(0)
        tank.setNode7AdditionalLossCoefficient(0)
        tank.setNode8AdditionalLossCoefficient(0)
        tank.setNode9AdditionalLossCoefficient(0)
        tank.setNode10AdditionalLossCoefficient(0)
        tank.setNode11AdditionalLossCoefficient(0)
        tank.setNode12AdditionalLossCoefficient(0)
        tank.setUseSideDesignFlowRate(0.9 * water_heater_volume / 60.1)
        tank.setSourceSideDesignFlowRate(0)
        tank.setSourceSideFlowControlMode('')
        tank.setSourceSideInletHeight(0)
        tank.setSourceSideOutletHeight(0)
      elsif heat_pump_type == 'PumpedCondenser'
        tank = hpwh.tank.to_WaterHeaterMixed.get
        tank.setDeadbandTemperatureDifference(3.89)
        tank.setHeaterControlType('Cycle')
        tank.setHeaterMaximumCapacity(electric_backup_capacity)
      end
      tank.setName("#{hpwh.name} Tank")
      tank.setEndUseSubcategory('Service Hot Water')
      tank.setTankVolume(0.9 * water_heater_volume)
      tank.setMaximumTemperatureLimit(90.0)
      tank.setHeaterFuelType('Electricity')
      tank.setHeaterThermalEfficiency(1.0)
      tank.setOffCycleParasiticFuelConsumptionRate(off_cycle_parasitic_fuel_consumption_rate)
      tank.setOffCycleParasiticFuelType('Electricity')
      tank.setOnCycleParasiticFuelConsumptionRate(on_cycle_parasitic_fuel_consumption_rate)
      tank.setOnCycleParasiticFuelType('Electricity')

      # set fan properties
      fan = hpwh.fan.to_FanOnOff.get
      fan.setName("#{hpwh.name} Fan")
      fan_power = 0.0462 # watts per cfm
      if hpwh_vol_gal <= 50.0
        fan.setFanEfficiency(23.0 / fan_power * OpenStudio.convert(1.0, 'ft^3/min', 'm^3/s').get)
        fan.setPressureRise(23.0)
      else
        fan.setFanEfficiency(65.0 / fan_power * OpenStudio.convert(1.0, 'ft^3/min', 'm^3/s').get)
        fan.setPressureRise(65.0)
      end
      # determine maximum flow rate from water heater capacity
      # use 5.035E-5 m^3/s/W from EnergyPlus used to autocalculate the evaporator air flow rate in WaterHeater:HeatPump:PumpedCondenser and Coil:WaterHeating:AirToWaterHeatPump:Pumped
      fan_flow_rate_m3_per_s = water_heater_capacity * 5.035e-5
      fan.setMaximumFlowRate(fan_flow_rate_m3_per_s)
      fan.setMotorEfficiency(1.0)
      fan.setMotorInAirstreamFraction(1.0)
      fan.setEndUseSubcategory('Service Hot Water')

      if water_heater_thermal_zone.nil?
        # add in schedules for Tamb, RHamb, and the compressor
        # assume the water heater is indoors at 71.6F / 22C
        default_water_heater_ambient_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                                OpenStudio.convert(71.6, 'F', 'C').get,
                                                                                                                name: 'Water Heater Ambient Temp Schedule 70F',
                                                                                                                schedule_type_limit: 'Temperature')
        tank.setAmbientTemperatureIndicator('Schedule')
        tank.setAmbientTemperatureSchedule(default_water_heater_ambient_temp_sch)
        tank.resetAmbientTemperatureThermalZone
        hpwh_rhamb = OpenStudio::Model::ScheduleConstant.new(model)
        hpwh_rhamb.setName("#{hpwh.name} Ambient Humidity Schedule")
        hpwh_rhamb.setValue(0.5)
        hpwh.setInletAirConfiguration('Schedule')
        hpwh.setInletAirTemperatureSchedule(default_water_heater_ambient_temp_sch)
        hpwh.setInletAirHumiditySchedule(hpwh_rhamb)
        hpwh.setCompressorLocation('Schedule')
        hpwh.setCompressorAmbientTemperatureSchedule(default_water_heater_ambient_temp_sch)
      else
        hpwh.addToThermalZone(water_heater_thermal_zone)
        hpwh.setInletAirConfiguration('ZoneAirOnly')
        hpwh.setCompressorLocation('Zone')
        tank.setAmbientTemperatureIndicator('ThermalZone')
        tank.setAmbientTemperatureThermalZone(water_heater_thermal_zone)
        tank.resetAmbientTemperatureSchedule
      end

      if set_peak_use_flowrate
        rated_flow_rate_m3_per_s = peak_flowrate
        rated_flow_rate_gal_per_min = OpenStudio.convert(rated_flow_rate_m3_per_s, 'm^3/s', 'gal/min').get
        tank.setPeakUseFlowRate(rated_flow_rate_m3_per_s)
        tank.setUseFlowRateFractionSchedule(flowrate_schedule) unless flowrate_schedule.nil?
      end

      # add EMS for overriding HPWH setpoints schedules (for upper/lower heating element in water tank and compressor in heat pump)
      if heat_pump_type == 'WrappedCondenser' && use_ems_control
        hpwh_name_ems_friendly = OpenstudioStandards::HVAC.ems_friendly_name(hpwh.name)

        # create an ambient temperature sensor for the air that blows through the HPWH evaporator
        if water_heater_thermal_zone.nil?
          # assume the condenser is outside
          amb_temp_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Site Outdoor Air Drybulb Temperature')
          amb_temp_sensor.setName("#{hpwh_name_ems_friendly}_amb_temp")
          amb_temp_sensor.setKeyName('Environment')
        else
          amb_temp_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Zone Mean Air Temperature')
          amb_temp_sensor.setName("#{hpwh_name_ems_friendly}_amb_temp")
          amb_temp_sensor.setKeyName(water_heater_thermal_zone.name.to_s)
        end

        # create actuator for heat pump compressor
        if service_water_temperature_schedule.to_ScheduleConstant.is_initialized
          service_water_temperature_schedule = service_water_temperature_schedule.to_ScheduleConstant.get
          schedule_type = 'Schedule:Constant'
        elsif service_water_temperature_schedule.to_ScheduleCompact.is_initialized
          service_water_temperature_schedule = service_water_temperature_schedule.to_ScheduleCompact.get
          schedule_type = 'Schedule:Compact'
        elsif service_water_temperature_schedule.to_ScheduleRuleset.is_initialized
          service_water_temperature_schedule = service_water_temperature_schedule.to_ScheduleRuleset.get
          schedule_type = 'Schedule:Year'
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.ServiceWaterHeating', "Unsupported schedule type for HPWH setpoint schedule #{service_water_temperature_schedule.name}.")
          return false
        end
        hpwhschedoverride_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(service_water_temperature_schedule, schedule_type, 'Schedule Value')
        hpwhschedoverride_actuator.setName("#{hpwh_name_ems_friendly}_HPWHSchedOverride")

        # create actuator for lower heating element in water tank
        leschedoverride_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(hpwh_bottom_element_sp, 'Schedule:Constant', 'Schedule Value')
        leschedoverride_actuator.setName("#{hpwh_name_ems_friendly}_LESchedOverride")

        # create actuator for upper heating element in water tank
        ueschedoverride_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(hpwh_top_element_sp, 'Schedule:Constant', 'Schedule Value')
        ueschedoverride_actuator.setName("#{hpwh_name_ems_friendly}_UESchedOverride")

        # create sensor for heat pump compressor
        t_set_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
        t_set_sensor.setName("#{hpwh_name_ems_friendly}_T_set")
        t_set_sensor.setKeyName(service_water_temperature_schedule.name.to_s)

        # define control configuration
        t_offset = 9.0 # deg-C

        # get tank specifications
        upper_element_db = tank.heater1DeadbandTemperatureDifference

        # define control logic
        hpwh_ctrl_program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
        hpwh_ctrl_program.setName("#{hpwh_name_ems_friendly}_Control")
        hpwh_ctrl_program.addLine("SET #{hpwhschedoverride_actuator.name} = #{t_set_sensor.name}")
        # lockout hp when ambient temperature is either too high or too low
        hpwh_ctrl_program.addLine("IF (#{amb_temp_sensor.name}<#{hpwh_op_min_temp_c}) || (#{amb_temp_sensor.name}>#{hpwh_op_max_temp_c})")
        hpwh_ctrl_program.addLine("SET #{ueschedoverride_actuator.name} = #{t_set_sensor.name}")
        hpwh_ctrl_program.addLine("SET #{leschedoverride_actuator.name} = #{t_set_sensor.name}")
        hpwh_ctrl_program.addLine('ELSE')
        # upper element setpoint temperature
        hpwh_ctrl_program.addLine("SET #{ueschedoverride_actuator.name} = #{t_set_sensor.name} - #{t_offset}")
        # upper element cut-in temperature
        hpwh_ctrl_program.addLine("SET #{ueschedoverride_actuator.name}_cut_in = #{ueschedoverride_actuator.name} - #{upper_element_db}")
        # lower element disabled
        hpwh_ctrl_program.addLine("SET #{leschedoverride_actuator.name} = 0")
        # lower element disabled
        hpwh_ctrl_program.addLine("SET #{leschedoverride_actuator.name}_cut_in = 0")
        hpwh_ctrl_program.addLine('ENDIF')

        # create a program calling manager
        program_calling_manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
        program_calling_manager.setName("#{hpwh_name_ems_friendly}_ProgramManager")
        program_calling_manager.setCallingPoint('InsideHVACSystemIterationLoop')
        program_calling_manager.addProgram(hpwh_ctrl_program)
      end

      # add the water heater to the service water loop if provided
      unless service_water_loop.nil?
        service_water_loop.addSupplyBranchForComponent(tank)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ServiceWaterHeating', "Added heat pump water heater called #{tank.name}")

      return hpwh
    end

    # @!endgroup Create Water Heater
  end
end
