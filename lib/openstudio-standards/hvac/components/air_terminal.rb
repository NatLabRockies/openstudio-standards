module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Air Terminal
    # Methods to create, modify, and get information about air terminals

    # Determines whether the terminal has a NaturalGas, Electricity, or HotWater reheat coil.
    #
    # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
    # @return [String] reheat type. One of NaturalGas, Electricity, or HotWater.
    def self.air_terminal_single_duct_vav_reheat_reheat_type(air_terminal_single_duct_vav_reheat)
      type = nil

      if air_terminal_single_duct_vav_reheat.to_AirTerminalSingleDuctVAVNoReheat.is_initialized
        return type
      end

      # Get the reheat coil
      rht_coil = air_terminal_single_duct_vav_reheat.reheatCoil
      if rht_coil.to_CoilHeatingElectric.is_initialized
        type = 'Electricity'
      elsif rht_coil.to_CoilHeatingWater.is_initialized
        type = 'HotWater'
      elsif rht_coil.to_CoilHeatingGas.is_initialized
        type = 'NaturalGas'
      end

      return type
    end
  end
end
