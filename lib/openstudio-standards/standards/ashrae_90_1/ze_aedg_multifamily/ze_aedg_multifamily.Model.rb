class ZEAEDGMultifamily < ASHRAE901
  # @!group Model

  # Applies the HVAC parts of the template to all objects in the model using the the template specified in the model.
  def model_apply_hvac_efficiency_standard(model, climate_zone, apply_controls: true)
    sql_db_vars_map = {}

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.ze_aedg_multifamily.Model', "Started applying HVAC efficiency standards for #{template} template.")

    # Air Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getAirLoopHVACs.sort.each { |obj| air_loop_hvac_apply_standard_controls(obj, climate_zone) unless air_loop_hvac_unitary_system?(obj) }
    end

    # Plant Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getPlantLoops.sort.each { |obj| plant_loop_apply_standard_controls(obj, climate_zone) }
    end

    # Zone HVAC Controls
    model.getZoneHVACComponents.sort.each { |obj| zone_hvac_component_apply_standard_controls(obj) }

    ##### Apply equipment efficiencies

    # Fans
    model.getFanVariableVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanConstantVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanOnOffs.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanZoneExhausts.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getZoneHVACComponents.sort.each { |obj| zone_hvac_component_apply_prm_baseline_fan_power(obj) }

    # Pumps
    model.getPumpConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getPumpVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getHeaderedPumpsConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getHeaderedPumpsVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getPlantLoops.sort.each { |obj| plant_loop_apply_prm_baseline_pumping_type(obj) unless plant_loop_swh_loop?(obj) }

    # Unitary HPs
    # set DX HP coils before DX clg coils because when DX HP coils need to first
    # pull the capacities of their paired DX clg coils, and this does not work
    # correctly if the DX clg coil efficiencies have been set because they are renamed.
    model.getCoilHeatingDXSingleSpeeds.sort.each { |obj| sql_db_vars_map = coil_heating_dx_single_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # Unitary ACs
    model.getCoilCoolingDXTwoSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_two_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingDXSingleSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_single_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # WSHPs
    # set WSHP heating coils before cooling coils to get cooling coil capacities before they are renamed
    model.getCoilHeatingWaterToAirHeatPumpEquationFits.sort.each { |obj| sql_db_vars_map = coil_heating_water_to_air_heat_pump_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each { |obj| sql_db_vars_map = coil_cooling_water_to_air_heat_pump_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # Chillers
    clg_tower_objs = model.getCoolingTowerSingleSpeeds
    model.getChillerElectricEIRs.sort.each { |obj| chiller_electric_eir_apply_efficiency_and_curves(obj, clg_tower_objs) }

    # Boilers
    model.getBoilerHotWaters.sort.each { |obj| boiler_hot_water_apply_efficiency_and_curves(obj) }

    # Water Heaters
    model.getWaterHeaterMixeds.sort.each { |obj| water_heater_mixed_apply_efficiency(obj) }

    # Cooling Towers
    model.getCoolingTowerSingleSpeeds.sort.each { |obj| cooling_tower_single_speed_apply_efficiency_and_curves(obj) }
    model.getCoolingTowerTwoSpeeds.sort.each { |obj| cooling_tower_two_speed_apply_efficiency_and_curves(obj) }
    model.getCoolingTowerVariableSpeeds.sort.each { |obj| cooling_tower_variable_speed_apply_efficiency_and_curves(obj) }

    # Fluid Coolers
    model.getFluidCoolerSingleSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Dry Cooler') }
    model.getFluidCoolerTwoSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Dry Cooler') }
    model.getEvaporativeFluidCoolerSingleSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Closed Cooling Tower') }
    model.getEvaporativeFluidCoolerTwoSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Closed Cooling Tower') }

    # ERVs
    model.getHeatExchangerAirToAirSensibleAndLatents.each { |obj| heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness(obj) }

    # Gas Heaters
    model.getCoilHeatingGass.sort.each { |obj| coil_heating_gas_apply_efficiency_and_curves(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.ze_aedg_multifamily.Model', "Finished applying HVAC efficiency standards for #{template} template.")
  end

  # Default 5-sided (exterior walls and roof) airtightness design value (m^3/h-m^2) from a building pressurization test at 75 Pascals.
  def default_airtightness
    airtightness_value = 5.0
    return airtightness_value
  end

  # Buildings built to this standard are assumed to have an air barrier
  def default_air_barrier
    return true
  end
end
