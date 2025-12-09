module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Exhaust
    # Methods to create exhaust fans

    # Create and add an exhaust fan to a thermal zone.
    #
    # @param exhaust_zone [OpenStudio::Model::ThermalZone] The zone with the exhaust fan
    # @param make_up_air_source_zone [OpenStudio::Model::ThermalZone] An optional source zone for make-up air
    # @param make_up_air_fraction [Double] The fraction of make-up sourced from make_up_air_source_zone
    # @return [OpenStudio::Model::FanZoneExhaust] The created exhaust fan
    def self.create_exhaust_fan(exhaust_zone,
                                make_up_air_source_zone: nil,
                                make_up_air_fraction: 0.5)
      # load exhaust fan data
      exhaust_fan_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/typical_exhaust.json"), symbolize_names: true)

      # loop through spaces to get standards space information
      space_type_hash = {}
      exhaust_zone.spaces.each do |space|
        next unless space.spaceType.is_initialized
        next unless space.partofTotalFloorArea

        space_type = space.spaceType.get
        if space_type_hash.key?(space_type)
          space_type_hash[space_type][:floor_area_m2] += space.floorArea * space.multiplier
        else

          # get exhaust space type from the object
          next unless space_type.additionalProperties.hasFeature('ventilation_space_type')

          ventilation_space_type = space_type.additionalProperties.getFeatureAsString('ventilation_space_type').to_s

          # skip spaces types with no ventilation space type defined
          next if ventilation_space_type.nil?

          # skip spaces type with no exhaust fan in this ventilation space type
          exhaust_fan_properties = exhaust_fan_data.select { |hash| hash[:ventilation_space_type] == ventilation_space_type }
          next if exhaust_fan_properties.empty?

          # get standards building type and use specific standards building type information if present
          if space_type.standardsBuildingType.is_initialized
            standards_building_type = space_type.standardsBuildingType.get
            building_type_specific_properties = exhaust_fan_data.select { |hash| (hash[:ventilation_space_type] == ventilation_space_type) && (hash[:standards_building_type] == standards_building_type) }
            unless building_type_specific_properties.empty?
              exhaust_fan_properties = building_type_specific_properties
            end
          end

          # skip spaces with no exhaust fan information defined
          if exhaust_fan_properties.empty?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.exhaust', "Space type '#{space_type.name}' has ventilation space type #{ventilation_space_type} but unable to find exhaust fan properties for this ventilation space type.")
            next
          end
          exhaust_fan_properties = exhaust_fan_properties[0]

          space_type_hash[space_type] = {}
          space_type_hash[space_type][:floor_area_m2] = space.floorArea * space.multiplier
          space_type_hash[space_type][:exhaust_cfm_per_area_ft2] = exhaust_fan_properties[:exhaust_per_area]
        end
      end

      # total exhaust
      exhaust_m3_per_s = 0.0
      space_type_hash.each do |space_type, fields|
        floor_area_ft2 = OpenStudio.convert(fields[:floor_area_m2], 'm^2', 'ft^2').get
        cfm = fields[:exhaust_cfm_per_area_ft2].to_f * floor_area_ft2.to_f
        exhaust_m3_per_s += OpenStudio.convert(cfm, 'cfm', 'm^3/s').get
      end

      if exhaust_m3_per_s.zero?
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.HVAC.create_exhaust_fan', "Calculated zero flow rate for thermal zone #{exhaust_zone.name}. No exhaust fan added.")
        return nil
      end

      # placeholders for exhaust schedules
      # @todo get the building HVAC schedule
      exhaust_availability_schedule = exhaust_zone.model.alwaysOnDiscreteSchedule
      exhaust_flow_fraction_schedule = exhaust_zone.model.alwaysOnDiscreteSchedule

      # add exhaust fan
      zone_exhaust_fan = OpenStudio::Model::FanZoneExhaust.new(exhaust_zone.model)
      zone_exhaust_fan.setName("#{exhaust_zone.name} Exhaust Fan")
      zone_exhaust_fan.setAvailabilitySchedule(exhaust_availability_schedule)
      zone_exhaust_fan.setFlowFractionSchedule(exhaust_flow_fraction_schedule)
      zone_exhaust_fan.setMaximumFlowRate(exhaust_m3_per_s)
      zone_exhaust_fan.setEndUseSubcategory('Zone Exhaust Fans')
      zone_exhaust_fan.addToThermalZone(exhaust_zone)

      # add objects to account for makeup air
      unless make_up_air_source_zone.nil?
        # add balanced exhaust schedule to zone_exhaust_fan
        balanced_exhaust_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(make_up_air_source_zone.model, make_up_air_fraction,
                                                                                                    name: "#{exhaust_zone.name} Balanced Exhaust Fraction Schedule",
                                                                                                    schedule_type_limit: 'Fraction')
        zone_exhaust_fan.setBalancedExhaustFractionSchedule(balanced_exhaust_schedule)

        # use max value of balanced exhaust fraction schedule for maximum flow rate
        max_sch_val = OpenstudioStandards::Schedules.schedule_get_min_max(balanced_exhaust_schedule)['max']
        transfer_air_m3_per_s = exhaust_m3_per_s * max_sch_val

        # add dummy exhaust fan to account for loss of transfer air
        transfer_air_source_zone_exhaust = OpenStudio::Model::FanZoneExhaust.new(exhaust_zone.model)
        transfer_air_source_zone_exhaust.setName("#{exhaust_zone.name} Transfer Air Source")
        transfer_air_source_zone_exhaust.setAvailabilitySchedule(exhaust_availability_schedule)
        transfer_air_source_zone_exhaust.setMaximumFlowRate(transfer_air_m3_per_s)
        transfer_air_source_zone_exhaust.setFanEfficiency(1.0)
        transfer_air_source_zone_exhaust.setPressureRise(0.0)
        transfer_air_source_zone_exhaust.setEndUseSubcategory('Zone Exhaust Fans')
        transfer_air_source_zone_exhaust.addToThermalZone(make_up_air_source_zone)

        # add zone mixing
        zone_mixing = OpenStudio::Model::ZoneMixing.new(exhaust_zone)
        zone_mixing.setSchedule(exhaust_flow_fraction_schedule)
        zone_mixing.setSourceZone(make_up_air_source_zone)
        zone_mixing.setDesignFlowRate(transfer_air_m3_per_s)
      end

      return zone_exhaust_fan
    end
  end
end
