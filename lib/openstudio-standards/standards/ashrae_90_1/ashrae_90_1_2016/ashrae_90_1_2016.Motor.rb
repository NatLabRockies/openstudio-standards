class ASHRAE9012016 < ASHRAE901
  # @!group Motor

  # Determine the type of motor to model
  #
  # @param nominal_hp [Float] nominal or nameplate motor horsepower
  # @return [String] motor type
  def motor_type(nominal_hp)
    return 'ECM' # Addendum aj to 90.1-2010
  end
end
