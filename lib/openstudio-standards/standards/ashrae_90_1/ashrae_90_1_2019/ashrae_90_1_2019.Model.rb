class ASHRAE9012019 < ASHRAE901
  # @!group Model

  # Returns the PRM building envelope infiltration rate at a pressure differential of 75 Pa in cfm per ft^2
  # @return [Double] infiltration rate in cfm per ft^2 at 75 Pa
  def prm_building_envelope_infiltration_rate
    return 1.0
  end
end