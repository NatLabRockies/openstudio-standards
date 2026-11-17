class ASHRAE9012022 < ASHRAE901
  # @!group ThermalZone

  # Determine the thermal zone's occupancy type category.
  # Options are: residential, nonresidential, publicassembly, retail
  #
  # @return [String] the occupancy type category
  # @todo Add public assembly building types
  def thermal_zone_occupancy_type(thermal_zone)
    occ_type = if OpenstudioStandards::ThermalZone.thermal_zone_residential?(thermal_zone)
                 'residential'
               else
                 'nonresidential'
               end

    # Based on the space type that
    # represents a majority of the zone.
    space_type = OpenstudioStandards::ThermalZone.thermal_zone_get_space_type(thermal_zone)
    if space_type.is_initialized
      space_type = space_type.get
      bldg_type = space_type.standardsBuildingType
      if bldg_type.is_initialized
        bldg_type = bldg_type.get
        case bldg_type
        when 'Retail', 'StripMall', 'SuperMarket'
          occ_type = 'retail'
          # when 'SomeBuildingType'
          # @todo add publicassembly building types
          # occ_type = 'publicassembly'
        end
      end
    end

    # OpenStudio::logFree(OpenStudio::Info, "openstudio.Standards.ThermalZone", "For #{self.name}, occupancy type = #{occ_type}.")

    return occ_type
  end

  # Determine the area and occupancy level limits for
  # demand control ventilation.
  #
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
  # @return [Array<Double>] the minimum area, in m^2
  # and the minimum occupancy density in m^2/person.  Returns nil
  # if there is no requirement.
  def thermal_zone_demand_control_ventilation_limits(thermal_zone)
    min_area_ft2 = 500
    min_occ_per_1000_ft2 = 25

    # Convert to SI
    min_area_m2 = OpenStudio.convert(min_area_ft2, 'ft^2', 'm^2').get
    min_occ_per_ft2 = min_occ_per_1000_ft2 / 1000.0
    min_ft2_per_occ = 1.0 / min_occ_per_ft2
    min_m2_per_occ = OpenStudio.convert(min_ft2_per_occ, 'ft^2', 'm^2').get

    return [min_area_m2, min_m2_per_occ]
  end
end

