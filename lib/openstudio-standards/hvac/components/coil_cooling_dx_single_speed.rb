module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilCoolingDXSingleSpeed object
    # Enters in default curves for coil by type of coil
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the system, or nil in which case it will be defaulted
    # @param schedule [String] name of the availability schedule, or [<OpenStudio::Model::Schedule>] Schedule object, or nil in which case default to always on
    # @param type [String] the type of single speed DX coil to reference the correct curve set
    # @param cop [Double] rated cooling coefficient of performance
    # @return [OpenStudio::Model::CoilCoolingDXTwoSpeed] the DX cooling coil
    def self.create_coil_cooling_dx_single_speed(model,
                                                 air_loop_node: nil,
                                                 name: '1spd DX Clg Coil',
                                                 schedule: nil,
                                                 type: nil,
                                                 cop: nil)
      clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)

      # add to air loop if specified
      clg_coil.addToNode(air_loop_node) unless air_loop_node.nil?

      # set coil name
      clg_coil.setName(name)

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
      clg_coil.setAvailabilitySchedule(coil_availability_schedule)

      # set coil cop
      clg_coil.setRatedCOP(cop) unless cop.nil?

      clg_cap_f_of_temp = nil
      clg_cap_f_of_flow = nil
      clg_energy_input_ratio_f_of_temp = nil
      clg_energy_input_ratio_f_of_flow = nil
      clg_part_load_ratio = nil

      # curve sets
      case type
      when 'OS default'
        # use OS defaults

      when 'Heat Pump'
        # "PSZ-AC_Unitary_PackagecoolCapFT"
        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_cap_f_of_temp.setCoefficient1Constant(0.766956)
        clg_cap_f_of_temp.setCoefficient2x(0.0107756)
        clg_cap_f_of_temp.setCoefficient3xPOW2(-0.0000414703)
        clg_cap_f_of_temp.setCoefficient4y(0.00134961)
        clg_cap_f_of_temp.setCoefficient5yPOW2(-0.000261144)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(0.000457488)
        clg_cap_f_of_temp.setMinimumValueofx(12.78)
        clg_cap_f_of_temp.setMaximumValueofx(23.89)
        clg_cap_f_of_temp.setMinimumValueofy(21.1)
        clg_cap_f_of_temp.setMaximumValueofy(46.1)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_cap_f_of_flow.setCoefficient1Constant(0.8)
        clg_cap_f_of_flow.setCoefficient2x(0.2)
        clg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
        clg_cap_f_of_flow.setMinimumValueofx(0.5)
        clg_cap_f_of_flow.setMaximumValueofx(1.5)

        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.297145)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.0430933)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.000748766)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.00597727)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.000482112)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.000956448)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(12.78)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(23.89)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(21.1)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.1)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.156)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.1816)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0256)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.5)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.5)

        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(model)
        clg_part_load_ratio.setCoefficient1Constant(0.85)
        clg_part_load_ratio.setCoefficient2x(0.15)
        clg_part_load_ratio.setCoefficient3xPOW2(0.0)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)

      when 'PSZ-AC'
        # Defaults to "DOE Ref DX Clg Coil Cool-Cap-fT"
        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_cap_f_of_temp.setCoefficient1Constant(0.9712123)
        clg_cap_f_of_temp.setCoefficient2x(-0.015275502)
        clg_cap_f_of_temp.setCoefficient3xPOW2(0.0014434524)
        clg_cap_f_of_temp.setCoefficient4y(-0.00039321)
        clg_cap_f_of_temp.setCoefficient5yPOW2(-0.0000068364)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.0002905956)
        clg_cap_f_of_temp.setMinimumValueofx(-100.0)
        clg_cap_f_of_temp.setMaximumValueofx(100.0)
        clg_cap_f_of_temp.setMinimumValueofy(-100.0)
        clg_cap_f_of_temp.setMaximumValueofy(100.0)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_cap_f_of_flow.setCoefficient1Constant(1.0)
        clg_cap_f_of_flow.setCoefficient2x(0.0)
        clg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
        clg_cap_f_of_flow.setMinimumValueofx(-100.0)
        clg_cap_f_of_flow.setMaximumValueofx(100.0)

        # "DOE Ref DX Clg Coil Cool-EIR-fT",
        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.28687133)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.023902164)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.000810648)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.013458546)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.0003389364)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.0004870044)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(-100.0)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(100.0)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(-100.0)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(100.0)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.0)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(0.0)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(-100.0)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(100.0)

        # "DOE Ref DX Clg Coil Cool-PLF-fPLR"
        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(model)
        clg_part_load_ratio.setCoefficient1Constant(0.90949556)
        clg_part_load_ratio.setCoefficient2x(0.09864773)
        clg_part_load_ratio.setCoefficient3xPOW2(-0.00819488)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)
        clg_part_load_ratio.setMinimumCurveOutput(0.7)
        clg_part_load_ratio.setMaximumCurveOutput(1.0)

      when 'Window AC'
        # Performance curves
        # From Frigidaire 10.7 EER unit in Winkler et. al. Lab Testing of Window ACs (2013)
        # @note These coefficients are in SI UNITS
        cool_cap_ft_coeffs_si = [0.6405, 0.01568, 0.0004531, 0.001615, -0.0001825, 0.00006614]
        cool_eir_ft_coeffs_si = [2.287, -0.1732, 0.004745, 0.01662, 0.000484, -0.001306]
        cool_cap_fflow_coeffs = [0.887, 0.1128, 0]
        cool_eir_fflow_coeffs = [1.763, -0.6081, 0]
        cool_plf_fplr_coeffs = [0.78, 0.22, 0]

        # Make the curves
        clg_cap_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_cap_ft_coeffs_si, name: 'RoomAC-Cap-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_cap_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_cap_fflow_coeffs, name: 'RoomAC-Cap-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_energy_input_ratio_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_eir_ft_coeffs_si, name: 'RoomAC-EIR-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_energy_input_ratio_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_eir_fflow_coeffs, name: 'RoomAC-EIR-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_part_load_ratio = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_plf_fplr_coeffs, name: 'RoomAC-PLF-fPLR', min_x: 0, max_x: 1, min_out: 0, max_out: 1, is_dimensionless: true)

      when 'Residential Central AC'
        # Performance curves
        # These coefficients are in IP UNITS
        cool_cap_ft_coeffs_ip = [3.670270705, -0.098652414, 0.000955906, 0.006552414, -0.0000156, -0.000131877]
        cool_eir_ft_coeffs_ip = [-3.302695861, 0.137871531, -0.001056996, -0.012573945, 0.000214638, -0.000145054]
        cool_cap_fflow_coeffs = [0.718605468, 0.410099989, -0.128705457]
        cool_eir_fflow_coeffs = [1.32299905, -0.477711207, 0.154712157]
        cool_plf_fplr_coeffs = [0.8, 0.2, 0]

        # Convert coefficients from IP to SI
        cool_cap_ft_coeffs_si = OpenstudioStandards::HVAC.convert_curve_biquadratic(cool_cap_ft_coeffs_ip)
        cool_eir_ft_coeffs_si = OpenstudioStandards::HVAC.convert_curve_biquadratic(cool_eir_ft_coeffs_ip)

        # Make the curves
        clg_cap_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_cap_ft_coeffs_si, name: 'AC-Cap-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_cap_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_cap_fflow_coeffs, name: 'AC-Cap-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_energy_input_ratio_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_eir_ft_coeffs_si, name: 'AC-EIR-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_energy_input_ratio_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_eir_fflow_coeffs, name: 'AC-EIR-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_part_load_ratio = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_plf_fplr_coeffs, name: 'AC-PLF-fPLR', min_x: 0, max_x: 1, min_out: 0, max_out: 1, is_dimensionless: true)

      when 'Residential Central ASHP'
        # Performance curves
        # These coefficients are in IP UNITS
        cool_cap_ft_coeffs_ip = [3.68637657, -0.098352478, 0.000956357, 0.005838141, -0.0000127, -0.000131702]
        cool_eir_ft_coeffs_ip = [-3.437356399, 0.136656369, -0.001049231, -0.0079378, 0.000185435, -0.0001441]
        cool_cap_fflow_coeffs = [0.718664047, 0.41797409, -0.136638137]
        cool_eir_fflow_coeffs = [1.143487507, -0.13943972, -0.004047787]
        cool_plf_fplr_coeffs = [0.8, 0.2, 0]

        # Convert coefficients from IP to SI
        cool_cap_ft_coeffs_si = OpenstudioStandards::HVAC.convert_curve_biquadratic(cool_cap_ft_coeffs_ip)
        cool_eir_ft_coeffs_si = OpenstudioStandards::HVAC.convert_curve_biquadratic(cool_eir_ft_coeffs_ip)

        # Make the curves
        clg_cap_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_cap_ft_coeffs_si, name: 'Cool-Cap-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_cap_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_cap_fflow_coeffs, name: 'Cool-Cap-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_energy_input_ratio_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_eir_ft_coeffs_si, name: 'Cool-EIR-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_energy_input_ratio_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_eir_fflow_coeffs, name: 'Cool-EIR-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_part_load_ratio = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_plf_fplr_coeffs, name: 'Cool-PLF-fPLR', min_x: 0, max_x: 1, min_out: 0, max_out: 1, is_dimensionless: true)

      else # default curve set, type == 'Split AC' || 'PTAC'
        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_cap_f_of_temp.setCoefficient1Constant(0.942587793)
        clg_cap_f_of_temp.setCoefficient2x(0.009543347)
        clg_cap_f_of_temp.setCoefficient3xPOW2(0.00068377)
        clg_cap_f_of_temp.setCoefficient4y(-0.011042676)
        clg_cap_f_of_temp.setCoefficient5yPOW2(0.000005249)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.00000972)
        clg_cap_f_of_temp.setMinimumValueofx(12.77778)
        clg_cap_f_of_temp.setMaximumValueofx(23.88889)
        clg_cap_f_of_temp.setMinimumValueofy(23.88889)
        clg_cap_f_of_temp.setMaximumValueofy(46.11111)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_cap_f_of_flow.setCoefficient1Constant(0.8)
        clg_cap_f_of_flow.setCoefficient2x(0.2)
        clg_cap_f_of_flow.setCoefficient3xPOW2(0)
        clg_cap_f_of_flow.setMinimumValueofx(0.5)
        clg_cap_f_of_flow.setMaximumValueofx(1.5)

        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.342414409)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.034885008)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.0006237)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.004977216)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.000437951)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.000728028)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(12.77778)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(23.88889)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(23.88889)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.11111)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.1552)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.1808)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0256)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.5)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.5)

        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(model)
        clg_part_load_ratio.setCoefficient1Constant(0.85)
        clg_part_load_ratio.setCoefficient2x(0.15)
        clg_part_load_ratio.setCoefficient3xPOW2(0.0)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)
        clg_part_load_ratio.setMinimumCurveOutput(0.7)
        clg_part_load_ratio.setMaximumCurveOutput(1.0)
      end

      clg_coil.setTotalCoolingCapacityFunctionOfTemperatureCurve(clg_cap_f_of_temp) unless clg_cap_f_of_temp.nil?
      clg_coil.setTotalCoolingCapacityFunctionOfFlowFractionCurve(clg_cap_f_of_flow) unless clg_cap_f_of_flow.nil?
      clg_coil.setEnergyInputRatioFunctionOfTemperatureCurve(clg_energy_input_ratio_f_of_temp) unless clg_energy_input_ratio_f_of_temp.nil?
      clg_coil.setEnergyInputRatioFunctionOfFlowFractionCurve(clg_energy_input_ratio_f_of_flow) unless clg_energy_input_ratio_f_of_flow.nil?
      clg_coil.setPartLoadFractionCorrelationCurve(clg_part_load_ratio) unless clg_part_load_ratio.nil?

      return clg_coil
    end

    # Return the capacity in W of a CoilCoolingDXSingleSpeed
    #
    # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
    # @param multiplier [Double] zone multiplier, if applicable
    # @return [Double] capacity in W
    def self.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: nil)
      capacity_w = nil
      if coil_cooling_dx_single_speed.ratedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_single_speed.ratedTotalCoolingCapacity.get
      elsif coil_cooling_dx_single_speed.autosizedRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_single_speed.autosizedRatedTotalCoolingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_cooling_dx_single_speed', "For #{coil_cooling_dx_single_speed.name} capacity is not available.")
        return capacity_w
      end

      if !multiplier.nil? && multiplier > 1
        total_cap = capacity_w
        capacity_w /= multiplier
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.coil_cooling_dx_single_speed', "For #{coil_cooling_dx_single_speed.name}, total capacity of #{OpenStudio.convert(total_cap, 'W', 'kBtu/hr').get.round(2)}kBTU/hr was divided by the zone multiplier of #{multiplier} to give #{capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get.round(2)}kBTU/hr.")
      end

      return capacity_w
    end
  end
end
