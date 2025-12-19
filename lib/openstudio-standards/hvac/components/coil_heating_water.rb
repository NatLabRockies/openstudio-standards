module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilHeatingWater object
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param hot_water_loop [<OpenStudio::Model::PlantLoop>] the coil will be placed on the demand side of this plant loop
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the coil, or nil in which case it will be defaulted
    # @param schedule [String] name of the availability schedule, or [<OpenStudio::Model::Schedule>] Schedule object, or nil in which case default to always on
    # @param rated_inlet_water_temperature [Double] rated inlet water temperature in degrees Celsius, default is hot water loop design exit temperature
    # @param rated_outlet_water_temperature [Double] rated outlet water temperature in degrees Celsius, default is hot water loop design return temperature
    # @param rated_inlet_air_temperature [Double] rated inlet air temperature in degrees Celsius, default is 16.6 (62F)
    # @param rated_outlet_air_temperature [Double] rated outlet air temperature in degrees Celsius, default is 32.2 (90F)
    # @param controller_convergence_tolerance [Double] controller convergence tolerance
    # @return [OpenStudio::Model::CoilHeatingWater] the heating coil
    def self.create_coil_heating_water(model,
                                       hot_water_loop,
                                       air_loop_node: nil,
                                       name: 'Htg Coil',
                                       schedule: nil,
                                       rated_inlet_water_temperature: nil,
                                       rated_outlet_water_temperature: nil,
                                       rated_inlet_air_temperature: 16.6,
                                       rated_outlet_air_temperature: 32.2,
                                       controller_convergence_tolerance: 0.1)
      htg_coil = OpenStudio::Model::CoilHeatingWater.new(model)

      # add to hot water loop
      hot_water_loop.addDemandBranchForComponent(htg_coil)

      # add to air loop if specified
      htg_coil.addToNode(air_loop_node) unless air_loop_node.nil?

      # set coil name
      if name.nil?
        htg_coil.setName('Htg Coil')
      else
        htg_coil.setName(name)
      end

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

      # rated water temperatures, use hot water loop temperatures if defined
      if rated_inlet_water_temperature.nil?
        rated_inlet_water_temperature = hot_water_loop.sizingPlant.designLoopExitTemperature
        htg_coil.setRatedInletWaterTemperature(rated_inlet_water_temperature)
      else
        htg_coil.setRatedInletWaterTemperature(rated_inlet_water_temperature)
      end
      if rated_outlet_water_temperature.nil?
        rated_outlet_water_temperature = rated_inlet_water_temperature - hot_water_loop.sizingPlant.loopDesignTemperatureDifference
        htg_coil.setRatedOutletWaterTemperature(rated_outlet_water_temperature)
      else
        htg_coil.setRatedOutletWaterTemperature(rated_outlet_water_temperature)
      end

      # rated air temperatures
      if rated_inlet_air_temperature.nil?
        htg_coil.setRatedInletAirTemperature(16.6)
      else
        htg_coil.setRatedInletAirTemperature(rated_inlet_air_temperature)
      end
      if rated_outlet_air_temperature.nil?
        htg_coil.setRatedOutletAirTemperature(32.2)
      else
        htg_coil.setRatedOutletAirTemperature(rated_outlet_air_temperature)
      end

      # coil controller properties
      # @note These inputs will get overwritten if addToNode or addDemandBranchForComponent is called on the htg_coil object after this
      htg_coil_controller = htg_coil.controllerWaterCoil.get
      htg_coil_controller.setName("#{htg_coil.name} Controller")
      htg_coil_controller.setMinimumActuatedFlow(0.0)
      htg_coil_controller.setControllerConvergenceTolerance(controller_convergence_tolerance) unless controller_convergence_tolerance.nil?

      return htg_coil
    end
  end
end
