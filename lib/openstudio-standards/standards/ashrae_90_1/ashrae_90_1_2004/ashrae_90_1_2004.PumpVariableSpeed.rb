class ASHRAE9012004 < ASHRAE901
  # @!group Pump

  # Determine type of pump part load control type
  # @note code_sections [90.1-2004_6.5.4.1]
  #
  # @param pump [OpenStudio::Model::PumpVariableSpeed] OpenStudio pump object
  # @param plant_loop_type [String] Type of plant loop
  # @param pump_nominal_hp [Float] Pump nominal horsepower
  # @return [String] Pump part load control type
  def pump_variable_speed_get_control_type(pump, plant_loop_type, pump_nominal_hp)
    threshold = 50 # hp

    # Sizing factor to take into account that pumps
    # are typically sized to handle a ~10% pressure
    # increase and ~10% flow increase.
    design_sizing_factor = 1.25

    # Get pump head in Pa
    pump_head_pa = pump.ratedPumpHead

    return 'VSD No Reset' if pump_nominal_hp * design_sizing_factor > threshold && pump_head_pa > 300_000 # 100 ft. of head

    # else
    return 'Riding Curve'
  end
end
