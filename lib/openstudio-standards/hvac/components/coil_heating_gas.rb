module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Create CoilHeatingGas object
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param air_loop_node [<OpenStudio::Model::Node>] the coil will be placed on this node of the air loop
    # @param name [String] the name of the system, or nil in which case it will be defaulted
    # @param schedule [String] name of the availability schedule, or [<OpenStudio::Model::Schedule>] Schedule object, or nil in which case default to always on
    # @param nominal_capacity [Double] rated nominal capacity
    # @param efficiency [Double] rated heating efficiency
    # @return [OpenStudio::Model::CoilHeatingGas] the gas heating coil
    def self.create_coil_heating_gas(model,
                                     air_loop_node: nil,
                                     name: 'Gas Htg Coil',
                                     schedule: nil,
                                     nominal_capacity: nil,
                                     efficiency: 0.80)
      htg_coil = OpenStudio::Model::CoilHeatingGas.new(model)

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

      # set capacity
      htg_coil.setNominalCapacity(nominal_capacity) unless nominal_capacity.nil?

      # set efficiency
      htg_coil.setGasBurnerEfficiency(efficiency)

      # defaults
      if model.version < OpenStudio::VersionString.new('3.7.0')
        htg_coil.setParasiticElectricLoad(0.0)
        htg_coil.setParasiticGasLoad(0.0)
      else
        htg_coil.setOnCycleParasiticElectricLoad(0.0)
        htg_coil.setOffCycleParasiticGasLoad(0.0)
      end

      return htg_coil
    end

    # Return the capacity in W of a CoilHeatingGas
    #
    # @param coil_heating_gas [OpenStudio::Model::CoilHeatingGas] coil heating gas object
    # @param multiplier [Double] zone multiplier, if applicable
    # @return [Double] capacity in W
    def self.coil_heating_gas_get_capacity(coil_heating_gas, multiplier: nil)
      capacity_w = nil
      if coil_heating_gas.nominalCapacity.is_initialized
        capacity_w = coil_heating_gas.nominalCapacity.get
      elsif coil_heating_gas.autosizedNominalCapacity.is_initialized
        capacity_w = coil_heating_gas.autosizedNominalCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_heating_gas', "For #{coil_heating_gas.name} capacity is not available.")
        return capacity_w
      end

      if !multiplier.nil? && multiplier > 1
        total_cap = capacity_w
        capacity_w /= multiplier
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.coil_heating_gas', "For #{coil_heating_gas.name}, total capacity of #{OpenStudio.convert(total_cap, 'W', 'kBtu/hr').get.round(2)}kBTU/hr was divided by the zone multiplier of #{multiplier} to give #{capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get.round(2)}kBTU/hr.")
      end

      return capacity_w
    end
  end
end
