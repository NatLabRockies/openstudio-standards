module OpenstudioStandards
  # The ThermalZone module provides methods get information about model thermal zones
  module ThermalZone
    # Determine if the thermal zone is a plenum based on whether a majority of the spaces in the zone are plenums or not.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if majority plenum, false if not
    def self.thermal_zone_plenum?(thermal_zone)
      plenum_status = false

      area_plenum = 0
      area_non_plenum = 0
      thermal_zone.spaces.each do |space|
        if OpenstudioStandards::Space.space_plenum?(space)
          area_plenum += space.floorArea
        else
          area_non_plenum += space.floorArea
        end
      end

      # Majority
      if area_plenum > area_non_plenum
        plenum_status = true
      end

      return plenum_status
    end

    # Determine if the thermal zone is residential based on the space type properties for the spaces in the zone.
    # If there are both residential and nonresidential spaces in the zone,
    # the result will be whichever type has more floor area.
    # In the event that they are equal, it will be assumed nonresidential.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # return [Boolean] true if residential, false if nonresidential
    def self.thermal_zone_residential?(thermal_zone)
      # Determine the respective areas
      res_area_m2 = 0
      nonres_area_m2 = 0
      thermal_zone.spaces.each do |space|
        # Ignore space if not part of total area
        next unless space.partofTotalFloorArea

        if OpenstudioStandards::Space.space_residential?(space)
          res_area_m2 += space.floorArea
        else
          nonres_area_m2 += space.floorArea
        end
      end

      # Determine which is larger
      is_res = false
      if res_area_m2 > nonres_area_m2
        is_res = true
      end

      return is_res
    end

    # Determine if this zone is a vestibule.
    # Zone must be less than 200 ft^2 and also have an infiltration object specified using Flow/Zone.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if vestibule, false if not
    def self.thermal_zone_vestibule?(thermal_zone)
      is_vest = false

      # Check area
      unless thermal_zone.floorArea < OpenStudio.convert(200, 'ft^2', 'm^2').get
        return is_vest
      end

      # Check presence of infiltration
      thermal_zone.spaces.each do |space|
        space.spaceInfiltrationDesignFlowRates.each do |infil|
          if infil.designFlowRate.is_initialized
            is_vest = true
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: This zone is considered a vestibule.")
            break
          end
        end
      end

      return is_vest
    end

    # Determines heating status.
    # If the zone has a thermostat with a maximum heating setpoint above 5C (41F), counts as heated.
    # Plenums are also assumed to be heated.
    #
    # @author Andrew Parker, Julien Marrec
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if heated, false if not
    def self.thermal_zone_heated?(thermal_zone)
      temp_f = 41.0
      temp_c = OpenStudio.convert(temp_f, 'F', 'C').get
      htd = false

      # Consider plenum zones heated
      area_plenum = 0
      area_non_plenum = 0
      thermal_zone.spaces.each do |space|
        if OpenstudioStandards::Space.space_plenum?(space)
          area_plenum += space.floorArea
        else
          area_non_plenum += space.floorArea
        end
      end

      # Majority
      if area_plenum > area_non_plenum
        htd = true
        return htd
      end

      # Check if the zone has radiant heating,
      # and if it does, get heating setpoint schedule
      # directly from the radiant system to check.
      thermal_zone.equipment.each do |equip|
        htg_sch = nil
        if equip.to_ZoneHVACHighTemperatureRadiant.is_initialized
          equip = equip.to_ZoneHVACHighTemperatureRadiant.get
          if equip.heatingSetpointTemperatureSchedule.is_initialized
            htg_sch = equip.heatingSetpointTemperatureSchedule.get
          end
        elsif equip.to_ZoneHVACLowTemperatureRadiantElectric.is_initialized
          equip = equip.to_ZoneHVACLowTemperatureRadiantElectric.get
          htg_sch = equip.heatingSetpointTemperatureSchedule
        elsif equip.to_ZoneHVACLowTempRadiantConstFlow.is_initialized
          equip = equip.to_ZoneHVACLowTempRadiantConstFlow.get
          htg_coil = equip.heatingCoil
          if htg_coil.to_CoilHeatingLowTempRadiantConstFlow.is_initialized
            htg_coil = htg_coil.to_CoilHeatingLowTempRadiantConstFlow.get
            if htg_coil.heatingHighControlTemperatureSchedule.is_initialized
              htg_sch = htg_coil.heatingHighControlTemperatureSchedule.get
            end
          end
        elsif equip.to_ZoneHVACLowTempRadiantVarFlow.is_initialized
          equip = equip.to_ZoneHVACLowTempRadiantVarFlow.get
          htg_coil = equip.heatingCoil
          if equip.model.version > OpenStudio::VersionString.new('3.1.0')
            if htg_coil.is_initialized
              htg_coil = htg_coil.get
            else
              htg_coil = nil
            end
          end
          if !htg_coil.nil? && htg_coil.to_CoilHeatingLowTempRadiantVarFlow.is_initialized
            htg_coil = htg_coil.to_CoilHeatingLowTempRadiantVarFlow.get
            if htg_coil.heatingControlTemperatureSchedule.is_initialized
              htg_sch = htg_coil.heatingControlTemperatureSchedule.get
            end
          end
        end
        # Move on if no heating schedule was found
        next if htg_sch.nil?

        # Get the setpoint from the schedule
        if htg_sch.to_ScheduleRuleset.is_initialized
          htg_sch = htg_sch.to_ScheduleRuleset.get
          max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(htg_sch)['max']
          if max_c > temp_c
            htd = true
          end
        elsif htg_sch.to_ScheduleConstant.is_initialized
          htg_sch = htg_sch.to_ScheduleConstant.get
          max_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(htg_sch)['max']
          if max_c > temp_c
            htd = true
          end
        elsif htg_sch.to_ScheduleCompact.is_initialized
          htg_sch = htg_sch.to_ScheduleCompact.get
          max_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(htg_sch)['max']
          if max_c > temp_c
            htd = true
          end
        else
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone', "Zone #{thermal_zone.name} used an unknown schedule type for the heating setpoint; assuming heated.")
          htd = true
        end
      end

      # Unheated if no thermostat present
      if thermal_zone.thermostat.empty?
        return htd
      end

      # Check the heating setpoint
      tstat = thermal_zone.thermostat.get
      if tstat.to_ThermostatSetpointDualSetpoint
        tstat = tstat.to_ThermostatSetpointDualSetpoint.get
        htg_sch = tstat.getHeatingSchedule
        if htg_sch.is_initialized
          htg_sch = htg_sch.get
          if htg_sch.to_ScheduleRuleset.is_initialized
            htg_sch = htg_sch.to_ScheduleRuleset.get
            max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(htg_sch)['max']
            if max_c > temp_c
              htd = true
            end
          elsif htg_sch.to_ScheduleConstant.is_initialized
            htg_sch = htg_sch.to_ScheduleConstant.get
            max_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(htg_sch)['max']
            if max_c > temp_c
              htd = true
            end
          elsif htg_sch.to_ScheduleCompact.is_initialized
            htg_sch = htg_sch.to_ScheduleCompact.get
            max_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(htg_sch)['max']
            if max_c > temp_c
              htd = true
            end
          else
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone', "Zone #{thermal_zone.name} used an unknown schedule type for the heating setpoint; assuming heated.")
            htd = true
          end
        end
      elsif tstat.to_ZoneControlThermostatStagedDualSetpoint
        tstat = tstat.to_ZoneControlThermostatStagedDualSetpoint.get
        htg_sch = tstat.heatingTemperatureSetpointSchedule
        if htg_sch.is_initialized
          htg_sch = htg_sch.get
          if htg_sch.to_ScheduleRuleset.is_initialized
            htg_sch = htg_sch.to_ScheduleRuleset.get
            max_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(htg_sch)['max']
            if max_c > temp_c
              htd = true
            end
          end
        end
      end

      return htd
    end

    # Determines cooling status.
    # If the zone has a thermostat with a minimum cooling setpoint below 33C (91F), counts as cooled.
    # Plenums are also assumed to be cooled.
    #
    # @author Andrew Parker, Julien Marrec
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if cooled, false if not
    def self.thermal_zone_cooled?(thermal_zone)
      temp_f = 91.0
      temp_c = OpenStudio.convert(temp_f, 'F', 'C').get
      cld = false

      # Consider plenum zones cooled
      area_plenum = 0
      area_non_plenum = 0
      thermal_zone.spaces.each do |space|
        if OpenstudioStandards::Space.space_plenum?(space)
          area_plenum += space.floorArea
        else
          area_non_plenum += space.floorArea
        end
      end

      # Majority
      if area_plenum > area_non_plenum
        cld = true
        return cld
      end

      # Check if the zone has radiant cooling,
      # and if it does, get cooling setpoint schedule
      # directly from the radiant system to check.
      thermal_zone.equipment.each do |equip|
        clg_sch = nil
        if equip.to_ZoneHVACLowTempRadiantConstFlow.is_initialized
          equip = equip.to_ZoneHVACLowTempRadiantConstFlow.get
          clg_coil = equip.coolingCoil
          if clg_coil.to_CoilCoolingLowTempRadiantConstFlow.is_initialized
            clg_coil = clg_coil.to_CoilCoolingLowTempRadiantConstFlow.get
            if clg_coil.coolingLowControlTemperatureSchedule.is_initialized
              clg_sch = clg_coil.coolingLowControlTemperatureSchedule.get
            end
          end
        elsif equip.to_ZoneHVACLowTempRadiantVarFlow.is_initialized
          equip = equip.to_ZoneHVACLowTempRadiantVarFlow.get
          clg_coil = equip.coolingCoil
          if equip.model.version > OpenStudio::VersionString.new('3.1.0')
            if clg_coil.is_initialized
              clg_coil = clg_coil.get
            else
              clg_coil = nil
            end
          end
          if !clg_coil.nil? && clg_coil.to_CoilCoolingLowTempRadiantVarFlow.is_initialized
            clg_coil = clg_coil.to_CoilCoolingLowTempRadiantVarFlow.get
            if clg_coil.coolingControlTemperatureSchedule.is_initialized
              clg_sch = clg_coil.coolingControlTemperatureSchedule.get
            end
          end
        end
        # Move on if no cooling schedule was found
        next if clg_sch.nil?

        # Get the setpoint from the schedule
        if clg_sch.to_ScheduleRuleset.is_initialized
          clg_sch = clg_sch.to_ScheduleRuleset.get
          min_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(clg_sch)['min']
          if min_c < temp_c
            cld = true
          end
        elsif clg_sch.to_ScheduleConstant.is_initialized
          clg_sch = clg_sch.to_ScheduleConstant.get
          min_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(clg_sch)['min']
          if min_c < temp_c
            cld = true
          end
        elsif clg_sch.to_ScheduleCompact.is_initialized
          clg_sch = clg_sch.to_ScheduleCompact.get
          min_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(clg_sch)['min']
          if min_c < temp_c
            cld = true
          end
        else
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone', "Zone #{thermal_zone.name} used an unknown schedule type for the cooling setpoint; assuming cooled.")
          cld = true
        end
      end

      # Unheated if no thermostat present
      if thermal_zone.thermostat.empty?
        return cld
      end

      # Check the cooling setpoint
      tstat = thermal_zone.thermostat.get
      if tstat.to_ThermostatSetpointDualSetpoint
        tstat = tstat.to_ThermostatSetpointDualSetpoint.get
        clg_sch = tstat.getCoolingSchedule
        if clg_sch.is_initialized
          clg_sch = clg_sch.get
          if clg_sch.to_ScheduleRuleset.is_initialized
            clg_sch = clg_sch.to_ScheduleRuleset.get
            min_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(clg_sch)['min']
            if min_c < temp_c
              cld = true
            end
          elsif clg_sch.to_ScheduleConstant.is_initialized
            clg_sch = clg_sch.to_ScheduleConstant.get
            min_c = OpenstudioStandards::Schedules.schedule_constant_get_min_max(clg_sch)['min']
            if min_c < temp_c
              cld = true
            end
          elsif clg_sch.to_ScheduleCompact.is_initialized
            clg_sch = clg_sch.to_ScheduleCompact.get
            min_c = OpenstudioStandards::Schedules.schedule_compact_get_min_max(clg_sch)['min']
            if min_c < temp_c
              cld = true
            end
          else
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone', "Zone #{thermal_zone.name} used an unknown schedule type for the cooling setpoint; assuming cooled.")
            cld = true
          end
        end
      elsif tstat.to_ZoneControlThermostatStagedDualSetpoint
        tstat = tstat.to_ZoneControlThermostatStagedDualSetpoint.get
        clg_sch = tstat.coolingTemperatureSetpointSchedule
        if clg_sch.is_initialized
          clg_sch = clg_sch.get
          if clg_sch.to_ScheduleRuleset.is_initialized
            clg_sch = clg_sch.to_ScheduleRuleset.get
            min_c = OpenstudioStandards::Schedules.schedule_ruleset_get_min_max(clg_sch)['min']
            if min_c < temp_c
              cld = true
            end
          end
        end
      elsif tstat.to_ThermostatSetpointSingleHeating
        cld = false
      end

      return cld
    end

    # Determine if the thermal zone is heated by electricity.
    # This will return true if there is any electric heat, even if not the primary heating source.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] true if heated by electricity, false if fossil fuel or other.
    def self.thermal_zone_electric_heat?(thermal_zone)
      # error if HVACComponent heating fuels method is not available
      if thermal_zone.model.version < OpenStudio::VersionString.new('3.6.0')
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.ThermalZone', 'Required HVACComponent method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
      end

      # Get an array of the heating fuels used by the zone
      htg_fuels = thermal_zone.heatingFuelTypes.map(&:valueName)
      is_electric = htg_fuels.include?('Electricity')

      return is_electric
    end

    # Determine if the thermal zone is heated by a fossil fuel.
    # This will return true if there is any fossil heat, even if not the primary heating source.
    # As an example, a zone served by a VRF + DOAS system will show as fossil heated
    # if the DOAS ventilation air is fossil heated
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] true if heated by fossil fuel, false if electric or other.
    def self.thermal_zone_fossil_heat?(thermal_zone)
      # error if HVACComponent heating fuels method is not available
      if thermal_zone.model.version < OpenStudio::VersionString.new('3.6.0')
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.ThermalZone', 'Required HVACComponent method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
      end

      is_fossil = false
      # Get an array of the heating fuels used by the zone
      htg_fuels = thermal_zone.heatingFuelTypes.map(&:valueName)
      if htg_fuels.include?('Gas') ||
         htg_fuels.include?('NaturalGas') ||
         htg_fuels.include?('Propane') ||
         htg_fuels.include?('PropaneGas') ||
         htg_fuels.include?('FuelOil_1') ||
         htg_fuels.include?('FuelOilNo1') ||
         htg_fuels.include?('FuelOil_2') ||
         htg_fuels.include?('FuelOilNo2') ||
         htg_fuels.include?('Coal') ||
         htg_fuels.include?('Diesel') ||
         htg_fuels.include?('Gasoline')

        is_fossil = true
      end

      return is_fossil
    end

    # Determine if the thermal zone is heated by district or purchased heat.
    # This will return true if there is any fossil heat, even if not the primary heating source.
    # As an example, a zone served by a VRF + DOAS system will show as district heated
    # if the DOAS ventilation air is heated by a district system
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] true if heated by district heat, false if electric or other.
    def self.thermal_zone_district_heat?(thermal_zone)
      # error if HVACComponent heating fuels method is not available
      if thermal_zone.model.version < OpenStudio::VersionString.new('3.6.0')
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.ThermalZone', 'Required HVACComponent method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
      end

      is_district = false
      # Get an array of the heating fuels used by the zone
      htg_fuels = thermal_zone.heatingFuelTypes.map(&:valueName)
      if htg_fuels.include?('DistrictHeating') ||
         htg_fuels.include?('DistrictHeatingWater') ||
         htg_fuels.include?('DistrictHeatingSteam')

        is_district = true
      end

      return is_district
    end

    # Determine if the thermal zone is heated by two or more of electricity, fossil fuel, and district or purchased heat.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] true if mixed fossil, electric, and district/purchased heat, false if not
    def self.thermal_zone_mixed_heat?(thermal_zone)
      electric_heat = OpenstudioStandards::ThermalZone.thermal_zone_electric_heat?(thermal_zone)
      fossil_heat = OpenstudioStandards::ThermalZone.thermal_zone_fossil_heat?(thermal_zone)
      district_heat = OpenstudioStandards::ThermalZone.thermal_zone_district_heat?(thermal_zone)
      is_mixed = [electric_heat, fossil_heat, district_heat].count(true) > 1

      return is_mixed
    end

    # Determine the design internal load (W) for this zone without space multipliers.
    # This include People, Lights, Electric Equipment, and Gas Equipment in all spaces in this zone.
    # It assumes 100% of the wattage is converted to heat, and that the design peak schedule value is 1 (100%).
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Double] the design internal load, in watts
    def self.thermal_zone_get_design_internal_load(thermal_zone)
      load_w = 0.0

      thermal_zone.spaces.each do |space|
        load_w += OpenstudioStandards::Space.space_get_design_internal_load(space)
      end

      return load_w
    end

    # Returns the space type that represents a majority of the floor area.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boost::Optional<OpenStudio::Model::SpaceType>] An OptionalSpaceType
    def self.thermal_zone_get_space_type(thermal_zone)
      space_type_to_area = Hash.new(0.0)

      thermal_zone.spaces.each do |space|
        if space.spaceType.is_initialized
          space_type = space.spaceType.get
          space_type_to_area[space_type] += space.floorArea
        end
      end

      # If no space types, return empty optional SpaceType
      if space_type_to_area.empty?
        return OpenStudio::Model::OptionalSpaceType.new
      end

      # Sort by area
      biggest_space_type = space_type_to_area.sort_by { |st, area| area }.reverse[0][0]

      return OpenStudio::Model::OptionalSpaceType.new(biggest_space_type)
    end

    # Returns the standards building type that represents the majority of floor area.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [String] the standards building type
    def self.thermal_zone_get_building_type(thermal_zone)
      # determine areas of each building type
      building_type_areas = {}
      thermal_zone.spaces.each do |space|
        # ignore space if not part of total area
        next unless space.partofTotalFloorArea

        if space.spaceType.is_initialized
          space_type = space.spaceType.get
          if space_type.standardsBuildingType.is_initialized
            building_type = space_type.standardsBuildingType.get
            if building_type_areas[building_type].nil?
              building_type_areas[building_type] = space.floorArea
            else
              building_type_areas[building_type] += space.floorArea
            end
          end
        end
      end

      # return largest building type area
      building_type = building_type_areas.key(building_type_areas.values.max)

      if building_type.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "Thermal zone #{thermal_zone.name} does not have standards building type.")
      end

      return building_type
    end

    # This method creates a new fractional schedule ruleset.
    # If occupied_percentage_threshold is set, this method will return a discrete on/off fractional schedule
    # with a value of one when occupancy across all spaces is greater than or equal to the occupied_percentage_threshold,
    # and zero all other times.  Otherwise the method will return the weighted fractional occupancy schedule.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @param sch_name [String] the name of the generated occupancy schedule
    # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
    #   if this parameter is set, the returned ScheduleRuleset will be 0 = unoccupied, 1 = occupied
    #   otherwise the ScheduleRuleset will be the weighted fractional occupancy schedule
    # @return [<OpenStudio::Model::ScheduleRuleset>] OpenStudio ScheduleRuleset of fractional or discrete occupancy
    def self.thermal_zone_get_occupancy_schedule(thermal_zone, sch_name: nil, occupied_percentage_threshold: nil)
      if sch_name.nil?
        sch_name = "#{thermal_zone.name} Occ Sch"
      end
      # Get the occupancy schedule for all spaces in thermal_zone
      sch_ruleset = OpenstudioStandards::Space.spaces_get_occupancy_schedule(thermal_zone.spaces,
                                                                             sch_name: sch_name,
                                                                             occupied_percentage_threshold: occupied_percentage_threshold)
      return sch_ruleset
    end

    # This method creates a new fractional schedule ruleset.
    # If occupied_percentage_threshold is set, this method will return a discrete on/off fractional schedule
    # with a value of one when occupancy across all spaces is greater than or equal to the occupied_percentage_threshold,
    # and zero all other times.  Otherwise the method will return the weighted fractional occupancy schedule.
    #
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] Array of OpenStudio ThermalZone objects
    # @param sch_name [String] the name of the generated occupancy schedule
    # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
    #   if this parameter is set, the returned ScheduleRuleset will be 0 = unoccupied, 1 = occupied
    #   otherwise the ScheduleRuleset will be the weighted fractional occupancy schedule
    # @return [<OpenStudio::Model::ScheduleRuleset>] OpenStudio ScheduleRuleset of fractional or discrete occupancy
    def self.thermal_zones_get_occupancy_schedule(thermal_zones, sch_name: nil, occupied_percentage_threshold: nil)
      if sch_name.nil?
        sch_name = "#{thermal_zones.size} zone Occ Sch"
      end
      # Get the occupancy schedule for all spaces in thermal_zones
      spaces = []
      thermal_zones.each do |thermal_zone|
        thermal_zone.spaces.each do |space|
          spaces << space
        end
      end
      sch_ruleset = OpenstudioStandards::Space.spaces_get_occupancy_schedule(spaces,
                                                                             sch_name: sch_name,
                                                                             occupied_percentage_threshold: occupied_percentage_threshold)
      return sch_ruleset
    end

    # Calculates the zone outdoor airflow requirement (Voz)
    # based on the inputs in the DesignSpecification:OutdoorAir objects in all spaces in the zone.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Double] the zone outdoor air flow rate in cubic meters per second (m^3/s)
    def self.thermal_zone_get_outdoor_airflow_rate(thermal_zone)
      tot_oa_flow_rate = 0.0

      spaces = thermal_zone.spaces.sort

      sum_floor_area = 0.0
      sum_number_of_people = 0.0
      sum_volume = 0.0

      # Variables for merging outdoor air
      any_max_oa_method = false
      sum_oa_for_people = 0.0
      sum_oa_for_floor_area = 0.0
      sum_oa_rate = 0.0
      sum_oa_for_volume = 0.0

      # Find common variables for the new space
      spaces.each do |space|
        floor_area = space.floorArea
        sum_floor_area += floor_area

        number_of_people = space.numberOfPeople
        sum_number_of_people += number_of_people

        volume = space.volume
        sum_volume += volume

        dsn_oa = space.designSpecificationOutdoorAir
        next if dsn_oa.empty?

        dsn_oa = dsn_oa.get

        # compute outdoor air rates in case we need them
        oa_for_people = number_of_people * dsn_oa.outdoorAirFlowperPerson
        oa_for_floor_area = floor_area * dsn_oa.outdoorAirFlowperFloorArea
        oa_rate = dsn_oa.outdoorAirFlowRate
        oa_for_volume = volume * dsn_oa.outdoorAirFlowAirChangesperHour / 3600

        # First check if this space uses the Maximum method and other spaces do not
        if dsn_oa.outdoorAirMethod == 'Maximum'
          sum_oa_rate += [oa_for_people, oa_for_floor_area, oa_rate, oa_for_volume].max
        elsif dsn_oa.outdoorAirMethod == 'Sum'
          sum_oa_for_people += oa_for_people
          sum_oa_for_floor_area += oa_for_floor_area
          sum_oa_rate += oa_rate
          sum_oa_for_volume += oa_for_volume
        end
      end

      tot_oa_flow_rate += sum_oa_for_people
      tot_oa_flow_rate += sum_oa_for_floor_area
      tot_oa_flow_rate += sum_oa_rate
      tot_oa_flow_rate += sum_oa_for_volume

      # Convert to cfm
      tot_oa_flow_rate_cfm = OpenStudio.convert(tot_oa_flow_rate, 'm^3/s', 'cfm').get

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}, design min OA = #{tot_oa_flow_rate_cfm.round} cfm.")

      return tot_oa_flow_rate
    end

    # Calculates the zone outdoor airflow requirement and divides by the zone area.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Double] the zone outdoor air flow rate per area in cubic meters per second (m^3/s)
    def self.thermal_zone_get_outdoor_airflow_rate_per_area(thermal_zone)
      tot_oa_flow_rate_per_area = 0.0

      # Find total area of the zone
      sum_floor_area = 0.0
      thermal_zone.spaces.sort.each do |space|
        sum_floor_area += space.floorArea
      end

      # Get the OA flow rate
      tot_oa_flow_rate = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(thermal_zone)

      # Calculate the per-area value
      tot_oa_flow_rate_per_area = tot_oa_flow_rate / sum_floor_area

      # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.ThermalZone", "For #{self.name}, OA per area = #{tot_oa_flow_rate_per_area.round(8)} m^3/s*m^2.")

      return tot_oa_flow_rate_per_area
    end

    # Convert total minimum OA requirement to a per-area value.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if successful, false if not
    def self.thermal_zone_convert_outdoor_air_to_per_area(thermal_zone)
      # For each space in the zone, convert
      # all design OA to per-area
      # unless the "Outdoor Air Method" is "Maximum"
      thermal_zone.spaces.each do |space|
        # Find the design OA, which may be assigned at either the
        # SpaceType or directly at the Space
        dsn_oa = space.designSpecificationOutdoorAir
        next if dsn_oa.empty?

        dsn_oa = dsn_oa.get
        next if dsn_oa.outdoorAirMethod == 'Maximum'

        # Get the space properties
        floor_area = space.floorArea
        number_of_people = space.numberOfPeople
        volume = space.volume

        # Sum up the total OA from all sources
        oa_for_people = number_of_people * dsn_oa.outdoorAirFlowperPerson
        oa_for_floor_area = floor_area * dsn_oa.outdoorAirFlowperFloorArea
        oa_rate = dsn_oa.outdoorAirFlowRate
        oa_for_volume = volume * dsn_oa.outdoorAirFlowAirChangesperHour / 3600
        tot_oa = oa_for_people + oa_for_floor_area + oa_rate + oa_for_volume

        # Convert total to per-area
        tot_oa_per_area = tot_oa / floor_area

        # Check if there is another design OA object that has already
        # been converted from per-person to per-area that matches.
        # If so, reuse that instead of creating a duplicate.
        new_dsn_oa_name = "#{dsn_oa.name} to per-area"
        if thermal_zone.model.getDesignSpecificationOutdoorAirByName(new_dsn_oa_name).is_initialized
          new_dsn_oa = thermal_zone.model.getDesignSpecificationOutdoorAirByName(new_dsn_oa_name).get
        else
          new_dsn_oa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(thermal_zone.model)
          new_dsn_oa.setName(new_dsn_oa_name)
        end

        # Assign this new design OA to the space
        space.setDesignSpecificationOutdoorAir(new_dsn_oa)

        # Set the method
        new_dsn_oa.setOutdoorAirMethod('Sum')
        # Set the per-area requirement
        new_dsn_oa.setOutdoorAirFlowperFloorArea(tot_oa_per_area)
        # Zero-out the per-person, ACH, and flow requirements
        new_dsn_oa.setOutdoorAirFlowperPerson(0.0)
        new_dsn_oa.setOutdoorAirFlowAirChangesperHour(0.0)
        new_dsn_oa.setOutdoorAirFlowRate(0.0)
        # Copy the orignal OA schedule, if any
        if dsn_oa.outdoorAirFlowRateFractionSchedule.is_initialized
          oa_sch = dsn_oa.outdoorAirFlowRateFractionSchedule.get
          new_dsn_oa.setOutdoorAirFlowRateFractionSchedule(oa_sch)
        end

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "For #{thermal_zone.name}: Converted total ventilation requirements to per-area value.")
      end

      return true
    end
  end
end
