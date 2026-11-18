class ASHRAE9012022 < ASHRAE901
  # @!group elevators

  # Determines the percentage of the elevator cab lighting that is incandescent.
  # The remainder is assumed to be LED.
  # Defaults to 0% incandescent (100% LED), representing newer elevators.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Double] incandescent lighting percentage
  def model_elevator_lighting_pct_incandescent(model)
    pct_incandescent = 0.0 # 100% LED
    return pct_incandescent
  end

  # Determines the power of the elevator ventilation fan.
  # 90.1-2022 has a requirement for ventilation fan efficiency.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param vent_rate_cfm [Double] the ventilation rate in ft^3/min
  # @return [Double] the ventilation fan power in watts
  def model_elevator_fan_pwr(model, vent_rate_cfm)
    vent_pwr_per_flow_w_per_cfm = 0.33
    vent_pwr_w = vent_pwr_per_flow_w_per_cfm * vent_rate_cfm
    # addendum 90.1-2007 aj has requirement on efficiency
    vent_pwr_w = vent_pwr_w * 0.29 / 0.70

    return vent_pwr_w
  end
end
