class Standard
  # @!group WaterHeaterMixed

  # Applies the standard efficiency ratings and typical losses and paraisitic loads to this object.
  # Efficiency and skin loss coefficient (UA)
  # Per PNNL http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf
  # Appendix A: Service Water Heating
  #
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @return [Boolean] returns true if successful, false if not
  def water_heater_mixed_apply_efficiency(water_heater_mixed)
    # @todo remove this once workaround for HPWHs is removed
    if water_heater_mixed.partLoadFactorCurve.is_initialized && water_heater_mixed.partLoadFactorCurve.get.name.get.include?('HPWH_COP')
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, the workaround for HPWHs has been applied, efficiency will not be changed.")
      return true
    end

    # get number of water heaters
    if water_heater_mixed.additionalProperties.getFeatureAsInteger('component_quantity').is_initialized
      comp_qty = water_heater_mixed.additionalProperties.getFeatureAsInteger('component_quantity').get
    else
      comp_qty = 1
    end

    # Get the capacity of the water heater
    # @todo add capability to pull autosized water heater capacity
    # if the Sizing:WaterHeater object is ever implemented in OpenStudio.
    capacity_w = water_heater_mixed.heaterMaximumCapacity
    if capacity_w.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot find capacity, standard will not be applied.")
      return false
    else
      capacity_w = capacity_w.get / comp_qty
    end
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # Get the volume of the water heater
    # @todo add capability to pull autosized water heater volume
    # if the Sizing:WaterHeater object is ever implemented in OpenStudio.
    volume_m3 = water_heater_mixed.tankVolume
    if volume_m3.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot find volume, standard will not be applied.")
      return false
    else
      volume_m3 = @instvarbuilding_type == 'MidriseApartment' ? volume_m3.get / 23 : volume_m3.get / comp_qty
    end
    volume_gal = OpenStudio.convert(volume_m3, 'm^3', 'gal').get

    # Get the heater fuel type
    fuel_type = water_heater_mixed.heaterFuelType
    unless fuel_type == 'NaturalGas' || fuel_type == 'Electricity'
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, fuel type of #{fuel_type} is not yet supported, standard will not be applied.")
    end

    wh_props = water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
    return false if wh_props == {}

    # Calculate the water heater efficiency and
    # skin loss coefficient (UA) using different methods,
    # depending on the metrics specified by the standard
    water_heater_efficiency = nil
    ua_btu_per_hr_per_f = nil

    if wh_props['thermal_efficiency'] && !wh_props['standby_loss_capacity_allowance']
      thermal_efficiency = wh_props['thermal_efficiency']
      water_heater_efficiency = thermal_efficiency
      # Fixed UA
      ua_btu_per_hr_per_f = 11.37
    end

    # Typically specified this way for small electric water heaters
    # and small natural gas water heaters
    if wh_props['energy_factor_base'] && wh_props['energy_factor_volume_derate']
      # Calculate the energy factor (EF)
      base_energy_factor = wh_props['energy_factor_base']
      vol_drt = wh_props['energy_factor_volume_derate']
      energy_factor = base_energy_factor - (vol_drt * volume_gal)
      water_heater_efficiency, ua_btu_per_hr_per_f = water_heater_convert_energy_factor_to_thermal_efficiency_and_ua(fuel_type, energy_factor, capacity_btu_per_hr)
      # Two booster water heaters
      ua_btu_per_hr_per_f = water_heater_mixed.name.to_s.include?('Booster') ? ua_btu_per_hr_per_f * 2 : ua_btu_per_hr_per_f
    end

    if (wh_props['uniform_energy_factor_base'] && wh_props['uniform_energy_factor_volume_allowance']) || wh_props['uniform_energy_factor']
      if wh_props['uniform_energy_factor']
        uniform_energy_factor = wh_props['uniform_energy_factor']
      else
        base_uniform_energy_factor = wh_props['uniform_energy_factor_base']
        vol_drt = wh_props['uniform_energy_factor_volume_allowance']
        uniform_energy_factor = base_uniform_energy_factor - (vol_drt * volume_gal)
      end
      energy_factor = water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater_mixed, fuel_type, uniform_energy_factor, capacity_btu_per_hr, volume_gal)
      water_heater_efficiency, ua_btu_per_hr_per_f = water_heater_convert_energy_factor_to_thermal_efficiency_and_ua(fuel_type, energy_factor, capacity_btu_per_hr)
      # Two booster water heaters
      ua_btu_per_hr_per_f = water_heater_mixed.name.to_s.include?('Booster') ? ua_btu_per_hr_per_f * 2 : ua_btu_per_hr_per_f
    end

    # Typically specified this way for large electric water heaters
    if wh_props['standby_loss_base'] && (wh_props['standby_loss_volume_allowance'] || wh_props['standby_loss_square_root_volume_allowance'])
      # Fixed water heater efficiency per PNNL
      water_heater_efficiency = 1.0
      # Calculate the max allowable standby loss (SL)
      sl_base = wh_props['standby_loss_base']
      if wh_props['standby_loss_square_root_volume_allowance']
        sl_drt = wh_props['standby_loss_square_root_volume_allowance']
        sl_btu_per_hr = sl_base + (sl_drt * Math.sqrt(volume_gal))
      else # standby_loss_volume_allowance
        sl_drt = wh_props['standby_loss_volume_allowance']
        sl_btu_per_hr = sl_base + (sl_drt * volume_gal)
      end
      # Calculate the skin loss coefficient (UA)
      ua_btu_per_hr_per_f = @instvarbuilding_type == 'MidriseApartment' ? sl_btu_per_hr / 70 * 23 :  sl_btu_per_hr / 70
      ua_btu_per_hr_per_f = water_heater_mixed.name.to_s.include?('Booster') ? ua_btu_per_hr_per_f * 2 : ua_btu_per_hr_per_f
    end

    # Typically specified this way for newer large electric water heaters
    if wh_props['hourly_loss_base'] && wh_props['hourly_loss_volume_allowance']
      # Fixed water heater efficiency per PNNL
      water_heater_efficiency = 1.0
      # Calculate the percent loss per hr
      hr_loss_base = wh_props['hourly_loss_base']
      hr_loss_allow = wh_props['hourly_loss_volume_allowance']
      hrly_loss_pct = hr_loss_base + (hr_loss_allow / volume_gal)
      # Convert to Btu/hr, assuming:
      # Water at 120F, density = 8.25 lb/gal
      # 1 Btu to raise 1 lb of water 1 F
      # Therefore 8.25 Btu / gal of water * deg F
      # 70F delta-T between water and zone
      hrly_loss_btu_per_hr = (hrly_loss_pct / 100) * volume_gal * 8.25 * 70
      # Calculate the skin loss coefficient (UA)
      ua_btu_per_hr_per_f = hrly_loss_btu_per_hr / 70
    end

    # Typically specified this way for large natural gas water heaters
    if wh_props['standby_loss_capacity_allowance'] && (wh_props['standby_loss_volume_allowance'] || wh_props['standby_loss_square_root_volume_allowance']) && wh_props['thermal_efficiency']
      sl_cap_adj = wh_props['standby_loss_capacity_allowance']
      if !wh_props['standby_loss_volume_allowance'].nil?
        sl_vol_drt = wh_props['standby_loss_volume_allowance']
      elsif !wh_props['standby_loss_square_root_volume_allowance'].nil?
        sl_vol_drt = wh_props['standby_loss_square_root_volume_allowance']
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, could not retrieve the standby loss volume allowance.")
        return false
      end
      et = wh_props['thermal_efficiency']
      # Estimate storage tank volume
      tank_volume = volume_gal > 100 ? (volume_gal - 100).round(0) : 0
      wh_tank_volume = [volume_gal, 100].min
      # SL Storage Tank: polynomial regression based on a set of manufacturer data
      sl_tank = (0.0000005 * (tank_volume**3)) - (0.001 * (tank_volume**2)) + (1.3519 * tank_volume) + 64.456 # in Btu/h
      # Calculate the max allowable standby loss (SL)
      # Output capacity is assumed to be 10 * Tank volume
      # Input capacity = Output capacity / Et
      p_on = capacity_btu_per_hr / et
      sl_btu_per_hr = (p_on / sl_cap_adj) + (sl_vol_drt * Math.sqrt(wh_tank_volume)) + sl_tank
      # Calculate the skin loss coefficient (UA)
      ua_btu_per_hr_per_f = (sl_btu_per_hr * et) / 70
      # Calculate water heater efficiency
      water_heater_efficiency = ((ua_btu_per_hr_per_f * 70) + (p_on * et)) / p_on
    end

    # Ensure that efficiency and UA were both set\
    if water_heater_efficiency.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot calculate efficiency, cannot apply efficiency standard.")
      return false
    end

    if ua_btu_per_hr_per_f.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot calculate UA, cannot apply efficiency standard.")
      return false
    end

    # Convert to SI
    ua_w_per_k = OpenStudio.convert(ua_btu_per_hr_per_f, 'Btu/hr*R', 'W/K').get
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, skin-loss UA = #{ua_w_per_k} W/K.")

    # Set the water heater properties
    # Efficiency
    water_heater_mixed.setHeaterThermalEfficiency(water_heater_efficiency)
    # Skin loss
    water_heater_mixed.setOffCycleLossCoefficienttoAmbientTemperature(ua_w_per_k)
    water_heater_mixed.setOnCycleLossCoefficienttoAmbientTemperature(ua_w_per_k)
    # @todo Parasitic loss (pilot light)
    # PNNL document says pilot lights were removed, but IDFs
    # still have the on/off cycle parasitic fuel consumptions filled in
    water_heater_mixed.setOnCycleParasiticFuelType(fuel_type)
    # self.setOffCycleParasiticFuelConsumptionRate(??)
    water_heater_mixed.setOnCycleParasiticHeatFractiontoTank(0)
    water_heater_mixed.setOffCycleParasiticFuelType(fuel_type)
    # self.setOffCycleParasiticFuelConsumptionRate(??)
    water_heater_mixed.setOffCycleParasiticHeatFractiontoTank(0)

    # Append the name with standards information
    water_heater_mixed.setName("#{water_heater_mixed.name} #{water_heater_efficiency.round(3)} Therm Eff")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.WaterHeaterMixed', "For #{template}: #{water_heater_mixed.name}; thermal efficiency = #{water_heater_efficiency.round(3)}, skin-loss UA = #{ua_btu_per_hr_per_f.round}Btu/hr-R")

    return true
  end

  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] OpenStudio WaterHeaterMixed object
  # @param fuel_type [Float] water heater fuel type
  # @param capacity_btu_per_hr [Float] water heater capacity in Btu/h
  # @param volume_gal [Float] water heater gallons of storage
  # @return [Hash] returns a hash wwith the applicable efficiency requirements
  def water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
    # Get the water heater properties
    search_criteria = {}
    search_criteria['template'] = template
    search_criteria['fuel_type'] = fuel_type
    search_criteria['equipment_type'] = 'Storage Water Heaters'

    # Search base on capacity first
    wh_props_capacity = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr)
    wh_props_capacity_and_volume = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal.round(0))
    wh_props_capacity_and_capacity_btu_per_hr = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, nil, capacity_btu_per_hr)
    wh_props_capacity_and_volume_and_capacity_per_volume = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal, capacity_btu_per_hr / volume_gal)

    # We consider that the lookup is successful if only one set of record is returned
    if wh_props_capacity.size == 1
      wh_props = wh_props_capacity[0]
    elsif wh_props_capacity_and_volume.size == 1
      wh_props = wh_props_capacity_and_volume[0]
    elsif wh_props_capacity_and_capacity_btu_per_hr == 1
      wh_props = wh_props_capacity_and_capacity_btu_per_hr[0]
    elsif wh_props_capacity_and_volume_and_capacity_per_volume == 1
      wh_props = wh_props_capacity_and_volume_and_capacity_per_volume[0]
    else
      # Search again with additional criteria
      search_criteria = water_heater_mixed_additional_search_criteria(water_heater_mixed, search_criteria)
      wh_props_capacity = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr)
      wh_props_capacity_and_volume = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal.round(0))
      wh_props_capacity_and_capacity_btu_per_hr = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, nil, capacity_btu_per_hr)
      wh_props_capacity_and_volume_and_capacity_per_volume = model_find_objects(standards_data['water_heaters'], search_criteria, capacity_btu_per_hr, nil, nil, nil, nil, volume_gal, capacity_btu_per_hr / volume_gal)
      if wh_props_capacity.size == 1
        wh_props = wh_props_capacity[0]
      elsif wh_props_capacity_and_volume.size == 1
        wh_props = wh_props_capacity_and_volume[0]
      elsif wh_props_capacity_and_capacity_btu_per_hr == 1
        wh_props = wh_props_capacity_and_capacity_btu_per_hr[0]
      elsif wh_props_capacity_and_volume_and_capacity_per_volume == 1
        wh_props = wh_props_capacity_and_volume_and_capacity_per_volume[0]
      else
        return {}
      end
    end

    return wh_props
  end

  # Applies the correct fuel type for the water heaters
  # in the baseline model.  For most standards and for most building
  # types, the baseline uses the same fuel type as the proposed.
  #
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @param building_type [String] the building type
  # @return [Boolean] returns true if successful, false if not
  def water_heater_mixed_apply_prm_baseline_fuel_type(water_heater_mixed, building_type)
    # baseline is same as proposed per Table G3.1 item 11.b
    return true # Do nothing
  end

  # Finds capacity in Btu/hr
  #
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @return [Double] capacity in Btu/hr to be used for find object
  def water_heater_mixed_find_capacity(water_heater_mixed)
    # Get the coil capacity
    capacity_w = nil
    if water_heater_mixed.heaterMaximumCapacity.is_initialized
      capacity_w = water_heater_mixed.heaterMaximumCapacity.get
    elsif water_heater_mixed.autosizedHeaterMaximumCapacity.is_initialized
      capacity_w = water_heater_mixed.autosizedHeaterMaximumCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name} capacity is not available.")
      return false
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    return capacity_btu_per_hr
  end

  # Get water heater sub type
  #
  # @param fuel_type [String] water heater fuel type
  # @param capacity_btu_per_hr [Float] water heater capacity
  # @param volume_gal [Float] water heater storage volume in gallons
  # @return [String] returns water heater sub type
  def water_heater_determine_sub_type(fuel_type, capacity_btu_per_hr, volume_gal)
    sub_type = nil
    capacity_w = OpenStudio.convert(capacity_btu_per_hr, 'Btu/hr', 'W').get
    # source: https://energycodeace.com/site/custom/public/reference-ace-2019/index.html#!Documents/52residentialwaterheatingequipment.htm
    if (fuel_type == 'NaturalGas' && capacity_btu_per_hr <= 75_000 && (volume_gal >= 20 && volume_gal <= 100)) ||
       (fuel_type == 'Electricity' && capacity_w <= 12_000 && (volume_gal >= 20 && volume_gal <= 120))
      sub_type = 'consumer_storage'
    elsif (fuel_type == 'NaturalGas' && capacity_btu_per_hr < 105_000 && volume_gal < 120) ||
          (fuel_type == 'Oil' && capacity_btu_per_hr < 140_000 && volume_gal < 120) ||
          (fuel_type == 'Electricity' && capacity_w < 58_600 && volume_gal <= 2)
      sub_type = 'residential_duty'
    elsif volume_gal <= 2
      sub_type = 'instantaneous'
    end

    return sub_type
  end

  # Convert Uniform Energy Factor (UEF) to Energy Factor (EF)
  #
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @param fuel_type [String] water heater fuel type
  # @param uniform_energy_factor [Float] water heater Uniform Energy Factor (UEF)
  # @param capacity_btu_per_hr [Float] water heater capacity
  # @param volume_gal [Float] water heater storage volume in gallons
  # @return [Float] returns Energy Factor (EF)
  def water_heater_convert_uniform_energy_factor_to_energy_factor(water_heater_mixed, fuel_type, uniform_energy_factor, capacity_btu_per_hr, volume_gal)
    # Get water heater sub type
    sub_type = water_heater_determine_sub_type(fuel_type, capacity_btu_per_hr, volume_gal)

    # source: RESNET, https://www.resnet.us/wp-content/uploads/RESNET-EF-Calculator-2017.xlsx
    if sub_type.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "No sub type identified for #{water_heater_mixed.name}, Energy Factor (EF) = Uniform Energy Factor (UEF) is assumed.")
      return uniform_energy_factor
    elsif sub_type == 'consumer_storage' && fuel_type == 'NaturalGas'
      return (0.9066 * uniform_energy_factor) + 0.0711
    elsif sub_type == 'consumer_storage' && fuel_type == 'Electricity'
      return (2.4029 * uniform_energy_factor) - 1.2844
    elsif sub_type == 'residential_duty' && (fuel_type == 'NaturalGas' || fuel_type == 'Oil')
      return (1.0005 * uniform_energy_factor) + 0.0019
    elsif sub_type == 'residential_duty' && fuel_type == 'Electricity'
      return (1.0219 * uniform_energy_factor) - 0.0025
    elsif sub_type == 'instantaneous'
      return uniform_energy_factor
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.WaterHeaterMixed', "Invalid sub_type for #{water_heater_mixed.name}, Energy Factor (EF) = Uniform Energy Factor (UEF) is assumed.")
      return uniform_energy_factor
    end
  end

  # Convert Energy Factor (EF) to Thermal Efficiency and storage tank UA
  #
  # @param fuel_type [String] water heater fuel type
  # @param energy_factor [Float] water heater Energy Factor (EF)
  # @param capacity_btu_per_hr [Float] water heater capacity in Btu/h
  # @return [Array] returns water heater thermal efficiency and storage tank UA
  def water_heater_convert_energy_factor_to_thermal_efficiency_and_ua(fuel_type, energy_factor, capacity_btu_per_hr)
    # Calculate the skin loss coefficient (UA)
    # differently depending on the fuel type
    if fuel_type == 'Electricity'
      # Fixed water heater efficiency per PNNL
      water_heater_efficiency = 1.0
      ua_btu_per_hr_per_f = (41_094 * ((1 / energy_factor) - 1)) / (24 * 67.5)
    elsif fuel_type == 'NaturalGas'
      # Fixed water heater thermal efficiency per PNNL
      water_heater_efficiency = 0.82
      # Calculate the Recovery Efficiency (RE)
      # based on a fixed capacity of 75,000 Btu/hr
      # and a fixed volume of 40 gallons by solving
      # this system of equations:
      # ua = (1/.95-1/re)/(67.5*(24/41094-1/(re*cap)))
      # 0.82 = (ua*67.5+cap*re)/cap
      # Solutions to the system of equations were determined
      # for discrete values of Energy Factor (EF) and modeled using a regression
      recovery_efficiency = (-0.1137 * (energy_factor**2)) + (0.1997 * energy_factor) + 0.731
      # Calculate the skin loss coefficient (UA)
      # Input capacity is assumed to be the output capacity
      # divided by a burner efficiency of 80%
      ua_btu_per_hr_per_f = (water_heater_efficiency - recovery_efficiency) * capacity_btu_per_hr / 0.8 / 67.5
    end

    return water_heater_efficiency, ua_btu_per_hr_per_f
  end

  # Add additional search criteria for water heater lookup efficiency.
  #
  # @param water_heater_mixed [OpenStudio::Model::WaterHeaterMixed] water heater mixed object
  # @param search_criteria [Hash] search criteria for looking up water heater data
  # @return [Hash] updated search criteria
  def water_heater_mixed_additional_search_criteria(water_heater_mixed, search_criteria)
    return search_criteria
  end
end
