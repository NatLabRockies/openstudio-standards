module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilCoolingWater object
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param chilled_water_loop [<OpenStudio::Model::PlantLoop>] the coil will be placed on the demand side of this plant loop
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the coil, or nil in which case it will be defaulted
    # @param schedule [String] name of the availability schedule, or [<OpenStudio::Model::Schedule>] Schedule object, or nil in which case default to always on
    # @param design_inlet_water_temperature [Double] design inlet water temperature in degrees Celsius, default is nil
    # @param design_inlet_air_temperature [Double] design inlet air temperature in degrees Celsius, default is nil
    # @param design_outlet_air_temperature [Double] design outlet air temperature in degrees Celsius, default is nil
    # @return [OpenStudio::Model::CoilCoolingWater] the cooling coil
    def self.create_coil_cooling_water(model,
                                       chilled_water_loop,
                                       air_loop_node: nil,
                                       name: 'Clg Coil',
                                       schedule: nil,
                                       design_inlet_water_temperature: nil,
                                       design_inlet_air_temperature: nil,
                                       design_outlet_air_temperature: nil)
      clg_coil = OpenStudio::Model::CoilCoolingWater.new(model)

      # add to chilled water loop
      chilled_water_loop.addDemandBranchForComponent(clg_coil)

      # add to air loop if specified
      clg_coil.addToNode(air_loop_node) unless air_loop_node.nil?

      # set coil name
      if name.nil?
        clg_coil.setName('Clg Coil')
      else
        clg_coil.setName(name)
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
      clg_coil.setAvailabilitySchedule(coil_availability_schedule)

      # rated temperatures
      if design_inlet_water_temperature.nil?
        clg_coil.autosizeDesignInletWaterTemperature
      else
        clg_coil.setDesignInletWaterTemperature(design_inlet_water_temperature)
      end
      clg_coil.setDesignInletAirTemperature(design_inlet_air_temperature) unless design_inlet_air_temperature.nil?
      clg_coil.setDesignOutletAirTemperature(design_outlet_air_temperature) unless design_outlet_air_temperature.nil?

      # defaults
      clg_coil.setHeatExchangerConfiguration('CrossFlow')

      # coil controller properties
      # @note These inputs will get overwritten if addToNode or addDemandBranchForComponent is called on the htg_coil object after this
      clg_coil_controller = clg_coil.controllerWaterCoil.get
      clg_coil_controller.setName("#{clg_coil.name} Controller")
      clg_coil_controller.setAction('Reverse')
      clg_coil_controller.setMinimumActuatedFlow(0.0)

      return clg_coil
    end
  end
end
