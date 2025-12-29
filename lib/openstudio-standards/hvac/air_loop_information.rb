module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group AirLoop:Information
    # Methods to get information on AirLoop objects

    # Returns whether air loop HVAC is a direct evaporative system
    #
    # @param air_loop_hvac [<OpenStudio::Model::AirLoopHVAC>] OpenStudio AirLoopHVAC object
    # @return [Boolean] returns true if successful, false if not
    def self.air_loop_hvac_direct_evap?(air_loop_hvac)
      # check if direct evap
      is_direct_evap = false
      air_loop_hvac.supplyComponents.each do |component|
        # Get the object type
        obj_type = component.iddObjectType.valueName.to_s
        case obj_type
        when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial'
          is_direct_evap = true
        end
      end
      return is_direct_evap
    end

    # Returns whether air loop HVAC is a unitary system
    #
    # @param air_loop_hvac [<OpenStudio::Model::AirLoopHVAC>] OpenStudio AirLoopHVAC object
    # @return [Boolean] returns true if air_loop_hvac is a unitary system, false if not
    def self.air_loop_hvac_unitary_system?(air_loop_hvac)
      # check if unitary system
      is_unitary_system = false
      air_loop_hvac.supplyComponents.each do |component|
        # Get the object type
        obj_type = component.iddObjectType.valueName.to_s
        case obj_type
        when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
          is_unitary_system = true
        end
      end
      return is_unitary_system
    end

    # Returns the unitary system minimum and maximum design temperatures
    #
    # @param unitary_system [<OpenStudio::Model::ModelObject>] OpenStudio ModelObject object
    # @return [Hash] returns as hash with 'min_temp' and 'max_temp' in degrees Fahrenheit
    def self.unitary_system_min_max_temperature_value(unitary_system)
      min_temp = nil
      max_temp = nil
      # Get the object type
      obj_type = unitary_system.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitarySystem'
        unitary_system = unitary_system.to_AirLoopHVACUnitarySystem.get
        if unitary_system.useDOASDXCoolingCoil
          min_temp = OpenStudio.convert(unitary_system.dOASDXCoolingCoilLeavingMinimumAirTemperature, 'C', 'F').get
        end
        if unitary_system.maximumSupplyAirTemperature.is_initialized
          max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperature.get, 'C', 'F').get
        end
      when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
        unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
        if unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.is_initialized
          max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.get, 'C', 'F').get
        end
      when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
        unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
        if unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.is_initialized
          max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.get, 'C', 'F').get
        end
      when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
        min_temp = OpenStudio.convert(unitary_system.minimumOutletAirTemperatureDuringCoolingOperation, 'C', 'F').get
        max_temp = OpenStudio.convert(unitary_system.maximumOutletAirTemperatureDuringHeatingOperation, 'C', 'F').get
      end

      return { 'min_temp' => min_temp, 'max_temp' => max_temp }
    end
  end
end
