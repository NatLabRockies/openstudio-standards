class NECB2020

  # Applies the standard efficiency ratings and typical losses and paraisitic loads to this object.
  # Efficiency and skin loss coefficient (UA)
  # Per PNNL http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf
  # Appendix A: Service Water Heating
  #
  # @return [Boolean] true if successful, false if not
  #
  # NECB2020 uses a different procedure calculate gas water heater efficiencies (compared to previous NECB)
  #
  def water_heater_mixed_apply_efficiency(water_heater_mixed)
    # Get the capacity of the water heater
    # @todo add capability to pull autosized water heater capacity
    # if the Sizing:WaterHeater object is ever implemented in OpenStudio.
    capacity_w = water_heater_mixed.heaterMaximumCapacity
    if capacity_w.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot find capacity, standard will not be applied.")
      return false
    else
      capacity_w = capacity_w.get
    end
    capacity_kw = capacity_w/1000.0
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Get the volume of the water heater
    # @todo add capability to pull autosized water heater volume
    # if the Sizing:WaterHeater object is ever implemented in OpenStudio.
    volume_m3 = water_heater_mixed.tankVolume
    if volume_m3.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, cannot find volume, standard will not be applied.")
      return false
    else
      volume_m3 = volume_m3.get
    end
    volume_gal = OpenStudio.convert(volume_m3, 'm^3', 'gal').get
    volume_litre = OpenStudio.convert(volume_m3, 'm^3', 'L').get
    
    # Get the heater fuel type
    fuel_type = water_heater_mixed.heaterFuelType
    unless fuel_type == 'NaturalGas' || fuel_type == 'Electricity' || fuel_type == 'FuelOilNo2'
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.WaterHeaterMixed', "For #{water_heater_mixed.name}, fuel type of #{fuel_type} is not yet supported, standard will not be applied.")
    end

    # Calculate the water heater efficiency and
    # skin loss coefficient (UA)
    # Calculate the energy factor (EF)
    # From PNNL http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf
    # Appendix A: Service Water Heating
	  # and modified by PCF 1630 as noted below.
    water_heater_eff = nil
    ua_btu_per_hr_per_f = nil
    sl_btu_per_hr = nil
    q_load_btu_per_hr = nil
    uef = nil

    case fuel_type
    when 'Electricity'
      volume_litre_per_s = volume_m3 * 1000
      if capacity_btu_per_hr <= OpenStudio.convert(12, 'kW', 'Btu/hr').get
        # Fixed water heater efficiency per PNNL
        water_heater_eff = 1
        # Calculate the max allowable standby loss (SL)
        sl_w = if volume_litre_per_s < 270
                 40 + 0.2 * volume_litre_per_s # assume bottom inlet
               else
                 0.472 * volume_litre_per_s - 33.5
                 # assume bottom inlet
               end
        sl_btu_per_hr = OpenStudio.convert(sl_w, 'W', 'Btu/hr').get
      else
        # Fixed water heater efficiency per PNNL
        water_heater_eff = 1
        # Calculate the max allowable standby loss (SL)   # use this - NECB does not give SL calculation for cap > 12 kW
        sl_w = 0.3 + 102.2/volume_litre_per_s
        sl_btu_per_hr = OpenStudio.convert(sl_w, 'W', 'Btu/hr').get
      end
      # Calculate the skin loss coefficient (UA)
      ua_btu_per_hr_per_f = sl_btu_per_hr / 70
    when 'NaturalGas', 'FuelOilNo2'
      # Performance requirements from NECB2020 Table 6.2.2.1 Gas-fired storage type
      
      # Performance requirement based on FHR and volume
      # Water heater parameters derived using the procedure described by:
      #   Maguire, J., & Roberts, D. (2020). DERIVING SIMULATION PARAMETERS FOR STORAGE-TYPE WATER HEATERS 
      #   USING RATINGS DATA PRODUCED FROM THE UNIFORM ENERGY FACTOR TEST PROCEDURE. 2020 Building Performance 
      #   Analysis Conference and SimBuild co-organized by ASHRAE and IBPSA-USA (pp. 325-331). Chicago: ASHRAE.
      #   https://www.ashrae.org/file%20library/conferences/specialty%20conferences/2020%20building%20performance/papers/d-bsc20-c039.pdf
      #
      #   AND
      #
      #   PNNL http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf
      #
      # Updated reference links:
      #  https://www.pnnl.gov/main/publications/external/technical_reports/PNNL-23269.pdf - Equations may have typos, also for EF which is at diff test T.
      #  https://www.nrel.gov/docs/fy21osti/71633.pdf
      #  https://ases.org/wp-content/uploads/2021/11/Using-Simple-Algebraic-Models-and-Rating-Test-Data-to-Predict-Water-Heater-Energy-Consumption-Under-Off-Test-Conditions-.pdf
      #  https://www.ecfr.gov/current/title-10/chapter-II/subchapter-D/part-430/subpart-B/appendix-Appendix%20E%20to%20Subpart%20B%20of%20Part%20430 
      #  

      # Assume first hour rating.
      # Rule of thumb is FHR is 70% tank_volume + ~40 Gal
      #  Ref: https://www.waterheaterpros.com/first-hour-rating#:~:text=To%20find%20a%20water%20heater%27s,can%20deliver%20at%20peak%20hours.
      fhr_L_per_hr = 0.7*volume_litre + 151.0

      if capacity_w <= 22000 and volume_litre >= 76 and volume_litre < 208
        if fhr_L_per_hr < 68 # 18 US Gal - UEF draw pattern very small usage
          uef = 0.3456 - 0.00053*volume_litre
          volume_drawn_gal = 10 # 37.85L
        elsif fhr_L_per_hr >= 68 and fhr_L_per_hr < 193 # 51 US Gal - UEF draw pattern low usage
          uef = 0.5982 - 0.00050*volume_litre
          volume_drawn_gal = 38 # 143.8L
        elsif fhr_L_per_hr >= 193 and fhr_L_per_hr < 284 # 75 US Gal - UEF draw pattern medium usage
          uef = 0.6483 - 0.00045*volume_litre
          volume_drawn_gal = 55 # 208.2L
        elsif fhr_L_per_hr >= 284 # 75 US Gal - UEF draw pattern high usage
          uef = 0.6920 - 0.00034*volume_litre
          volume_drawn_gal = 84 # 318.0L
        end

        # Assume burner efficiency  (PNNL-23269)
        water_heater_eff = 0.82

        # Estimate recovery efficiency (RE) and UA (Maguire and Robers, 2020)
        q_load_btu = volume_drawn_gal*8.30074*0.99826*(125.0-58.0) # water properties at 91.5F; derived from UEF test.
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

        # From PNNL-23269?
        re = water_heater_eff + q_load_btu*(uef-water_heater_eff)/(24*capacity_btu_per_hr*uef)
        ua_btu_per_hr_per_f = (water_heater_eff-re)*capacity_btu_per_hr/(125-67.5)  

      elsif capacity_w <= 22000 and volume_litre >= 208 and volume_litre < 380
        if fhr_L_per_hr < 68
          uef = 0.6470 - 0.00016*volume_litre
          volume_drawn_gal = 10
        elsif fhr_L_per_hr >= 68 and fhr_L_per_hr < 193
          uef = 0.7689 - 0.00013*volume_litre
          volume_drawn_gal = 38
        elsif fhr_L_per_hr >= 193 and fhr_L_per_hr < 284
          uef = 0.7897 - 0.00011*volume_litre
          volume_drawn_gal = 55
        elsif fhr_L_per_hr >= 284 
          uef = 0.8072 - 0.00008*volume_litre
          volume_drawn_gal = 84
        end

        # Assume burner  efficiency  (PNNL)
        water_heater_eff = 0.82

        # Estimate recovery efficiency (RE) and UA (Maguire and Robers, 2020)
        q_load_btu = volume_drawn_gal*8.30074*0.99826*(125-58) #water properties at 91.5F
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

        # Estimate recovery efficiency (RE) and UA (Maguire and Robers, 2020); Note tank at 125F for UEF, previously 135F for EF test
        re = water_heater_eff + q_load_btu*(uef-water_heater_eff)/(24*capacity_btu_per_hr*uef)
        ua_btu_per_hr_per_f = (water_heater_eff-re)*capacity_btu_per_hr/(125-67.5)      

      elsif capacity_w > 22000 and capacity_w <= 30500 and volume_litre <= 454 
        # NOTE: volume_litre 454L in this case, refers to manufacturer stated volume.
        # Assume manufacturer rated volume = actual tank volume (value used in EnergyPlus)
        
        uef = 0.8107 - 0.00021*volume_litre

        # Assume burner efficiency  (PNNL)
        water_heater_eff = 0.82

        # Estimate recovery efficiency (RE) and UA (Maguire and Robers, 2020)
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        if fhr_L_per_hr < 68
          volume_drawn_gal = 10
        elsif fhr_L_per_hr >= 68 and fhr_L_per_hr < 193
          volume_drawn_gal = 38
        elsif fhr_L_per_hr >= 193 and fhr_L_per_hr < 284
          volume_drawn_gal = 55
        elsif fhr_L_per_hr >= 284
          volume_drawn_gal = 84
        end
        q_load_btu = volume_drawn_gal*8.30074*0.99826*(125-58) #water properties at 91.5F

        # Estimate recovery efficiency (RE) and UA (Maguire and Robers, 2020)
        re = water_heater_eff + q_load_btu*(uef-water_heater_eff)/(24*capacity_btu_per_hr*uef)
        ua_btu_per_hr_per_f = (water_heater_eff-re)*capacity_btu_per_hr/(125-67.5)      
        
      else # all other water heaters
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        # thermal efficiency (NECB2020)
        et = 0.9
        # maximum standby losses
        sl_w = 0.84*(1.25*capacity_kw + 16.57*(volume_litre**0.5))
        sl_btu_per_hr = OpenStudio.convert(sl_w, 'W', 'Btu/hr').get
        ua_btu_per_hr_per_f = sl_btu_per_hr*et / 70
        water_heater_eff = (ua_btu_per_hr_per_f*70 + capacity_btu_per_hr*et)/capacity_btu_per_hr
      end
    end

    # Convert to SI
    ua_w_per_k = OpenStudio.convert(ua_btu_per_hr_per_f, 'Btu/hr*R', 'W/K').get
    # Set the water heater properties
    # Efficiency
    water_heater_mixed.setHeaterThermalEfficiency(water_heater_eff)
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
    water_heater_mixed.setOffCycleParasiticHeatFractiontoTank(0.8)

    # set part-load performance curve
    if (fuel_type == 'NaturalGas') || (fuel_type == 'FuelOilNo2')
      plf_vs_plr_curve = model_add_curve(water_heater_mixed.model, 'SWH-EFFFPLR-NECB2011')
      water_heater_mixed.setPartLoadFactorCurve(plf_vs_plr_curve)
    end

    # Append the name with standards information
    water_heater_mixed.setName("#{water_heater_mixed.name} #{water_heater_eff.round(3)} Therm Eff")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.WaterHeaterMixed', "For #{template}: #{water_heater_mixed.name}; thermal efficiency = #{water_heater_eff.round(3)}, skin-loss UA = #{ua_btu_per_hr_per_f.round}Btu/hr-R")
    return true
  end
end