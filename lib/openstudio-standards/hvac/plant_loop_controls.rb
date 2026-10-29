module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group PlantLoop:Controls
    # Methods to set Plant Loop controls

    # Returns standard chilled water loop design sizing temperatures
    #
    # @return [Hash] Hash of design sizing temperature lookups
    def self.standard_chilled_water_loop_design_sizing_temperatures
      dsgn_temps = {}
      dsgn_temps['dsgn_chw_temp_f'] = 44.0 # Loop design chilled water temperature (F)
      dsgn_temps['dsgn_chw_temp_delt_r'] = 10.1 # Loop design chilled water temperature (R)
      dsgn_temps['dsgn_chw_min_temp_f'] = 34.0 # Loop design minimum chilled water temperature (F)
      dsgn_temps['dsgn_chw_max_temp_f'] = 104.0 # Loop design maximum chilled water temperature (F)
      dsgn_temps['chw_out_temp_high_f'] = 80.0 # Chilled water temperature reset at high outdoor air temperature (F)
      dsgn_temps['chw_out_temp_low_f'] = 60.0 # Chilled water temperature reset at low outdoor air temperature (F)
      dsgn_temps['chw_out_high_setp_f'] = 44.0 # Chilled water setpoint temperature at high outdoor air temperature (F)
      dsgn_temps['chw_out_low_setp_f'] = 54.0 # Chilled water setpoint temperature at low outdoor air temperature (F)
      dsgn_temps['chw_low_temp_limit_f'] = 36.0 # Chiller leaving chilled water lower temperature limit (F)
      dsgn_temps['chw_cond_temp_f'] = 95.0 # Chiller entering condenser fluid temperature (F)

      return dsgn_temps
    end

    # Apply sizing and controls to chilled water loop
    #
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop
    # @param design_temperatures [Hash] a hash of design temperature lookups from standard_chilled_water_loop_design_sizing_temperatures
    # @param outdoor_air_reset [Boolean] whether to apply outdoor air temperature reset. Default is a false, using a constant setpoint supply water temperature.
    # @return [Boolean] returns true if successful, false if not
    def self.set_chilled_water_loop_system_sizing(chilled_water_loop, design_temperatures,
                                                  outdoor_air_reset: false)
      # chilled water loop sizing and controls
      dsgn_sup_wtr_temp_c = OpenStudio.convert(design_temperatures['dsgn_chw_temp_f'], 'F', 'C').get
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(design_temperatures['dsgn_chw_temp_delt_r'], 'R', 'K').get
      chilled_water_loop.setMinimumLoopTemperature(OpenStudio.convert(design_temperatures['dsgn_chw_min_temp_f'], 'F', 'C').get)
      chilled_water_loop.setMaximumLoopTemperature(OpenStudio.convert(design_temperatures['dsgn_chw_max_temp_f'], 'F', 'C').get)
      sizing_plant = chilled_water_loop.sizingPlant
      sizing_plant.setLoopType('Cooling')
      sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
      sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)

      if outdoor_air_reset
        # set up outdoor air temperature reset
        outdoor_high_temperature_c = OpenStudio.convert(design_temperatures['chw_out_temp_high_f'], 'F', 'C').get
        setpoint_temperature_outdoor_high_c = OpenStudio.convert(design_temperatures['chw_out_high_setp_f'], 'F', 'C').get
        outdoor_low_temperature_c = OpenStudio.convert(design_temperatures['chw_out_temp_low_f'], 'F', 'C').get
        setpoint_temperature_outdoor_low_c = OpenStudio.convert(design_temperatures['chw_out_low_setp_f'], 'F', 'C').get
        chw_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(chilled_water_loop.model)
        chw_stpt_manager.setOutdoorHighTemperature(outdoor_high_temperature_c) # Degrees Celsius
        chw_stpt_manager.setSetpointatOutdoorHighTemperature(setpoint_temperature_outdoor_high_c) # Degrees Celsius
        chw_stpt_manager.setOutdoorLowTemperature(outdoor_low_temperature_c) # Degrees Celsius
        chw_stpt_manager.setSetpointatOutdoorLowTemperature(setpoint_temperature_outdoor_low_c) # Degrees Celsius
      else
        chw_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(chilled_water_loop.model,
                                                                                       dsgn_sup_wtr_temp_c,
                                                                                       name: "#{chilled_water_loop.name} Temp - #{design_temperatures['dsgn_chw_temp_f'].round(0)}F",
                                                                                       schedule_type_limit: 'Temperature')
        chw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(chilled_water_loop.model, chw_temp_sch)
      end
      chw_stpt_manager.setName("#{chilled_water_loop.name} Setpoint Manager")
      chw_stpt_manager.addToNode(chilled_water_loop.supplyOutletNode)
      return true
    end
  end
end
