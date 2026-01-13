module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Conversions
    # Methods to convert between different units of measurement for HVAC systems

    # Convert from SEER to COP (no fan) for cooling coils
    # @ref [References::ASHRAE9012013] Appendix G
    #
    # @param seer [Double] seasonal energy efficiency ratio (SEER)
    # @return [Double] Coefficient of Performance (COP)
    def self.seer_to_cop_no_fan(seer)
      cop = (-0.0076 * seer * seer) + (0.3796 * seer)

      return cop
    end

    # Convert from COP to SEER
    # @ref [References::USDOEPrototypeBuildings]
    #
    # @param cop [Double] COP
    # @return [Double] Seasonal Energy Efficiency Ratio
    def self.cop_no_fan_to_seer(cop)
      delta = (0.3796**2) - (4.0 * 0.0076 * cop)
      seer = ((-delta**0.5) + 0.3796) / (2.0 * 0.0076)

      return seer
    end

    # Convert from SEER to COP (with fan) for cooling coils
    # per the method specified in Thornton et al. 2011
    #
    # @param seer [Double] seasonal energy efficiency ratio (SEER)
    # @return [Double] Coefficient of Performance (COP)
    def self.seer_to_cop(seer)
      eer = (-0.0182 * seer * seer) + (1.1088 * seer)
      cop = OpenstudioStandards::HVAC.eer_to_cop(eer)

      return cop
    end

    # Convert from COP to SEER (with fan) for cooling coils
    # per the method specified in Thornton et al. 2011
    #
    # @param cop [Double] Coefficient of Performance (COP)
    # @return [Double] seasonal energy efficiency ratio (SEER)
    def self.cop_to_seer(cop)
      eer = OpenstudioStandards::HVAC.cop_to_eer(cop)
      delta = (1.1088**2) - (4.0 * 0.0182 * eer)
      seer = (1.1088 - (delta**0.5)) / (2.0 * 0.0182)

      return seer
    end

    # Convert from COP_H to COP (no fan) for heat pump heating coils
    # @ref [References::ASHRAE9012013] Appendix G
    #
    # @param coph47 [Double] coefficient of performance at 47F Tdb, 42F Twb
    # @param capacity_w [Double] the heating capacity at AHRI rating conditions, in W
    # @return [Double] Coefficient of Performance (COP)
    def self.cop_heating_to_cop_heating_no_fan(coph47, capacity_w)
      # Convert the capacity to Btu/hr
      capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

      cop = (1.48E-7 * coph47 * capacity_btu_per_hr) + (1.062 * coph47)

      return cop
    end

    # Convert from HSPF to COP (no fan) for heat pump heating coils
    # @ref [References::ASHRAE9012013] Appendix G
    #
    # @param hspf [Double] heating seasonal performance factor (HSPF)
    # @return [Double] Coefficient of Performance (COP)
    def self.hspf_to_cop_no_fan(hspf)
      cop = (-0.0296 * hspf * hspf) + (0.7134 * hspf)

      return cop
    end

    # Convert from HSPF to COP (with fan) for heat pump heating coils
    # @ref ASHRAE RP-1197
    #
    # @param hspf [Double] heating seasonal performance factor (HSPF)
    # @return [Double] Coefficient of Performance (COP)
    def self.hspf_to_cop(hspf)
      cop = (-0.0255 * hspf * hspf) + (0.6239 * hspf)

      return cop
    end

    # Convert from EER to COP (no fan)
    # @ref [References::USDOEPrototypeBuildings] If capacity is not supplied, use DOE Prototype Building method.
    # @ref [References::ASHRAE9012013] If capacity is supplied, use the 90.1-2013 method
    #
    # @param eer [Double] Energy Efficiency Ratio (EER)
    # @param capacity_w [Double] the heating capacity at AHRI rating conditions, in W
    # @return [Double] Coefficient of Performance (COP)
    def self.eer_to_cop_no_fan(eer, capacity_w = nil)
      if capacity_w.nil?
        # From Thornton et al. 2011
        # r is the ratio of supply fan power to total equipment power at the rating condition,
        # assumed to be 0.12 for the reference buildings per Thornton et al. 2011.
        r = 0.12
        cop = ((eer / OpenStudio.convert(1.0, 'W', 'Btu/h').get) + r) / (1 - r)
      else
        # The 90.1-2013 method
        # Convert the capacity to Btu/hr
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        cop = (7.84E-8 * eer * capacity_btu_per_hr) + (0.338 * eer)
      end

      return cop
    end

    # Convert from COP (no fan) to EER
    # @ref [References::USDOEPrototypeBuildings]
    #
    # @param cop [Double] COP
    # @return [Double] Energy Efficiency Ratio (EER)
    def self.cop_no_fan_to_eer(cop, capacity_w = nil)
      if capacity_w.nil?
        # From Thornton et al. 2011
        # r is the ratio of supply fan power to total equipment power at the rating condition,
        # assumed to be 0.12 for the reference buildngs per Thornton et al. 2011.
        r = 0.12
        eer = OpenStudio.convert(1.0, 'W', 'Btu/h').get * ((cop * (1 - r)) - r)
      else
        # The 90.1-2013 method
        # Convert the capacity to Btu/hr
        capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
        eer = cop / ((7.84E-8 * capacity_btu_per_hr) + 0.338)
      end

      return eer
    end

    # Convert from IEER to COP (no fan)
    #
    # @note IEER is a weighted-average efficiency metrics at different load percentages, operataional and environemental conditions
    # @note IEER should be modeled by using performance curves that match a targeted efficiency values
    # @note This method estimates what a reasonable full load rated EER would be for a targeted IEER value
    # @note The regression used in this method is based on a survey of over 1,000 rated AHRI units with IEER ranging from 11.8 to 25.6
    # @todo Implement methods to handle IEER modeling
    #
    # @param ieer [Double] Energy Efficiency Ratio (EER)
    # @return [Double] Coefficient of Performance (COP)
    def self.ieer_to_cop_no_fan(ieer)
      eer = (0.0183 * ieer * ieer) - (0.4552 * ieer) + 13.21

      return OpenstudioStandards::HVAC.eer_to_cop_no_fan(eer)
    end

    # Convert from EER to COP
    #
    # @param eer [Double] Energy Efficiency Ratio (EER)
    # @return [Double] Coefficient of Performance (COP)
    def self.eer_to_cop(eer)
      return eer / OpenStudio.convert(1.0, 'W', 'Btu/h').get
    end

    # Convert from COP to EER
    #
    # @param cop [Double] Coefficient of Performance (COP)
    # @return [Double] Energy Efficiency Ratio (EER)
    def self.cop_to_eer(cop)
      return cop * OpenStudio.convert(1.0, 'W', 'Btu/h').get
    end

    # Convert from COP to kW/ton
    #
    # @param cop [Double] Coefficient of Performance (COP)
    # @return [Double] kW of input power per ton of cooling
    def self.cop_to_kw_per_ton(cop)
      return 3.517 / cop
    end

    # A helper method to convert from kW/ton to COP
    #
    # @param kw_per_ton [Double] kW of input power per ton of cooling
    # @return [Double] Coefficient of Performance (COP)
    def self.kw_per_ton_to_cop(kw_per_ton)
      return 3.517 / kw_per_ton
    end

    # A helper method to convert from AFUE to thermal efficiency
    # @ref [References::USDOEPrototypeBuildings] Boiler Addendum 90.1-04an
    #
    # @param afue [Double] Annual Fuel Utilization Efficiency
    # @return [Double] Thermal efficiency (%)
    def self.afue_to_thermal_eff(afue)
      return afue
    end

    # A helper method to convert from thermal efficiency to AFUE
    # @ref [References::USDOEPrototypeBuildings] Boiler Addendum 90.1-04an
    #
    # @param teff [Double] Thermal Efficiency
    # @return [Double] AFUE
    def self.thermal_eff_to_afue(teff)
      return teff
    end

    # A helper method to convert from combustion efficiency to thermal efficiency
    # @ref [References::USDOEPrototypeBuildings] Boiler Addendum 90.1-04an
    #
    # @param combustion_eff [Double] Combustion efficiency (%)
    # @return [Double] Thermal efficiency (%)
    def self.combustion_eff_to_thermal_eff(combustion_eff)
      return combustion_eff - 0.007
    end

    # A helper method to convert from thermal efficiency to combustion efficiency
    # @ref [References::USDOEPrototypeBuildings] Boiler Addendum 90.1-04an
    #
    # @param thermal_eff [Double] Thermal efficiency
    # @return [Double] Combustion efficiency
    def self.thermal_eff_to_comb_eff(thermal_eff)
      return thermal_eff + 0.007
    end
  end
end
