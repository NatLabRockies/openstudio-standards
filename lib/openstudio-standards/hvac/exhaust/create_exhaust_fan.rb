module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Exhaust
    # Methods to create exhaust fans

    # Exhaust rates, keyed by all-level space type name with a legacy DOE prototype key.
    #
    # @return [Hash] the parsed contents of data/typical_exhaust.json
    def self.typical_exhaust_data
      @typical_exhaust_data ||= JSON.parse(File.read("#{File.dirname(__FILE__)}/data/typical_exhaust.json"), symbolize_names: true)
    end

    # Where an exhausted space draws its makeup air from.
    #
    # @return [Hash] the parsed contents of data/exhaust_makeup_air.json
    def self.exhaust_makeup_air_data
      @exhaust_makeup_air_data ||= JSON.parse(File.read("#{File.dirname(__FILE__)}/data/exhaust_makeup_air.json"), symbolize_names: true)
    end

    # Look up the exhaust rate for a space type.
    #
    # All-level space type is the key. Exhaust is a property of what happens in the space, not
    # of the building that contains it, so the building type takes no part in the lookup: a
    # kitchen hood moves 0.7 cfm/ft2 whether it is in a restaurant, a hotel or a hospital.
    # Only one record carries a given all-level name, so the result is deterministic.
    #
    # The (space_type, building_type) pair is tried second, for models still built from DOE
    # prototype space type names.
    #
    # @param standards_space_type [String] the space type's standardsSpaceType
    # @param standards_building_type [String, nil] the space type's standardsBuildingType, for the legacy key
    # @return [Double, nil] exhaust rate in cfm/ft2, or nil where the space type has none
    def self.space_type_exhaust_per_area(standards_space_type, standards_building_type = nil)
      records = typical_exhaust_data[:space_types].select do |hash|
        (hash[:all_level_space_types] || []).include?(standards_space_type)
      end

      if records.empty? && !standards_building_type.nil?
        records = typical_exhaust_data[:space_types].select do |hash|
          (hash[:space_type] == standards_space_type) && (hash[:building_type] == standards_building_type)
        end
      end

      return nil if records.empty?

      if records.size > 1
        rates = records.map { |hash| hash[:exhaust_per_area].to_f }.uniq
        if rates.size > 1
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.create_exhaust_fan',
                             "Space type '#{standards_space_type}' matches #{records.size} exhaust records with differing rates (#{rates.join(', ')} cfm/ft2). Using the first. Give the all-level space type a single record to make this deterministic.")
        end
      end

      records[0][:exhaust_per_area].to_f
    end

    # Look up where an exhausted space type draws its makeup air from.
    #
    # @param standards_space_type [String] the exhausted space type's standardsSpaceType
    # @param standards_building_type [String, nil] the space type's standardsBuildingType, for the legacy key
    # @return [Hash, nil] with :space_types (an ordered preference list of standardsSpaceType names),
    #   :building_type (the standardsBuildingType the source must also match, nil on the all-level path)
    #   and :fraction, or nil where the space type has no makeup air source
    def self.exhaust_makeup_air_source(standards_space_type, standards_building_type = nil)
      record = (exhaust_makeup_air_data[:makeup_air] || []).find do |hash|
        hash[:exhaust_space_type] == standards_space_type
      end
      unless record.nil?
        return { space_types: record[:makeup_space_types] || [],
                 building_type: nil,
                 fraction: record[:makeup_air_fraction] || 0.5 }
      end

      return nil if standards_building_type.nil?

      record = (exhaust_makeup_air_data[:legacy_makeup_air] || []).find do |hash|
        (hash[:exhaust_space_type] == standards_space_type) && (hash[:exhaust_building_type] == standards_building_type)
      end
      return nil if record.nil?

      { space_types: [record[:makeup_space_type]],
        building_type: record[:makeup_building_type],
        fraction: record[:makeup_air_fraction] || 0.5 }
    end

    # Fields an exhaust override entry may set.
    EXHAUST_OVERRIDE_FIELDS = [:exhaust_per_area].freeze

    # Apply runtime exhaust overrides to a space type's exhaust rate.
    #
    # Entries are matched the same way schedule, load, thermostat and service water heating
    # overrides are: by schedule set name, all-level space type, ventilation space type, or the
    # '*' wildcard, with a specific entry winning over the wildcard.
    #
    # This is how a building says that a space type does not exhaust the way the space type data
    # says it does. The all-level taxonomy makes a hospital radiology room and an outpatient MRI
    # room the same space type, so tagging 'imaging' with the MRI room's 1.0 cfm/ft2 gives
    # hospital radiology exhaust that the DOE prototype never gave it; a hospital that disagrees
    # says so with an override of 0.0 rather than by removing the rate for everyone.
    #
    # @param exhaust_per_area [Double, nil] the rate from the space type data, in cfm/ft2
    # @param space_type [OpenStudio::Model::SpaceType] the space type being looked up
    # @param standards_space_type [String] the space type's standardsSpaceType
    # @param overrides [Array<Hash>, nil] override entries, each with a `space_type` key and an
    #   `exhaust` hash of fields
    # @return [Double, nil] the overridden rate, or the original where no entry applies
    def self.apply_exhaust_overrides(exhaust_per_area, space_type, standards_space_type, overrides)
      return exhaust_per_area if overrides.nil? || overrides.empty?

      matched = OpenstudioStandards::CreateTypical.resolve_overrides(overrides, space_type,
                                                                    section_keys: [:exhaust],
                                                                    extra_names: [standards_space_type])[:exhaust]
      return exhaust_per_area if matched.nil? || matched.empty?

      applied = matched.select { |key, _| EXHAUST_OVERRIDE_FIELDS.include?(key) }
      return exhaust_per_area unless applied.key?(:exhaust_per_area)

      applied[:exhaust_per_area].nil? ? nil : applied[:exhaust_per_area].to_f
    end

    # Space type pairs that need to end up next to each other for makeup air to connect.
    #
    # Geometry creation has no idea that a kitchen wants a dining space beside it, so an
    # exhausted space type and its makeup air source land adjacent only by accident of the
    # order they happen to be sliced in. This resolves the makeup air data against the space
    # types a model is actually being built from, so create_bar can order its slices to put
    # each pair side by side. Only one makeup space type is returned per exhausted space type:
    # the first one in the preference list that is present.
    #
    # @param standards_space_types [Array<String>] the standardsSpaceType names present in the model
    # @return [Array<Array<String>>] pairs of [exhausted space type, makeup air space type]
    def self.exhaust_makeup_air_pairs(standards_space_types)
      present = standards_space_types.compact.uniq
      pairs = []

      present.each do |standards_space_type|
        makeup = OpenstudioStandards::HVAC.exhaust_makeup_air_source(standards_space_type)
        next if makeup.nil?

        source = makeup[:space_types].find { |name| present.include?(name) }
        next if source.nil?

        pairs << [standards_space_type, source]
      end

      pairs
    end

    # Create and add an exhaust fan to a thermal zone.
    #
    # @param exhaust_zone [OpenStudio::Model::ThermalZone] The zone with the exhaust fan
    # @param make_up_air_source_zone [OpenStudio::Model::ThermalZone] An optional source zone for make-up air
    # @param make_up_air_fraction [Double] The fraction of make-up sourced from make_up_air_source_zone
    # @param exhaust_overrides [Array<Hash>, nil] runtime exhaust overrides. Each entry is keyed by
    #   `space_type` (matched against the schedule set name or the standards space type) or `"*"`,
    #   with an `exhaust` hash whose `exhaust_per_area` replaces the space type's own rate.
    # @return [OpenStudio::Model::FanZoneExhaust] The created exhaust fan
    def self.create_exhaust_fan(exhaust_zone,
                                make_up_air_source_zone: nil,
                                make_up_air_fraction: 0.5,
                                exhaust_overrides: nil)
      # loop through spaces to get standards space information
      space_type_hash = {}
      exhaust_zone.spaces.each do |space|
        next unless space.spaceType.is_initialized
        next unless space.partofTotalFloorArea

        space_type = space.spaceType.get
        if space_type_hash.key?(space_type)
          space_type_hash[space_type][:floor_area_m2] += space.floorArea * space.multiplier
        else
          next unless space_type.standardsSpaceType.is_initialized

          standards_space_type = space_type.standardsSpaceType.get
          standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil

          exhaust_per_area = OpenstudioStandards::HVAC.space_type_exhaust_per_area(standards_space_type, standards_building_type)
          exhaust_per_area = OpenstudioStandards::HVAC.apply_exhaust_overrides(exhaust_per_area, space_type, standards_space_type, exhaust_overrides)

          # skip spaces with no exhaust fan information defined
          next if exhaust_per_area.nil?

          space_type_hash[space_type] = {}
          space_type_hash[space_type][:floor_area_m2] = space.floorArea * space.multiplier
          space_type_hash[space_type][:exhaust_cfm_per_area_ft2] = exhaust_per_area
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

    # Add typical zone exhaust fans to every zone whose space types call for exhaust.
    #
    # This is the module-level replacement for Standard.model_add_exhaust. The behavior is the
    # same in shape: zones whose space type has a makeup air source are done first, so their
    # source zone is still free to receive the transfer air fan, then every remaining zone gets
    # a plain exhaust fan. What differs is the makeup air lookup, which reads
    # data/exhaust_makeup_air.json instead of a hard-coded table of DOE prototype
    # (building_type, space_type) pairs, and so works on models built from all-level space types.
    #
    # Fan pressure rise and efficiency are still prototype properties, so the standard has to
    # be passed in rather than built here.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param hvac_standard [Standard] a Standard object, used for fan pressure rise and efficiency
    # @param makeup_source [String] 'None' or 'Adjacent'. 'Adjacent' draws makeup air from the
    #   largest adjacent zone holding a space of the mapped makeup space type.
    # @param remove_existing_exhaust_fans [Boolean] whether to remove the model's existing zone exhaust fans first
    # @param exhaust_overrides [Array<Hash>, nil] runtime exhaust overrides, see {apply_exhaust_overrides}
    # @return [Array<OpenStudio::Model::FanZoneExhaust>] the created exhaust fans
    def self.create_typical_exhaust(model, hvac_standard,
                                    makeup_source: 'None',
                                    remove_existing_exhaust_fans: true,
                                    exhaust_overrides: nil)
      if remove_existing_exhaust_fans
        model.getThermalZones.sort.each do |thermal_zone|
          thermal_zone.equipment.each { |equip| equip.remove if equip.to_FanZoneExhaust.is_initialized }
        end
      end

      zone_exhaust_fans = []

      # zones whose space type names a makeup air source
      if makeup_source == 'Adjacent'
        model.getThermalZones.sort.each do |thermal_zone|
          next if OpenstudioStandards::HVAC.thermal_zone_has_exhaust_fan?(thermal_zone)

          thermal_zone.spaces.each do |space|
            next unless space.spaceType.is_initialized
            next unless space.partofTotalFloorArea

            space_type = space.spaceType.get
            next unless space_type.standardsSpaceType.is_initialized

            standards_space_type = space_type.standardsSpaceType.get
            standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil

            makeup = OpenstudioStandards::HVAC.exhaust_makeup_air_source(standards_space_type, standards_building_type)
            next if makeup.nil?

            makeup_space = OpenstudioStandards::HVAC.adjacent_makeup_air_space(thermal_zone, makeup)

            if makeup_space.nil?
              OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.create_typical_exhaust',
                                 "Model has zone #{thermal_zone.name} with space type '#{standards_space_type}' but no adjacent zone with #{makeup[:space_types].join(' or ')}. Exhaust will be added, but no makeup air.")
              makeup_thermal_zone = nil
            else
              makeup_thermal_zone = makeup_space.thermalZone.get
            end

            zone_exhaust_fan = OpenstudioStandards::HVAC.create_exhaust_fan(thermal_zone,
                                                                           make_up_air_source_zone: makeup_thermal_zone,
                                                                           make_up_air_fraction: makeup[:fraction],
                                                                           exhaust_overrides: exhaust_overrides)
            next if zone_exhaust_fan.nil?

            hvac_standard.fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)
            hvac_standard.prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)
            zone_exhaust_fans << zone_exhaust_fan
          end
        end
      end

      # every remaining zone
      model.getThermalZones.sort.each do |thermal_zone|
        if OpenstudioStandards::HVAC.thermal_zone_has_exhaust_fan?(thermal_zone)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.create_typical_exhaust', "Thermal zone #{thermal_zone.name} already has an exhaust fan. None will be added.")
          next
        end

        zone_exhaust_fan = OpenstudioStandards::HVAC.create_exhaust_fan(thermal_zone, exhaust_overrides: exhaust_overrides)
        next if zone_exhaust_fan.nil?

        hvac_standard.fan_zone_exhaust_apply_prototype_fan_pressure_rise(zone_exhaust_fan)
        hvac_standard.prototype_fan_apply_prototype_fan_efficiency(zone_exhaust_fan)
        zone_exhaust_fans << zone_exhaust_fan
      end

      return zone_exhaust_fans
    end

    # Retime every zone exhaust fan in the model to the availability of the air loop serving
    # its zone.
    #
    # create_exhaust_fan has to give the fan a schedule when it builds it, and at that point
    # there is no HVAC in the model to ask -- create_typical adds exhaust well before it adds
    # systems -- so the fan is created always on. Left that way it keeps pulling air out of a
    # zone whose air handler has cycled off, and the zone has no supply and no makeup path to
    # replace it. EnergyPlus reports that as an unbalanced air loop and a warmup convergence
    # failure, and then burns the run failing to converge: on a secondary school it turned an
    # 8 minute simulation into 78, with 269 million warnings and 26,440 max-iteration failures
    # against 170.
    #
    # Zones served by zone equipment rather than an air loop are left alone; they have no loop
    # schedule to follow, and no supply air that the exhaust can get out of step with.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Integer] the number of fans retimed
    def self.exhaust_fans_follow_hvac_availability(model)
      retimed = 0
      unmatched = []

      model.getFanZoneExhausts.sort.each do |fan|
        next unless fan.thermalZone.is_initialized

        zone = fan.thermalZone.get
        air_loop = zone.airLoopHVAC
        if air_loop.is_initialized
          fan.setAvailabilitySchedule(air_loop.get.availabilitySchedule)
          retimed += 1
        else
          unmatched << fan.name.to_s
        end
      end

      unless unmatched.empty?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.create_typical_exhaust',
                           "#{unmatched.size} zone exhaust fan(s) are in zones with no air loop and keep their own availability schedule: #{unmatched.first(5).join(', ')}#{unmatched.size > 5 ? ', ...' : ''}.")
      end
      if retimed.positive?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.create_typical_exhaust',
                           "Retimed #{retimed} zone exhaust fan(s) to the availability schedule of the air loop serving their zone.")
      end

      retimed
    end

    # Whether a thermal zone already has a zone exhaust fan.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] true if the zone has a FanZoneExhaust
    def self.thermal_zone_has_exhaust_fan?(thermal_zone)
      thermal_zone.equipment.any? { |equip| equip.to_FanZoneExhaust.is_initialized }
    end

    # Find the largest space in a zone adjacent to exhaust_zone that matches a makeup air source.
    #
    # The makeup space types are an ordered preference list, so a school kitchen takes its own
    # cafeteria over a general dining space when both are adjacent.
    #
    # @param exhaust_zone [OpenStudio::Model::ThermalZone] the zone being exhausted
    # @param makeup [Hash] as returned by {exhaust_makeup_air_source}
    # @return [OpenStudio::Model::Space, nil] the largest matching adjacent space, or nil if there is none
    def self.adjacent_makeup_air_space(exhaust_zone, makeup)
      adjacent_zones = OpenstudioStandards::Geometry.thermal_zone_get_adjacent_zones_with_shared_walls(exhaust_zone)

      makeup[:space_types].each do |makeup_space_type|
        makeup_space = nil
        adjacent_zones.each do |adjacent_zone|
          adjacent_zone.spaces.each do |adjacent_space|
            next unless adjacent_space.spaceType.is_initialized
            next unless adjacent_space.partofTotalFloorArea

            adjacent_space_type = adjacent_space.spaceType.get
            next unless adjacent_space_type.standardsSpaceType.is_initialized
            next unless adjacent_space_type.standardsSpaceType.get == makeup_space_type

            unless makeup[:building_type].nil?
              next unless adjacent_space_type.standardsBuildingType.is_initialized
              next unless adjacent_space_type.standardsBuildingType.get == makeup[:building_type]
            end

            makeup_space = adjacent_space if makeup_space.nil? || (adjacent_space.floorArea > makeup_space.floorArea)
          end
        end
        return makeup_space unless makeup_space.nil?
      end

      nil
    end
  end
end
