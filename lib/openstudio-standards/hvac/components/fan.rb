module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Fan
    # Methods to create, modify, and get information about fans

    # creates an on off fan
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param fan_name [String] fan name
    # @param fan_efficiency [Double] fan efficiency
    # @param pressure_rise [Double] fan pressure rise in Pa
    # @param motor_efficiency [Double] fan motor efficiency
    # @param motor_in_airstream_fraction [Double] fraction of motor heat in airstream
    # @param end_use_subcategory [String] end use subcategory name
    # @return [OpenStudio::Model::FanOnOff] on off fan object
    def self.create_fan_on_off(model,
                               fan_name: nil,
                               fan_efficiency: nil,
                               pressure_rise: nil,
                               motor_efficiency: nil,
                               motor_in_airstream_fraction: nil,
                               end_use_subcategory: nil)
      fan = OpenStudio::Model::FanOnOff.new(model)
      fan.setName(fan_name) unless fan_name.nil?
      fan.setFanEfficiency(fan_efficiency) unless fan_efficiency.nil?
      fan.setPressureRise(pressure_rise) unless pressure_rise.nil?
      fan.setMotorEfficiency(motor_efficiency) unless motor_efficiency.nil?
      fan.setMotorInAirstreamFraction(motor_in_airstream_fraction) unless motor_in_airstream_fraction.nil?
      fan.setEndUseSubcategory(end_use_subcategory) unless end_use_subcategory.nil?

      return fan
    end

    # creates a constant volume fan
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param fan_name [String] fan name
    # @param fan_efficiency [Double] fan efficiency
    # @param pressure_rise [Double] fan pressure rise in Pa
    # @param motor_efficiency [Double] fan motor efficiency
    # @param motor_in_airstream_fraction [Double] fraction of motor heat in airstream
    # @param end_use_subcategory [String] end use subcategory name
    # @return [OpenStudio::Model::FanConstantVolume] constant volume fan object
    def self.create_fan_constant_volume(model,
                                        fan_name: nil,
                                        fan_efficiency: nil,
                                        pressure_rise: nil,
                                        motor_efficiency: nil,
                                        motor_in_airstream_fraction: nil,
                                        end_use_subcategory: nil)
      fan = OpenStudio::Model::FanConstantVolume.new(model)
      fan.setName(fan_name) unless fan_name.nil?
      fan.setFanEfficiency(fan_efficiency) unless fan_efficiency.nil?
      fan.setPressureRise(pressure_rise) unless pressure_rise.nil?
      fan.setEndUseSubcategory(end_use_subcategory) unless end_use_subcategory.nil?
      fan.setMotorEfficiency(motor_efficiency) unless motor_efficiency.nil?
      fan.setMotorInAirstreamFraction(motor_in_airstream_fraction) unless motor_in_airstream_fraction.nil?

      return fan
    end

    # creates a variable volume fan
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param fan_name [String] fan name
    # @param fan_efficiency [Double] fan efficiency
    # @param pressure_rise [Double] fan pressure rise in Pa
    # @param motor_efficiency [Double] fan motor efficiency
    # @param motor_in_airstream_fraction [Double] fraction of motor heat in airstream
    # @param end_use_subcategory [String] end use subcategory name
    # @param fan_curve [String] fan curve for variable volume fans. See fan_variable_volume_set_control_type() for options.
    # @param fan_power_minimum_flow_rate_input_method [String] options are Fraction, FixedFlowRate
    # @param fan_power_minimum_flow_rate_fraction [Double] minimum flow rate fraction. overrides data in fan curve.
    # @param fan_power_coefficient_1 [Double] fan power coefficient 1. overrides data in fan curve.
    # @param fan_power_coefficient_2 [Double] fan power coefficient 2. overrides data in fan curve.
    # @param fan_power_coefficient_3 [Double] fan power coefficient 3. overrides data in fan curve.
    # @param fan_power_coefficient_4 [Double] fan power coefficient 4. overrides data in fan curve.
    # @param fan_power_coefficient_5 [Double] fan power coefficient 5. overrides data in fan curve.
    # @return [OpenStudio::Model::FanVariableVolume] variable volume fan object
    def self.create_fan_variable_volume(model,
                                        fan_name: nil,
                                        fan_efficiency: nil,
                                        pressure_rise: nil,
                                        motor_efficiency: nil,
                                        motor_in_airstream_fraction: nil,
                                        end_use_subcategory: nil,
                                        fan_curve: nil,
                                        fan_power_minimum_flow_rate_input_method: nil,
                                        fan_power_minimum_flow_rate_fraction: nil,
                                        fan_power_coefficient_1: nil,
                                        fan_power_coefficient_2: nil,
                                        fan_power_coefficient_3: nil,
                                        fan_power_coefficient_4: nil,
                                        fan_power_coefficient_5: nil)
      fan = OpenStudio::Model::FanVariableVolume.new(model)
      fan.setName(fan_name) unless fan_name.nil?
      fan.setFanEfficiency(fan_efficiency) unless fan_efficiency.nil?
      fan.setPressureRise(pressure_rise) unless pressure_rise.nil?
      fan.setEndUseSubcategory(end_use_subcategory) unless end_use_subcategory.nil?
      fan.setMotorEfficiency(motor_efficiency) unless motor_efficiency.nil?
      fan.setMotorInAirstreamFraction(motor_in_airstream_fraction) unless motor_in_airstream_fraction.nil?
      OpenstudioStandards::HVAC.fan_variable_volume_set_control_type(fan, control_type: fan_curve) unless fan_curve.nil?
      fan.setFanPowerMinimumFlowRateInputMethod(fan_power_minimum_flow_rate_input_method) unless fan_power_minimum_flow_rate_input_method.nil?
      fan.setFanPowerMinimumFlowFraction(fan_power_minimum_flow_rate_fraction) unless fan_power_minimum_flow_rate_fraction.nil?
      fan.setFanPowerCoefficient1(fan_power_coefficient_1) unless fan_power_coefficient_1.nil?
      fan.setFanPowerCoefficient2(fan_power_coefficient_2) unless fan_power_coefficient_2.nil?
      fan.setFanPowerCoefficient3(fan_power_coefficient_3) unless fan_power_coefficient_3.nil?
      fan.setFanPowerCoefficient4(fan_power_coefficient_4) unless fan_power_coefficient_4.nil?
      fan.setFanPowerCoefficient5(fan_power_coefficient_5) unless fan_power_coefficient_5.nil?

      return fan
    end

    # creates a zone exhaust fan
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param fan_name [String] fan name
    # @param fan_efficiency [Double] fan efficiency
    # @param pressure_rise [Double] fan pressure rise in Pa
    # @param end_use_subcategory [String] end use subcategory name
    # @param system_availability_manager_coupling_mode [String] coupling mode, options are Coupled, Decoupled
    # @return [OpenStudio::Model::FanZoneExhaust] the exhaust fan
    def self.create_fan_zone_exhaust(model,
                                     fan_name: nil,
                                     fan_efficiency: nil,
                                     pressure_rise: nil,
                                     system_availability_manager_coupling_mode: nil,
                                     end_use_subcategory: nil)
      fan = OpenStudio::Model::FanZoneExhaust.new(model)
      fan.setName(fan_name) unless fan_name.nil?
      fan.setFanEfficiency(fan_efficiency) unless fan_efficiency.nil?
      fan.setPressureRise(pressure_rise) unless pressure_rise.nil?
      fan.setEndUseSubcategory(end_use_subcategory) unless end_use_subcategory.nil?
      fan.setSystemAvailabilityManagerCouplingMode(system_availability_manager_coupling_mode) unless system_availability_manager_coupling_mode.nil?

      return fan
    end

    # creates a fan system model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param fan_name [String] fan name
    # @param pressure_rise [Double] fan pressure rise in Pa
    # @param motor_efficiency [Double] fan motor efficiency
    # @param motor_in_airstream_fraction [Double] fraction of motor heat in airstream
    # @param end_use_subcategory [String] end use subcategory name
    # @param design_power_sizing_method [String] design power sizing method, options are PowerPerFlow or PowerPerFlowPerPressure
    # @param power_per_flow_rate [Double] power per flow rate in W/(m^3/s)
    # @param power_per_flow_rate_per_pressure [Double] power per flow rate per pressure in W/(m^3/s)/Pa
    # @param speed_control_method [String] speed control method, options are Discrete or Continuous
    # @param speeds [Array<[Integer, Integer]>] array of pairs of air flow rate fraction and electric power fraction for discrete speed fans
    # @return [OpenStudio::Model::FanSystemModel] fan system model object
    def self.create_fan_system_model(model,
                                     fan_name: nil,
                                     pressure_rise: nil,
                                     motor_efficiency: nil,
                                     motor_in_airstream_fraction: nil,
                                     end_use_subcategory: nil,
                                     design_power_sizing_method: 'PowerPerFlowPerPressure',
                                     power_per_flow_rate: nil,
                                     power_per_flow_rate_per_pressure: 1.66667,
                                     speed_control_method: 'Continuous',
                                     speeds: nil)
      fan = OpenStudio::Model::FanSystemModel.new(model)
      fan.setName(fan_name) unless fan_name.nil?
      fan.setDesignPressureRise(pressure_rise) unless pressure_rise.nil?
      fan.setMotorEfficiency(motor_efficiency) unless motor_efficiency.nil?
      fan.setMotorInAirStreamFraction(motor_in_airstream_fraction) unless motor_in_airstream_fraction.nil?
      fan.setEndUseSubcategory(end_use_subcategory) unless end_use_subcategory.nil?
      fan.setDesignPowerSizingMethod(design_power_sizing_method) unless design_power_sizing_method.nil?
      fan.setElectricPowerPerUnitFlowRate(power_per_flow_rate) unless power_per_flow_rate.nil?
      fan.setElectricPowerPerUnitFlowRatePerUnitPressure(power_per_flow_rate_per_pressure) unless power_per_flow_rate_per_pressure.nil?
      fan.setSpeedControlMethod(speed_control_method) unless speed_control_method.nil?
      if !speeds.nil? && (speed_control_method == 'Discrete')
        speeds.each { |pair| fan.addSpeed(pair[0], pair[1]) }
      end

      return fan
    end

    # create a fan with properties for a typical fan type
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param typical_fan [String] the kind of typical fan to create
    # @param fan_name [String] fan name
    # @param fan_efficiency [Double] fan efficiency
    # @param pressure_rise [Double] fan pressure rise in Pa
    # @param motor_efficiency [Double] fan motor efficiency
    # @param motor_in_airstream_fraction [Double] fraction of motor heat in airstream
    # @param end_use_subcategory [String] end use subcategory name
    # @param fan_curve [String] fan curve for variable volume fans. See fan_variable_volume_set_control_type() for options.
    # @param system_availability_manager_coupling_mode [String] coupling mode, options are Coupled, Decoupled
    # @return [OpenStudio::Model::StraightComponent] fan object
    def self.create_typical_fan(model, typical_fan,
                                fan_name: nil,
                                fan_efficiency: nil,
                                pressure_rise: nil,
                                motor_efficiency: nil,
                                motor_in_airstream_fraction: nil,
                                end_use_subcategory: nil,
                                fan_power_minimum_flow_rate_input_method: nil,
                                fan_power_minimum_flow_rate_fraction: nil,
                                fan_curve: nil,
                                system_availability_manager_coupling_mode: nil)
      fan_json = JSON.parse(File.read("#{__dir__}/data/fans.json"), symbolize_names: true)
      fan_data = fan_json[:fans].select { |hash| hash[:name] == typical_fan }

      if fan_data.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC.fan', "Could not find fan data for typical fan '#{typical_fan}'.")
        return nil
      end
      fan_data = fan_data[0]

      # use argument values if provided, otherwise use values from the fan data
      fan_efficiency ||= fan_data[:fan_efficiency]
      pressure_rise_inh2o ||= fan_data[:pressure_rise]
      pressure_rise_pa = pressure_rise_inh2o ? OpenStudio.convert(pressure_rise_inh2o, 'inH_{2}O', 'Pa').get : nil # convert pressure rise to Pa
      motor_efficiency ||= fan_data[:motor_efficiency]
      motor_in_airstream_fraction ||= fan_data[:motor_in_airstream_fraction]

      case fan_data[:type]
      when 'OnOff'
        fan = OpenstudioStandards::HVAC.create_fan_on_off(model,
                                                          fan_name: fan_name,
                                                          fan_efficiency: fan_efficiency,
                                                          pressure_rise: pressure_rise_pa,
                                                          motor_efficiency: motor_efficiency,
                                                          motor_in_airstream_fraction: motor_in_airstream_fraction,
                                                          end_use_subcategory: end_use_subcategory)
      when 'ConstantVolume'
        fan = OpenstudioStandards::HVAC.create_fan_constant_volume(model,
                                                                   fan_name: fan_name,
                                                                   fan_efficiency: fan_efficiency,
                                                                   pressure_rise: pressure_rise_pa,
                                                                   motor_efficiency: motor_efficiency,
                                                                   motor_in_airstream_fraction: motor_in_airstream_fraction,
                                                                   end_use_subcategory: end_use_subcategory)
      when 'VariableVolume'
        fan_curve ||= fan_data[:fan_curve]
        fan = OpenstudioStandards::HVAC.create_fan_variable_volume(model,
                                                                   fan_name: fan_name,
                                                                   fan_efficiency: fan_efficiency,
                                                                   pressure_rise: pressure_rise_pa,
                                                                   motor_efficiency: motor_efficiency,
                                                                   motor_in_airstream_fraction: motor_in_airstream_fraction,
                                                                   end_use_subcategory: end_use_subcategory,
                                                                   fan_curve: fan_curve,
                                                                   fan_power_minimum_flow_rate_input_method: fan_power_minimum_flow_rate_input_method,
                                                                   fan_power_minimum_flow_rate_fraction: fan_power_minimum_flow_rate_fraction)
      when 'ZoneExhaust'
        fan = OpenstudioStandards::HVAC.create_fan_zone_exhaust(model,
                                                                fan_name: fan_name,
                                                                fan_efficiency: fan_efficiency,
                                                                pressure_rise: pressure_rise,
                                                                end_use_subcategory: end_use_subcategory,
                                                                system_availability_manager_coupling_mode: system_availability_manager_coupling_mode)
      end

      return fan
    end

    # Modify the fan curve coefficients to reflect a specific type of control.
    #
    # @param fan_variable_volume [OpenStudio::Model::FanVariableVolume] variable volume fan object
    # @param control_type [String] valid choices are:
    #   Single Zone VAV
    #   Multi Zone VAV with Fixed Static Pressure Setpoint
    #   Multi Zone VAV with Static Pressure Setpoint Reset
    #   Multi Zone VAV with Discharge Dampers
    #   Multi Zone VAV with Airfoil or Backward Incline riding the curve
    #   Multi Zone VAV with Airfoil or Backward Incline with Inlet Vanes
    #   Multi Zone VAV with Forward Curved fans riding the curve
    #   Multi Zone VAV with Forward Curved with Inlet Vanes
    #   Multi Zone VAV with Vane-axial with Variable Pitch Blades
    # @return [Boolean] returns true if successful, false if not
    def self.fan_variable_volume_set_control_type(fan_variable_volume, control_type: 'Multi Zone VAV with Static Pressure Setpoint Reset')
      case control_type
      when 'Single Zone VAV'
        # Baseline for System Type 11 from ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.027827882
        coeff_b = 0.026583195
        coeff_c = -0.0870687
        coeff_d = 1.03091975
        min_pct_pwr = 0.1
      when 'Multi Zone VAV with Fixed Static Pressure Setpoint'
        # Appendix G baseline from ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.0013
        coeff_b = 0.1470
        coeff_c = 0.9506
        coeff_d = -0.0998
        min_pct_pwr = 0.2
      when 'Multi Zone VAV with Static Pressure Setpoint Reset'
        # OpenStudio default, baseline for System Types 5-8 from ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.040759894
        coeff_b = 0.08804497
        coeff_c = -0.07292612
        coeff_d = 0.943739823
        min_pct_pwr = 0.1
      when 'Multi Zone VAV with Discharge Dampers'
        coeff_a = 0.18984763
        coeff_b = 0.31447014
        coeff_c = 0.49568211
        coeff_d = 0.0
        min_pct_pwr = 0.25
      when 'Multi Zone VAV with Airfoil or Backward Incline riding the curve'
        # From ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.1631
        coeff_b = 1.5901
        coeff_c = -0.8817
        coeff_d = 0.1281
        min_pct_pwr = 0.7
      when 'Multi Zone VAV with Airfoil or Backward Incline with Inlet Vanes'
        # From ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.9977
        coeff_b = -0.659
        coeff_c = 0.9547
        coeff_d = -0.2936
        min_pct_pwr = 0.5
      when 'Multi Zone VAV with Forward Curved fans riding the curve'
        # From ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.1224
        coeff_b = 0.612
        coeff_c = 0.5983
        coeff_d = -0.3334
        min_pct_pwr = 0.3
      when 'Multi Zone VAV with Forward Curved with Inlet Vanes'
        # From ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.3038
        coeff_b = -0.7608
        coeff_c = 2.2729
        coeff_d = -0.8169
        min_pct_pwr = 0.3
      when 'Multi Zone VAV with Vane-axial with Variable Pitch Blades'
        # From ANSI/ASHRAE/IES Standard 90.1-2016 - Energy Standard for Buildings Except Low-Rise Residential Performance Rating Method
        coeff_a = 0.1639
        coeff_b = -0.4016
        coeff_c = 1.9909
        coeff_d = -0.7541
        min_pct_pwr = 0.2
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.fan', "Fan control type '#{control_type}' not recognized, fan power coefficients will not be changed.")
        return false
      end

      # Set the coefficients
      fan_variable_volume.setFanPowerCoefficient1(coeff_a) unless coeff_a.nil?
      fan_variable_volume.setFanPowerCoefficient2(coeff_b) unless coeff_b.nil?
      fan_variable_volume.setFanPowerCoefficient3(coeff_c) unless coeff_c.nil?
      fan_variable_volume.setFanPowerCoefficient4(coeff_d) unless coeff_d.nil?

      # Set the fan minimum power
      unless min_pct_pwr.nil?
        fan_variable_volume.setFanPowerMinimumFlowRateInputMethod('Fraction')
        fan_variable_volume.setFanPowerMinimumFlowFraction(min_pct_pwr)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.fan', "For #{fan_variable_volume.name}: Set fan curve coefficients to reflect control type of '#{control_type}'.")

      return true
    end
  end
end
