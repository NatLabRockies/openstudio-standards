module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Pump
    # Methods to create, modify, and get information about pumps

    # Get the pump flow rate (whether autosized or hard-sized)
    #
    # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types: PumpConstantSpeed, PumpVariableSpeed, HeaderedPumpsConstantSpeed, HeaderedPumpsVariableSpeed
    # return [Double] flow rate in m^3/s
    def self.pump_get_rated_flow_rate(pump)
      flow_m3_per_s = 0.0
      if pump.to_PumpVariableSpeed.is_initialized || pump.to_PumpConstantSpeed.is_initialized
        if pump.ratedFlowRate.is_initialized
          flow_m3_per_s = pump.ratedFlowRate.get
        elsif pump.autosizedRatedFlowRate.is_initialized
          flow_m3_per_s = pump.autosizedRatedFlowRate.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.pump', "For #{pump.name}, could not find rated pump Flow Rate.")
        end
      elsif pump.to_HeaderedPumpsVariableSpeed.is_initialized || pump.to_HeaderedPumpsConstantSpeed.is_initialized
        if pump.totalRatedFlowRate.is_initialized
          flow_m3_per_s = pump.totalRatedFlowRate.get
        elsif pump.autosizedTotalRatedFlowRate.is_initialized
          flow_m3_per_s = pump.autosizedTotalRatedFlowRate.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.pump', "For #{pump.name}, could not find rated pump Flow Rate.")
        end
      end

      return flow_m3_per_s
    end

    # Determines the pump power (W) based on flow rate, pressure rise,
    # and total pump efficiency(impeller eff * motor eff).
    # Uses the E+ default assumption of 0.78 impeller efficiency.
    #
    # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
    #   PumpConstantSpeed, PumpVariableSpeed
    # @return [Double] pump power in watts
    def self.pump_get_power(pump)
      # Get flow rate (whether autosized or hard-sized)
      flow_m3_per_s = OpenstudioStandards::HVAC.pump_get_rated_flow_rate(pump)

      # E+ default impeller efficiency
      # http://bigladdersoftware.com/epx/docs/8-4/engineering-reference/component-sizing.html#pump-sizing
      impeller_eff = 0.78

      # Get the motor efficiency
      motor_eff = pump.motorEfficiency

      # Calculate the total efficiency
      # which includes both motor and
      # impeller efficiency.
      pump_total_eff = impeller_eff * motor_eff

      # Get the pressure rise (Pa)
      pressure_rise_pa = pump.ratedPumpHead

      # Calculate the pump power (W)
      pump_power_w = pressure_rise_pa * flow_m3_per_s / pump_total_eff

      return pump_power_w
    end

    # Determines the brake horsepower of the pump based on flow rate,
    # pressure rise, and impeller efficiency.
    #
    # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
    #   PumpConstantSpeed, PumpVariableSpeed
    # @return [Double] brake horsepower
    def self.pump_get_brake_horsepower(pump)
      # Get flow rate (whether autosized or hard-sized)
      flow_m3_per_s = OpenstudioStandards::HVAC.pump_get_rated_flow_rate(pump)

      # E+ default impeller efficiency
      # http://bigladdersoftware.com/epx/docs/8-4/engineering-reference/component-sizing.html#pump-sizing
      impeller_eff = 0.78

      # Get the pressure rise (Pa)
      pressure_rise_pa = pump.ratedPumpHead

      # Calculate the pump power (W)
      pump_power_w = pressure_rise_pa * flow_m3_per_s / impeller_eff

      # Convert to HP
      pump_power_hp = pump_power_w / 745.7 # 745.7 W/HP

      return pump_power_hp
    end

    # Determines the horsepower of the pump motor, including motor efficiency and pump impeller efficiency.
    #
    # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
    #   PumpConstantSpeed, PumpVariableSpeed
    # @return [Double] motor horsepower
    def self.pump_get_motor_horsepower(pump)
      # Get the pump power
      pump_power_w = OpenstudioStandards::HVAC.pump_get_power(pump)

      # Convert to HP
      pump_hp = pump_power_w / 745.7 # 745.7 W/HP

      return pump_hp
    end

    # Determines the rated watts per GPM of the pump
    #
    # @param pump [OpenStudio::Model::StraightComponent] pump object, allowable types:
    #   PumpConstantSpeed, PumpVariableSpeed
    # @return [Double] rated power consumption per flow in watts per gpm, W*min/gal
    def self.pump_get_rated_w_per_gpm(pump)
      # Get design power (whether autosized or hard-sized)
      rated_power_w = 0
      if pump.ratedPowerConsumption.is_initialized
        rated_power_w = pump.ratedPowerConsumption.get
      elsif pump.autosizedRatedPowerConsumption.is_initialized
        rated_power_w = pump.autosizedRatedPowerConsumption.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC.pump', "For #{pump.name}, could not find rated pump power consumption, cannot determine w per gpm correctly.")
        return 0.0
      end

      rated_m3_per_s = OpenstudioStandards::HVAC.pump_get_rated_flow_rate(pump)
      rated_w_per_m3s = rated_power_w / rated_m3_per_s
      rated_w_per_gpm = OpenStudio.convert(rated_w_per_m3s, 'W*s/m^3', 'W*min/gal').get

      return rated_w_per_gpm
    end

    # Set the pump curve coefficients based on the specified control type.
    #
    # @param pump_variable_speed [OpenStudio::Model::PumpVariableSpeed, OpenStudio::Model::HeaderedPumpsVariableSpeed] variable speed pump or headered variable speed pumps object
    # @param control_type [String] valid choices are Riding Curve, VSD No Reset, VSD DP Reset
    # @return [Boolean] returns true if successful, false if not
    def self.pump_variable_speed_set_control_type(pump_variable_speed, control_type: 'Riding Curve')
      # Determine the coefficients
      coeff_a = nil
      coeff_b = nil
      coeff_c = nil
      coeff_d = nil
      case control_type
      when 'Constant Flow'
        coeff_a = 0.0
        coeff_b = 1.0
        coeff_c = 0.0
        coeff_d = 0.0
      when 'Riding Curve'
        coeff_a = 0.0
        coeff_b = 3.2485
        coeff_c = -4.7443
        coeff_d = 2.5294
      when 'VSD No Reset'
        coeff_a = 0.0
        coeff_b = 0.5726
        coeff_c = -0.301
        coeff_d = 0.7347
      when 'VSD DP Reset'
        coeff_a = 0.0
        coeff_b = 0.0205
        coeff_c = 0.4101
        coeff_d = 0.5753
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.pump', "Pump control type '#{control_type}' not recognized, pump coefficients will not be changed.")
        return false
      end

      # Set the coefficients
      pump_variable_speed.setCoefficient1ofthePartLoadPerformanceCurve(coeff_a)
      pump_variable_speed.setCoefficient2ofthePartLoadPerformanceCurve(coeff_b)
      pump_variable_speed.setCoefficient3ofthePartLoadPerformanceCurve(coeff_c)
      pump_variable_speed.setCoefficient4ofthePartLoadPerformanceCurve(coeff_d)
      pump_variable_speed.setPumpControlType('Intermittent')

      # Append the control type to the pump name
      # self.setName("#{self.name} #{control_type}")

      return true
    end
  end
end
