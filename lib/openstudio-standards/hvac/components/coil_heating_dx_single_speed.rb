module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilHeatingDXSingleSpeed object
    # Enters in default curves for coil by type of coil
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the system, or nil in which case it will be defaulted
    # @param schedule [String] name of the availability schedule, or [<OpenStudio::Model::Schedule>] Schedule object, or nil in which case default to always on
    # @param type [String] the type of single speed DX coil to reference the correct curve set
    # @param cop [Double] rated heating coefficient of performance
    # @param defrost_strategy [String] type of defrost strategy. options are reverse-cycle or resistive
    # @return [OpenStudio::Model::CoilHeatingDXSingleSpeed] the DX heating coil
    def self.create_coil_heating_dx_single_speed(model,
                                                 air_loop_node: nil,
                                                 name: '1spd DX Htg Coil',
                                                 schedule: nil,
                                                 type: nil,
                                                 cop: 3.3,
                                                 defrost_strategy: 'ReverseCycle')
      htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)

      # add to air loop if specified
      htg_coil.addToNode(air_loop_node) unless air_loop_node.nil?

      # set coil name
      htg_coil.setName(name)

      # set coil availability schedule
      if schedule.nil?
        # default always on
        coil_availability_schedule = model.alwaysOnDiscreteSchedule
      elsif schedule.instance_of?(String)
        coil_availability_schedule = model_add_schedule(model, schedule)

        if coil_availability_schedule.nil? && schedule == 'alwaysOffDiscreteSchedule'
          coil_availability_schedule = model.alwaysOffDiscreteSchedule
        elsif coil_availability_schedule.nil?
          coil_availability_schedule = model.alwaysOnDiscreteSchedule
        end
      elsif !schedule.to_Schedule.empty?
        coil_availability_schedule = schedule
      end
      htg_coil.setAvailabilitySchedule(coil_availability_schedule)

      # set coil cop
      if cop.nil?
        htg_coil.setRatedCOP(3.3)
      else
        htg_coil.setRatedCOP(cop)
      end

      htg_cap_f_of_temp = nil
      htg_cap_f_of_flow = nil
      htg_energy_input_ratio_f_of_temp = nil
      htg_energy_input_ratio_f_of_flow = nil
      htg_part_load_fraction = nil
      def_eir_f_of_temp = nil

      # curve sets
      case type
      when 'OS default'
        # use OS defaults
      when 'Residential Central Air Source HP'
        # Performance curves
        # These coefficients are in IP UNITS
        heat_cap_ft_coeffs_ip = [0.566333415, -0.000744164, -0.0000103, 0.009414634, 0.0000506, -0.00000675]
        heat_eir_ft_coeffs_ip = [0.718398423, 0.003498178, 0.000142202, -0.005724331, 0.00014085, -0.000215321]
        heat_cap_fflow_coeffs = [0.694045465, 0.474207981, -0.168253446]
        heat_eir_fflow_coeffs = [2.185418751, -1.942827919, 0.757409168]
        heat_plf_fplr_coeffs = [0.8, 0.2, 0]
        defrost_eir_coeffs = [0.1528, 0, 0, 0, 0, 0]

        # Convert coefficients from IP to SI
        heat_cap_ft_coeffs_si = OpenstudioStandards::HVAC.convert_curve_biquadratic(heat_cap_ft_coeffs_ip)
        heat_eir_ft_coeffs_si = OpenstudioStandards::HVAC.convert_curve_biquadratic(heat_eir_ft_coeffs_ip)

        htg_cap_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, heat_cap_ft_coeffs_si, name: 'Heat-Cap-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        htg_cap_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, heat_cap_fflow_coeffs, name: 'Heat-Cap-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        htg_energy_input_ratio_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, heat_eir_ft_coeffs_si, name: 'Heat-EIR-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        htg_energy_input_ratio_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, heat_eir_fflow_coeffs, name: 'Heat-EIR-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        htg_part_load_fraction = OpenstudioStandards::HVAC.create_curve_quadratic(model, heat_plf_fplr_coeffs, name: 'Heat-PLF-fPLR', min_x: 0, max_x: 1, min_out: 0, max_out: 1, is_dimensionless: true)

        # Heating defrost curve for reverse cycle
        def_eir_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, defrost_eir_coeffs, name: 'DefrostEIR', min_x: -100, max_x: 100, min_y: -100, max_y: 100)
      when 'Residential Minisplit HP'
        # Performance curves
        # These coefficients are in SI UNITS
        heat_cap_ft_coeffs_si = [1.14715889038462, -0.010386676170938, 0, 0.00865384615384615, 0, 0]
        heat_eir_ft_coeffs_si = [0.9999941697687026, 0.004684593830254383, 5.901286675833333e-05, -0.0028624467783091973, 1.3041120194135802e-05, -0.00016172918478765433]
        heat_cap_fflow_coeffs = [1, 0, 0]
        heat_eir_fflow_coeffs = [1, 0, 0]
        heat_plf_fplr_coeffs = [0.89, 0.11, 0]
        defrost_eir_coeffs = [0.1528, 0, 0, 0, 0, 0]

        htg_cap_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, heat_cap_ft_coeffs_si, name: 'Heat-Cap-fT', min_x: -100, max_x: 100, min_y: -100, max_y: 100)
        htg_cap_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, heat_cap_fflow_coeffs, name: 'Heat-Cap-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        htg_energy_input_ratio_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, heat_eir_ft_coeffs_si, name: 'Heat-EIR-fT', min_x: -100, max_x: 100, min_y: -100, max_y: 100)
        htg_energy_input_ratio_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, heat_eir_fflow_coeffs, name: 'Heat-EIR-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        htg_part_load_fraction = OpenstudioStandards::HVAC.create_curve_quadratic(model, heat_plf_fplr_coeffs, name: 'Heat-PLF-fPLR', min_x: 0, max_x: 1, min_out: 0.6, max_out: 1, is_dimensionless: true)

        # Heating defrost curve for reverse cycle
        def_eir_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, defrost_eir_coeffs, name: 'Defrost EIR', min_x: -100, max_x: 100, min_y: -100, max_y: 100)
      else # default curve set
        htg_cap_f_of_temp = OpenStudio::Model::CurveCubic.new(model)
        htg_cap_f_of_temp.setName("#{htg_coil.name} Htg Cap Func of Temp Curve")
        htg_cap_f_of_temp.setCoefficient1Constant(0.758746)
        htg_cap_f_of_temp.setCoefficient2x(0.027626)
        htg_cap_f_of_temp.setCoefficient3xPOW2(0.000148716)
        htg_cap_f_of_temp.setCoefficient4xPOW3(0.0000034992)
        htg_cap_f_of_temp.setMinimumValueofx(-20.0)
        htg_cap_f_of_temp.setMaximumValueofx(20.0)

        htg_cap_f_of_flow = OpenStudio::Model::CurveCubic.new(model)
        htg_cap_f_of_flow.setName("#{htg_coil.name} Htg Cap Func of Flow Frac Curve")
        htg_cap_f_of_flow.setCoefficient1Constant(0.84)
        htg_cap_f_of_flow.setCoefficient2x(0.16)
        htg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
        htg_cap_f_of_flow.setCoefficient4xPOW3(0.0)
        htg_cap_f_of_flow.setMinimumValueofx(0.5)
        htg_cap_f_of_flow.setMaximumValueofx(1.5)

        htg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveCubic.new(model)
        htg_energy_input_ratio_f_of_temp.setName("#{htg_coil.name} EIR Func of Temp Curve")
        htg_energy_input_ratio_f_of_temp.setCoefficient1Constant(1.19248)
        htg_energy_input_ratio_f_of_temp.setCoefficient2x(-0.0300438)
        htg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(0.00103745)
        htg_energy_input_ratio_f_of_temp.setCoefficient4xPOW3(-0.000023328)
        htg_energy_input_ratio_f_of_temp.setMinimumValueofx(-20.0)
        htg_energy_input_ratio_f_of_temp.setMaximumValueofx(20.0)

        htg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        htg_energy_input_ratio_f_of_flow.setName("#{htg_coil.name} EIR Func of Flow Frac Curve")
        htg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.3824)
        htg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.4336)
        htg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0512)
        htg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.0)
        htg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.0)

        htg_part_load_fraction = OpenStudio::Model::CurveQuadratic.new(model)
        htg_part_load_fraction.setName("#{htg_coil.name} PLR Correlation Curve")
        htg_part_load_fraction.setCoefficient1Constant(0.85)
        htg_part_load_fraction.setCoefficient2x(0.15)
        htg_part_load_fraction.setCoefficient3xPOW2(0.0)
        htg_part_load_fraction.setMinimumValueofx(0.0)
        htg_part_load_fraction.setMaximumValueofx(1.0)

        unless defrost_strategy == 'Resistive'
          def_eir_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
          def_eir_f_of_temp.setName("#{htg_coil.name} Defrost EIR Func of Temp Curve")
          def_eir_f_of_temp.setCoefficient1Constant(0.297145)
          def_eir_f_of_temp.setCoefficient2x(0.0430933)
          def_eir_f_of_temp.setCoefficient3xPOW2(-0.000748766)
          def_eir_f_of_temp.setCoefficient4y(0.00597727)
          def_eir_f_of_temp.setCoefficient5yPOW2(0.000482112)
          def_eir_f_of_temp.setCoefficient6xTIMESY(-0.000956448)
          def_eir_f_of_temp.setMinimumValueofx(-23.33333)
          def_eir_f_of_temp.setMaximumValueofx(29.44444)
          def_eir_f_of_temp.setMinimumValueofy(-23.33333)
          def_eir_f_of_temp.setMaximumValueofy(29.44444)
        end
      end

      if type == 'PSZ-AC'
        htg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-12.2)
        htg_coil.setMaximumOutdoorDryBulbTemperatureforDefrostOperation(1.67)
        htg_coil.setCrankcaseHeaterCapacity(50.0)
        htg_coil.setMaximumOutdoorDryBulbTemperatureforCrankcaseHeaterOperation(4.4)
        htg_coil.setDefrostControl('OnDemand')

        def_eir_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        def_eir_f_of_temp.setName("#{htg_coil.name} Defrost EIR Func of Temp Curve")
        def_eir_f_of_temp.setCoefficient1Constant(0.297145)
        def_eir_f_of_temp.setCoefficient2x(0.0430933)
        def_eir_f_of_temp.setCoefficient3xPOW2(-0.000748766)
        def_eir_f_of_temp.setCoefficient4y(0.00597727)
        def_eir_f_of_temp.setCoefficient5yPOW2(0.000482112)
        def_eir_f_of_temp.setCoefficient6xTIMESY(-0.000956448)
        def_eir_f_of_temp.setMinimumValueofx(-23.33333)
        def_eir_f_of_temp.setMaximumValueofx(29.44444)
        def_eir_f_of_temp.setMinimumValueofy(-23.33333)
        def_eir_f_of_temp.setMaximumValueofy(29.44444)
      end

      htg_coil.setTotalHeatingCapacityFunctionofTemperatureCurve(htg_cap_f_of_temp) unless htg_cap_f_of_temp.nil?
      htg_coil.setTotalHeatingCapacityFunctionofFlowFractionCurve(htg_cap_f_of_flow) unless htg_cap_f_of_flow.nil?
      htg_coil.setEnergyInputRatioFunctionofTemperatureCurve(htg_energy_input_ratio_f_of_temp) unless htg_energy_input_ratio_f_of_temp.nil?
      htg_coil.setEnergyInputRatioFunctionofFlowFractionCurve(htg_energy_input_ratio_f_of_flow) unless htg_energy_input_ratio_f_of_flow.nil?
      htg_coil.setPartLoadFractionCorrelationCurve(htg_part_load_fraction) unless htg_part_load_fraction.nil?
      htg_coil.setDefrostEnergyInputRatioFunctionofTemperatureCurve(def_eir_f_of_temp) unless def_eir_f_of_temp.nil?
      htg_coil.setDefrostStrategy(defrost_strategy)
      htg_coil.setDefrostControl('OnDemand')

      return htg_coil
    end

    # Return the capacity in W of a CoilHeatingDXSingleSpeed
    #
    # @param coil_heating_dx_single_speed [OpenStudio::Model::CoilHeatingDXSingleSpeed] coil heating dx single speed object
    # @param multiplier [Double] zone multiplier, if applicable
    # @return [Double] capacity in W
    def self.coil_heating_dx_single_speed_get_capacity(coil_heating_dx_single_speed, multiplier: 1.0)
      capacity_w = nil
      if coil_heating_dx_single_speed.ratedTotalHeatingCapacity.is_initialized
        capacity_w = coil_heating_dx_single_speed.ratedTotalHeatingCapacity.get
      elsif coil_heating_dx_single_speed.autosizedRatedTotalHeatingCapacity.is_initialized
        capacity_w = coil_heating_dx_single_speed.autosizedRatedTotalHeatingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_heating_dx_single_speed', "For #{coil_heating_dx_single_speed.name} capacity is not available.")
        return capacity_w
      end

      return capacity_w
    end
  end
end
