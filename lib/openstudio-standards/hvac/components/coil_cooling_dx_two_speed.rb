module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilCoolingDXTwoSpeed object
    # Enters in default curves for coil by type of coil
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the system, or nil in which case it will be defaulted
    # @param schedule [String] name of the availability schedule, or [<OpenStudio::Model::Schedule>] Schedule object, or nil in which case default to always on
    # @param type [String] the type of two speed DX coil to reference the correct curve set
    # @return [OpenStudio::Model::CoilCoolingDXTwoSpeed] the DX cooling coil
    def self.create_coil_cooling_dx_two_speed(model,
                                              air_loop_node: nil,
                                              name: '2spd DX Clg Coil',
                                              schedule: nil,
                                              type: nil)
      clg_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)

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

      clg_cap_f_of_temp = nil
      clg_cap_f_of_flow = nil
      clg_energy_input_ratio_f_of_temp = nil
      clg_energy_input_ratio_f_of_flow = nil
      clg_part_load_ratio = nil
      clg_cap_f_of_temp_low_spd = nil
      clg_energy_input_ratio_f_of_temp_low_spd = nil

      # curve sets
      if type == 'OS default'
        # use OS defaults
      elsif type == 'Residential Minisplit HP'
        # Performance curves
        # These coefficients are in SI units
        cool_cap_ft_coeffs_si = [0.7531983499655835, 0.003618193903031667, 0.0, 0.006574385031351544, -6.87181191015432e-05, 0.0]
        cool_eir_ft_coeffs_si = [-0.06376924779982301, -0.0013360593470367282, 1.413060577993827e-05, 0.019433076486584752, -4.91395947154321e-05, -4.909341249475308e-05]
        cool_cap_fflow_coeffs = [1, 0, 0]
        cool_eir_fflow_coeffs = [1, 0, 0]
        cool_plf_fplr_coeffs = [0.89, 0.11, 0]

        # Make the curves
        clg_cap_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_cap_ft_coeffs_si, name: 'Cool-Cap-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_cap_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_cap_fflow_coeffs, name: 'Cool-Cap-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_energy_input_ratio_f_of_temp = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_eir_ft_coeffs_si, name: 'Cool-EIR-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_energy_input_ratio_f_of_flow = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_eir_fflow_coeffs, name: 'Cool-EIR-fFF', min_x: 0, max_x: 2, min_out: 0, max_out: 2, is_dimensionless: true)
        clg_part_load_ratio = OpenstudioStandards::HVAC.create_curve_quadratic(model, cool_plf_fplr_coeffs, name: 'Cool-PLF-fPLR', min_x: 0, max_x: 1, min_out: 0, max_out: 1, is_dimensionless: true)
        clg_cap_f_of_temp_low_spd = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_cap_ft_coeffs_si, name: 'Cool-Cap-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_energy_input_ratio_f_of_temp_low_spd = OpenstudioStandards::HVAC.create_curve_biquadratic(model, cool_eir_ft_coeffs_si, name: 'Cool-EIR-fT', min_x: 0, max_x: 100, min_y: 0, max_y: 100)
        clg_coil.setRatedLowSpeedSensibleHeatRatio(0.73)
        clg_coil.setCondenserType('AirCooled')
      else # default curve set, type == 'PSZ-AC' || 'Split AC' || 'PTAC'
        clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_cap_f_of_temp.setCoefficient1Constant(0.42415)
        clg_cap_f_of_temp.setCoefficient2x(0.04426)
        clg_cap_f_of_temp.setCoefficient3xPOW2(-0.00042)
        clg_cap_f_of_temp.setCoefficient4y(0.00333)
        clg_cap_f_of_temp.setCoefficient5yPOW2(-0.00008)
        clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.00021)
        clg_cap_f_of_temp.setMinimumValueofx(17.0)
        clg_cap_f_of_temp.setMaximumValueofx(22.0)
        clg_cap_f_of_temp.setMinimumValueofy(13.0)
        clg_cap_f_of_temp.setMaximumValueofy(46.0)

        clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_cap_f_of_flow.setCoefficient1Constant(0.77136)
        clg_cap_f_of_flow.setCoefficient2x(0.34053)
        clg_cap_f_of_flow.setCoefficient3xPOW2(-0.11088)
        clg_cap_f_of_flow.setMinimumValueofx(0.75918)
        clg_cap_f_of_flow.setMaximumValueofx(1.13877)

        clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(1.23649)
        clg_energy_input_ratio_f_of_temp.setCoefficient2x(-0.02431)
        clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(0.00057)
        clg_energy_input_ratio_f_of_temp.setCoefficient4y(-0.01434)
        clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.00063)
        clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.00038)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofx(17.0)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofx(22.0)
        clg_energy_input_ratio_f_of_temp.setMinimumValueofy(13.0)
        clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.0)

        clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
        clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.20550)
        clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.32953)
        clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.12308)
        clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.75918)
        clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.13877)

        clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(model)
        clg_part_load_ratio.setCoefficient1Constant(0.77100)
        clg_part_load_ratio.setCoefficient2x(0.22900)
        clg_part_load_ratio.setCoefficient3xPOW2(0.0)
        clg_part_load_ratio.setMinimumValueofx(0.0)
        clg_part_load_ratio.setMaximumValueofx(1.0)

        clg_cap_f_of_temp_low_spd = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_cap_f_of_temp_low_spd.setCoefficient1Constant(0.42415)
        clg_cap_f_of_temp_low_spd.setCoefficient2x(0.04426)
        clg_cap_f_of_temp_low_spd.setCoefficient3xPOW2(-0.00042)
        clg_cap_f_of_temp_low_spd.setCoefficient4y(0.00333)
        clg_cap_f_of_temp_low_spd.setCoefficient5yPOW2(-0.00008)
        clg_cap_f_of_temp_low_spd.setCoefficient6xTIMESY(-0.00021)
        clg_cap_f_of_temp_low_spd.setMinimumValueofx(17.0)
        clg_cap_f_of_temp_low_spd.setMaximumValueofx(22.0)
        clg_cap_f_of_temp_low_spd.setMinimumValueofy(13.0)
        clg_cap_f_of_temp_low_spd.setMaximumValueofy(46.0)

        clg_energy_input_ratio_f_of_temp_low_spd = OpenStudio::Model::CurveBiquadratic.new(model)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient1Constant(1.23649)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient2x(-0.02431)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient3xPOW2(0.00057)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient4y(-0.01434)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient5yPOW2(0.00063)
        clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient6xTIMESY(-0.00038)
        clg_energy_input_ratio_f_of_temp_low_spd.setMinimumValueofx(17.0)
        clg_energy_input_ratio_f_of_temp_low_spd.setMaximumValueofx(22.0)
        clg_energy_input_ratio_f_of_temp_low_spd.setMinimumValueofy(13.0)
        clg_energy_input_ratio_f_of_temp_low_spd.setMaximumValueofy(46.0)

        clg_coil.setRatedLowSpeedSensibleHeatRatio(OpenStudio::OptionalDouble.new(0.69))
        clg_coil.setBasinHeaterCapacity(10)
        clg_coil.setBasinHeaterSetpointTemperature(2.0)
      end

      clg_coil.setTotalCoolingCapacityFunctionOfTemperatureCurve(clg_cap_f_of_temp) unless clg_cap_f_of_temp.nil?
      clg_coil.setTotalCoolingCapacityFunctionOfFlowFractionCurve(clg_cap_f_of_flow) unless clg_cap_f_of_flow.nil?
      clg_coil.setEnergyInputRatioFunctionOfTemperatureCurve(clg_energy_input_ratio_f_of_temp) unless clg_energy_input_ratio_f_of_temp.nil?
      clg_coil.setEnergyInputRatioFunctionOfFlowFractionCurve(clg_energy_input_ratio_f_of_flow) unless clg_energy_input_ratio_f_of_flow.nil?
      clg_coil.setPartLoadFractionCorrelationCurve(clg_part_load_ratio) unless clg_part_load_ratio.nil?
      clg_coil.setLowSpeedTotalCoolingCapacityFunctionOfTemperatureCurve(clg_cap_f_of_temp_low_spd) unless clg_cap_f_of_temp_low_spd.nil?
      clg_coil.setLowSpeedEnergyInputRatioFunctionOfTemperatureCurve(clg_energy_input_ratio_f_of_temp_low_spd) unless clg_energy_input_ratio_f_of_temp_low_spd.nil?

      return clg_coil
    end

    # Return the capacity in W of a CoilCoolingDXTwoSpeed
    #
    # @param coil_cooling_dx_two_speed [OpenStudio::Model::CoilCoolingDXTwoSpeed] coil cooling dx two speed object
    # @param multiplier [Double] zone multiplier, if applicable
    # @return [Double] capacity in W
    def self.coil_cooling_dx_two_speed_get_capacity(coil_cooling_dx_two_speed, multiplier: nil)
      capacity_w = nil
      if coil_cooling_dx_two_speed.ratedHighSpeedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_two_speed.ratedHighSpeedTotalCoolingCapacity.get
      elsif coil_cooling_dx_two_speed.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_two_speed.autosizedRatedHighSpeedTotalCoolingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_cooling_dx_two_speed', "For #{coil_cooling_dx_two_speed.name} capacity is not available.")
        return capacity_w
      end

      if !multiplier.nil? && multiplier > 1
        total_cap = capacity_w
        capacity_w /= multiplier
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.coil_cooling_dx_two_speed', "For #{coil_cooling_dx_two_speed.name}, total capacity of #{OpenStudio.convert(total_cap, 'W', 'kBtu/hr').get.round(2)}kBTU/hr was divided by the zone multiplier of #{multiplier} to give #{capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get.round(2)}kBTU/hr.")
      end

      return capacity_w
    end
  end
end
