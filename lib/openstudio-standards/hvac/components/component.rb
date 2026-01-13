module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component
    # Methods to create, modify, and get information about HVAC components

    # Returns the thermal zone associated with an HVAC component
    #
    # @param hvac_component [OpenStudio::Model::HVACComponent] HVAC component object
    # @return [OpenStudio::Model::ThermalZone] thermal zone object
    def self.hvac_component_get_thermal_zone(hvac_component)
      if hvac_component.to_ZoneHVACComponent.is_initialized
        hvac_component = hvac_component.to_ZoneHVACComponent.get
        if hvac_component.thermalZone.is_initialized
          return hvac_component.thermalZone.get
        end
      end

      if hvac_component.containingHVACComponent.is_initialized
        hvac_component = hvac_component.containingHVACComponent.get
        if hvac_component.to_AirLoopHVACUnitarySystem.is_initialized
          unitary = hvac_component.to_AirLoopHVACUnitarySystem.get
          if unitary.controllingZoneorThermostatLocation.is_initialized
            return unitary.controllingZoneorThermostatLocation.get
          end
        end
      end

      if hvac_component.containingZoneHVACComponent.is_initialized
        hvac_component = hvac_component.containingZoneHVACComponent.get
        if hvac_component.thermalZone.is_initialized
          return hvac_component.thermalZone.get
        end
      end

      return nil
    end
  end
end
