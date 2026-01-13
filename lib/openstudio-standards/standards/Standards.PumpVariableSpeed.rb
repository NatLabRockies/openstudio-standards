class Standard
  include Pump

  # Determine and set type of part load control type for heating and chilled
  # water variable speed pumps
  #
  # @param pump [OpenStudio::Model::PumpVariableSpeed] OpenStudio pump object
  # @return [Boolean] Returns true if applicable, false otherwise
  def pump_variable_speed_control_type(pump)
    # Get plant loop
    plant_loop = pump.plantLoop.get

    # Get plant loop type
    plant_loop_type = plant_loop.sizingPlant.loopType
    return false unless plant_loop_type == 'Heating' || plant_loop_type == 'Cooling'

    # Get rated pump power
    if pump.ratedPowerConsumption.is_initialized
      pump_rated_power_w = pump.ratedPowerConsumption.get
    elsif pump.autosizedRatedPowerConsumption.is_initialized
      pump_rated_power_w = pump.autosizedRatedPowerConsumption.get
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Pump', "For #{pump.name}, could not find rated pump power consumption, cannot determine w per gpm correctly.")
      return false
    end

    # Get nominal nameplate HP
    pump_nominal_hp = pump_rated_power_w * pump.motorEfficiency / 745.7

    # Assign peformance curves
    control_type = pump_variable_speed_get_control_type(pump, plant_loop_type, pump_nominal_hp)

    # Set pump part load performance curve coefficients
    OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type) if control_type

    return true
  end

  # Determine type of pump part load control type
  #
  # @param pump [OpenStudio::Model::PumpVariableSpeed] OpenStudio pump object
  # @param plant_loop_type [String] Type of plant loop
  # @param pump_nominal_hp [Float] Pump nominal horsepower
  # @return [String] Pump part load control type
  def pump_variable_speed_get_control_type(pump, plant_loop_type, pump_nominal_hp)
    # Get plant loop
    plant_loop = pump.plantLoop.get

    # Default assumptions are based on ASHRAE 90.1-2010 Appendix G (G3.1.3.5 and G3.1.3.10)
    case plant_loop_type
      when 'Heating'
        # Determine the area served by the plant loop
        area_served_m2 = plant_loop_total_floor_area_served(plant_loop)
        area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

        return 'VSD No Reset' if area_served_ft2 > 120_000

        # else
        return 'Riding Curve'
      when 'Cooling'
        # Get plant loop capacity capacity
        cooling_capacity_w = plant_loop_total_cooling_capacity(plant_loop)

        return 'VSD No Reset' if cooling_capacity_w >= 300

        # else
        return 'Riding Curve'
    end
  end
end
