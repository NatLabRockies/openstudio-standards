class ZEAEDGMultifamily < ASHRAE901
  # @!group HeatExchangerSensLat

  # Sets the minimum effectiveness of the heat exchanger
  def heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness(heat_exchanger_air_to_air_sensible_and_latent)
    # Assumed to be sensible and latent at all flow
    heat_exchanger_type = heat_exchanger_air_to_air_sensible_and_latent.heatExchangerType
    if heat_exchanger_air_to_air_sensible_and_latent.model.version < OpenStudio::VersionString.new('3.8.0')
      if heat_exchanger_type == 'Plate'
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100HeatingAirFlow(0.755)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100HeatingAirFlow(0.564)
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75HeatingAirFlow(0.791)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75HeatingAirFlow(0.625)
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100CoolingAirFlow(0.755)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100CoolingAirFlow(0.564)
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75CoolingAirFlow(0.791)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75CoolingAirFlow(0.625)
        heat_exchanger_air_to_air_sensible_and_latent.setNominalElectricPower(0.0)
      else # Rotary
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100HeatingAirFlow(0.75)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100HeatingAirFlow(0.74)
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75HeatingAirFlow(0.79)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75HeatingAirFlow(0.79)
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat100CoolingAirFlow(0.75)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat100CoolingAirFlow(0.74)
        heat_exchanger_air_to_air_sensible_and_latent.setSensibleEffectivenessat75CoolingAirFlow(0.78)
        heat_exchanger_air_to_air_sensible_and_latent.setLatentEffectivenessat75CoolingAirFlow(0.78)
      end
    else
      values = Hash.new{|hash, key| hash[key] = Hash.new}
      if heat_exchanger_type == 'Plate'
        values['Sensible Heating'][0.75] = 0.791
        values['Sensible Heating'][1.0] = 0.755
        values['Latent Heating'][0.75] = 0.625
        values['Latent Heating'][1.0] = 0.564
        values['Sensible Cooling'][0.75] = 0.791
        values['Sensible Cooling'][1.0] = 0.755
        values['Latent Cooling'][0.75] = 0.625
        values['Latent Cooling'][1.0] = 0.564
        heat_exchanger_air_to_air_sensible_and_latent.setNominalElectricPower(0.0)
      else
        values['Sensible Heating'][0.75] = 0.79
        values['Sensible Heating'][1.0] = 0.75
        values['Latent Heating'][0.75] = 0.79
        values['Latent Heating'][1.0] = 0.74
        values['Sensible Cooling'][0.75] = 0.78
        values['Sensible Cooling'][1.0] = 0.75
        values['Latent Cooling'][0.75] = 0.78
        values['Latent Cooling'][1.0] = 0.74
      end
      OpenstudioStandards::HVAC.heat_exchanger_air_to_air_set_effectiveness_values(heat_exchanger_air_to_air_sensible_and_latent, defaults: false, values: values)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.ze_aedg_multifamily.HeatExchangerAirToAirSensibleAndLatent', "For #{heat_exchanger_air_to_air_sensible_and_latent.name}, set sensible and latent effectiveness to #{heat_exchanger_type} values.")

    return true
  end
end
