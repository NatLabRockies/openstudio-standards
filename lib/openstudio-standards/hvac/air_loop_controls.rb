module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group AirLoop:Controls
    # Methods to set Air Loop HVAC controls

    # Sets the air loop system sizing parameters
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @param design_temperatures [Hash] a hash of design temperature lookups from standard_design_sizing_temperatures
    # @param type_of_load_sizing [String] type of load to size on
    # @param minimum_system_airflow_ratio [Double] minimum system airflow ratio, between 0 and 1
    # @param sizing_option [String] sizing option. Options are 'Coincident' and 'NonCoincident'
    # @return [OpenStudio::Model::SizingSystem] sizing system object
    def self.set_air_loop_system_sizing(air_loop_hvac,
                                        design_temperatures,
                                        type_of_load_sizing: 'Sensible',
                                        minimum_system_airflow_ratio: 0.3,
                                        sizing_option: 'Coincident')
      # adjust sizing system defaults
      sizing_system = air_loop_hvac.sizingSystem
      sizing_system.setTypeofLoadtoSizeOn(type_of_load_sizing)
      sizing_system.autosizeDesignOutdoorAirFlowRate
      sizing_system.setPreheatDesignTemperature(design_temperatures['prehtg_dsgn_sup_air_temp_c'])
      sizing_system.setPrecoolDesignTemperature(design_temperatures['preclg_dsgn_sup_air_temp_c'])
      sizing_system.setCentralCoolingDesignSupplyAirTemperature(design_temperatures['clg_dsgn_sup_air_temp_c'])
      sizing_system.setCentralHeatingDesignSupplyAirTemperature(design_temperatures['htg_dsgn_sup_air_temp_c'])
      sizing_system.setPreheatDesignHumidityRatio(0.008)
      sizing_system.setPrecoolDesignHumidityRatio(0.008)
      sizing_system.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      sizing_system.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      if air_loop_hvac.model.version < OpenStudio::VersionString.new('2.7.0')
        sizing_system.setMinimumSystemAirFlowRatio(minimum_system_airflow_ratio)
      else
        sizing_system.setCentralHeatingMaximumSystemAirFlowRatio(minimum_system_airflow_ratio)
      end
      sizing_system.setSizingOption(sizing_option)
      sizing_system.setAllOutdoorAirinCooling(false)
      sizing_system.setAllOutdoorAirinHeating(false)
      sizing_system.setSystemOutdoorAirMethod('ZoneSum')
      sizing_system.setCoolingDesignAirFlowMethod('DesignDay')
      sizing_system.setHeatingDesignAirFlowMethod('DesignDay')

      return sizing_system
    end
  end
end
