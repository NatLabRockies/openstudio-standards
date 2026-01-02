module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilCoolingWaterToAirHeatPumpEquationFit object
    # Enters in default curves for coil by type of coil
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param plant_loop [<OpenStudio::Model::PlantLoop>] the coil will be placed on the demand side of this plant loop
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the system, or nil in which case it will be defaulted
    # @param type [String] the type of coil to reference the correct curve set
    # @param cop [Double] rated cooling coefficient of performance
    # @return [OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit] the cooling coil
    def self.create_coil_cooling_water_to_air_heat_pump_equation_fit(model,
                                                                     plant_loop,
                                                                     air_loop_node: nil,
                                                                     name: 'Water-to-Air HP Clg Coil',
                                                                     type: nil,
                                                                     cop: 3.4)
      clg_coil = OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit.new(model)

      # add to air loop if specified
      clg_coil.addToNode(air_loop_node) unless air_loop_node.nil?

      # set coil name
      clg_coil.setName(name)

      # add to plant loop
      if plant_loop.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.HVAC', 'No plant loop supplied for cooling coil')
        return false
      end
      plant_loop.addDemandBranchForComponent(clg_coil)

      # set coil cop
      if cop.nil?
        clg_coil.setRatedCoolingCoefficientofPerformance(3.4)
      else
        clg_coil.setRatedCoolingCoefficientofPerformance(cop)
      end

      # curve sets
      if type == 'OS default'
        # use OS default curves
      else # default curve set
        if model.version < OpenStudio::VersionString.new('3.2.0')
          clg_coil.setTotalCoolingCapacityCoefficient1(-4.30266987344639)
          clg_coil.setTotalCoolingCapacityCoefficient2(7.18536990534372)
          clg_coil.setTotalCoolingCapacityCoefficient3(-2.23946714486189)
          clg_coil.setTotalCoolingCapacityCoefficient4(0.139995928440879)
          clg_coil.setTotalCoolingCapacityCoefficient5(0.102660179888915)
          clg_coil.setSensibleCoolingCapacityCoefficient1(6.0019444814887)
          clg_coil.setSensibleCoolingCapacityCoefficient2(22.6300677244073)
          clg_coil.setSensibleCoolingCapacityCoefficient3(-26.7960783730934)
          clg_coil.setSensibleCoolingCapacityCoefficient4(-1.72374720346819)
          clg_coil.setSensibleCoolingCapacityCoefficient5(0.490644802367817)
          clg_coil.setSensibleCoolingCapacityCoefficient6(0.0693119353468141)
          clg_coil.setCoolingPowerConsumptionCoefficient1(-5.67775976415698)
          clg_coil.setCoolingPowerConsumptionCoefficient2(0.438988156976704)
          clg_coil.setCoolingPowerConsumptionCoefficient3(5.845277342193)
          clg_coil.setCoolingPowerConsumptionCoefficient4(0.141605667000125)
          clg_coil.setCoolingPowerConsumptionCoefficient5(-0.168727936032429)
        else
          if model.getCurveByName('Water to Air Heat Pump Total Cooling Capacity Curve').is_initialized
            total_cooling_capacity_curve = model.getCurveByName('Water to Air Heat Pump Total Cooling Capacity Curve').get
            total_cooling_capacity_curve = total_cooling_capacity_curve.to_CurveQuadLinear.get
          else
            total_cooling_capacity_curve = OpenStudio::Model::CurveQuadLinear.new(model)
            total_cooling_capacity_curve.setName('Water to Air Heat Pump Total Cooling Capacity Curve')
            total_cooling_capacity_curve.setCoefficient1Constant(-4.30266987344639)
            total_cooling_capacity_curve.setCoefficient2w(7.18536990534372)
            total_cooling_capacity_curve.setCoefficient3x(-2.23946714486189)
            total_cooling_capacity_curve.setCoefficient4y(0.139995928440879)
            total_cooling_capacity_curve.setCoefficient5z(0.102660179888915)
            total_cooling_capacity_curve.setMinimumValueofw(-100)
            total_cooling_capacity_curve.setMaximumValueofw(100)
            total_cooling_capacity_curve.setMinimumValueofx(-100)
            total_cooling_capacity_curve.setMaximumValueofx(100)
            total_cooling_capacity_curve.setMinimumValueofy(0)
            total_cooling_capacity_curve.setMaximumValueofy(100)
            total_cooling_capacity_curve.setMinimumValueofz(0)
            total_cooling_capacity_curve.setMaximumValueofz(100)
          end
          clg_coil.setTotalCoolingCapacityCurve(total_cooling_capacity_curve)

          if model.getCurveByName('Water to Air Heat Pump Sensible Cooling Capacity Curve').is_initialized
            sensible_cooling_capacity_curve = model.getCurveByName('Water to Air Heat Pump Sensible Cooling Capacity Curve').get
            sensible_cooling_capacity_curve = sensible_cooling_capacity_curve.to_CurveQuintLinear.get
          else
            sensible_cooling_capacity_curve = OpenStudio::Model::CurveQuintLinear.new(model)
            sensible_cooling_capacity_curve.setName('Water to Air Heat Pump Sensible Cooling Capacity Curve')
            sensible_cooling_capacity_curve.setCoefficient1Constant(6.0019444814887)
            sensible_cooling_capacity_curve.setCoefficient2v(22.6300677244073)
            sensible_cooling_capacity_curve.setCoefficient3w(-26.7960783730934)
            sensible_cooling_capacity_curve.setCoefficient4x(-1.72374720346819)
            sensible_cooling_capacity_curve.setCoefficient5y(0.490644802367817)
            sensible_cooling_capacity_curve.setCoefficient6z(0.0693119353468141)
            sensible_cooling_capacity_curve.setMinimumValueofw(-100)
            sensible_cooling_capacity_curve.setMaximumValueofw(100)
            sensible_cooling_capacity_curve.setMinimumValueofx(-100)
            sensible_cooling_capacity_curve.setMaximumValueofx(100)
            sensible_cooling_capacity_curve.setMinimumValueofy(0)
            sensible_cooling_capacity_curve.setMaximumValueofy(100)
            sensible_cooling_capacity_curve.setMinimumValueofz(0)
            sensible_cooling_capacity_curve.setMaximumValueofz(100)
          end
          clg_coil.setSensibleCoolingCapacityCurve(sensible_cooling_capacity_curve)

          if model.getCurveByName('Water to Air Heat Pump Cooling Power Consumption Curve').is_initialized
            cooling_power_consumption_curve = model.getCurveByName('Water to Air Heat Pump Cooling Power Consumption Curve').get
            cooling_power_consumption_curve = cooling_power_consumption_curve.to_CurveQuadLinear.get
          else
            cooling_power_consumption_curve = OpenStudio::Model::CurveQuadLinear.new(model)
            cooling_power_consumption_curve.setName('Water to Air Heat Pump Cooling Power Consumption Curve')
            cooling_power_consumption_curve.setCoefficient1Constant(-5.67775976415698)
            cooling_power_consumption_curve.setCoefficient2w(0.438988156976704)
            cooling_power_consumption_curve.setCoefficient3x(5.845277342193)
            cooling_power_consumption_curve.setCoefficient4y(0.141605667000125)
            cooling_power_consumption_curve.setCoefficient5z(-0.168727936032429)
            cooling_power_consumption_curve.setMinimumValueofw(-100)
            cooling_power_consumption_curve.setMaximumValueofw(100)
            cooling_power_consumption_curve.setMinimumValueofx(-100)
            cooling_power_consumption_curve.setMaximumValueofx(100)
            cooling_power_consumption_curve.setMinimumValueofy(0)
            cooling_power_consumption_curve.setMaximumValueofy(100)
            cooling_power_consumption_curve.setMinimumValueofz(0)
            cooling_power_consumption_curve.setMaximumValueofz(100)
          end
          clg_coil.setCoolingPowerConsumptionCurve(cooling_power_consumption_curve)
        end

        # part load fraction correlation curve added as a required curve in OS v3.7.0
        if model.version > OpenStudio::VersionString.new('3.6.1')
          if model.getCurveByName('Water to Air Heat Pump Part Load Fraction Correlation Curve').is_initialized
            part_load_correlation_curve = model.getCurveByName('Water to Air Heat Pump Part Load Fraction Correlation Curve').get
            part_load_correlation_curve = part_load_correlation_curve.to_CurveLinear.get
          else
            part_load_correlation_curve = OpenStudio::Model::CurveLinear.new(model)
            part_load_correlation_curve.setName('Water to Air Heat Pump Part Load Fraction Correlation Curve')
            part_load_correlation_curve.setCoefficient1Constant(0.833746458696111)
            part_load_correlation_curve.setCoefficient2x(0.166253541303889)
            part_load_correlation_curve.setMinimumValueofx(0)
            part_load_correlation_curve.setMaximumValueofx(1)
            part_load_correlation_curve.setMinimumCurveOutput(0)
            part_load_correlation_curve.setMaximumCurveOutput(1)
          end
          clg_coil.setPartLoadFractionCorrelationCurve(part_load_correlation_curve)
        end
      end

      return clg_coil
    end

    # Return the capacity in W of a CoilCoolingWaterToAirHeatPumpEquationFit
    #
    # @param coil_cooling_water_to_air_heat_pump [OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit] coil cooling object
    # @param multiplier [Double] zone multiplier, if applicable
    # @return [Double] capacity in W
    def self.coil_cooling_water_to_air_heat_pump_get_capacity(coil_cooling_water_to_air_heat_pump, multiplier: nil)
      capacity_w = nil
      if coil_cooling_water_to_air_heat_pump.ratedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_water_to_air_heat_pump.ratedTotalCoolingCapacity.get
      elsif coil_cooling_water_to_air_heat_pump.autosizedRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_water_to_air_heat_pump.autosizedRatedTotalCoolingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_cooling_water_to_air_heat_pump_equation_fit', "For #{coil_cooling_water_to_air_heat_pump.name} capacity is not available.")
        return capacity_w
      end

      if !multiplier.nil? && multiplier > 1
        total_cap = capacity_w
        capacity_w /= multiplier
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.coil_cooling_water_to_air_heat_pump', "For #{coil_cooling_dx_twcoil_cooling_water_to_air_heat_pumpo_speed.name}, total capacity of #{OpenStudio.convert(total_cap, 'W', 'kBtu/hr').get.round(2)}kBTU/hr was divided by the zone multiplier of #{multiplier} to give #{capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get.round(2)}kBTU/hr.")
      end

      return capacity_w
    end
  end
end
