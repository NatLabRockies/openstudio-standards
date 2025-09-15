class ACM179dASHRAE9012007
  # @!group FanVariableVolume

  include Fan

  # Modify the fan curve coefficients to reflect a specific type of control.
  #
  # NOTE: 179D Override coeffs here for Table G3.1.3.15 VAV fan part-load fan power equation
  # This is the last line in the chain for these values.
  #
  # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
  # @param control_type [String] valid choices are:
  #   Multi Zone VAV with discharge dampers,
  #   Multi Zone VAV with VSD and SP Setpoint Reset,
  #   Multi Zone VAV with AF or BI Riding Curve,
  #   Multi Zone VAV with AF or BI with Inlet Vanes,
  #   Multi Zone VAV with FC Riding Curve,
  #   Multi Zone VAV with FC with Inlet Vanes,
  #   Multi Zone VAV with Vane-axial with Variable Pitch Blades,
  #   Multi Zone VAV with VSD and Fixed SP Setpoint,
  #   Multi Zone VAV with VSD and Static Pressure Reset,
  #   Single Zone VAV Fan
  # @return [Bool] returns true if successful, false if not
  def fan_variable_volume_set_control_type(fan_variable_volume, control_type)
    # Determine the coefficients
    coeff_a = nil
    coeff_b = nil
    coeff_c = nil
    coeff_d = nil
    min_pct_pwr = nil
    case control_type

    # add 'Multi Zone VAV with discharge dampers' and change the minimum fan power fraction of "Multi Zone VAV with VSD and Static Pressure Reset"
    when 'Multi Zone VAV with discharge dampers'
      coeff_a = 0.0013
      coeff_b = 0.1470
      coeff_c = 0.9506
      coeff_d = -0.0998
      min_pct_pwr = 0.25
    when 'Multi Zone VAV with VSD and SP Setpoint Reset'
      coeff_a = 0.04076
      coeff_b = 0.0881
      coeff_c = -0.0729
      coeff_d = 0.9437
      min_pct_pwr = 0.25
    when 'Multi Zone VAV with AF or BI Riding Curve'
      coeff_a = 0.1631
      coeff_b = 1.5901
      coeff_c = -0.8817
      coeff_d = 0.1281
      min_pct_pwr = 0.7
    when 'Multi Zone VAV with AF or BI with Inlet Vanes'
      coeff_a = 0.9977
      coeff_b = -0.659
      coeff_c = 0.9547
      coeff_d = -0.2936
      min_pct_pwr = 0.5
    when 'Multi Zone VAV with FC Riding Curve'
      coeff_a = 0.1224
      coeff_b = 0.612
      coeff_c = 0.5983
      coeff_d = -0.3334
      min_pct_pwr = 0.3
    when 'Multi Zone VAV with FC with Inlet Vanes'
      coeff_a = 0.3038
      coeff_b = -0.7608
      coeff_c = 2.2729
      coeff_d = -0.8169
      min_pct_pwr = 0.3
    when 'Multi Zone VAV with Vane-axial with Variable Pitch Blades'
      coeff_a = 0.1639
      coeff_b = -0.4016
      coeff_c = 1.9909
      coeff_d = -0.7541
      min_pct_pwr = 0.2
    when 'Multi Zone VAV with VSD and Fixed SP Setpoint'
      coeff_a = 0.0013
      coeff_b = 0.1470
      coeff_c = 0.9506
      coeff_d = -0.0998
      min_pct_pwr = 0.2
    when 'Multi Zone VAV with VSD and Static Pressure Reset'
      coeff_a = 0.04076
      coeff_b = 0.0881
      coeff_c = -0.0729
      coeff_d = 0.9437
      min_pct_pwr = 0.1
    when 'Single Zone VAV Fan'
      coeff_a = 0.0013
      coeff_b = 0.147
      coeff_c = 0.9506
      coeff_d = -0.0998
      min_pct_pwr = 0.1
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.FanVariableVolume', "Fan control type '#{control_type}' not recognized, fan power coefficients will not be changed.")
      return false
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.FanVariableVolume', "For #{fan_variable_volume.name}: Set fan curve coefficients to reflect control type of '#{control_type}'.")

    # Set the coefficients
    fan_variable_volume.setFanPowerCoefficient1(coeff_a)
    fan_variable_volume.setFanPowerCoefficient2(coeff_b)
    fan_variable_volume.setFanPowerCoefficient3(coeff_c)
    fan_variable_volume.setFanPowerCoefficient4(coeff_d)

    # Set the fan minimum power
    fan_variable_volume.setFanPowerMinimumFlowRateInputMethod('Fraction')
    fan_variable_volume.setFanPowerMinimumFlowFraction(min_pct_pwr)

    # Append the control type to the fan name
    # self.setName("#{self.name} #{control_type}")
    return true
  end
end
