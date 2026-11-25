class NECB2011
  def add_all_spacetypes_to_model(model)
    # Get the space Type data from @standards data
    spacetype_data = nil
    if @standards_data['space_types'].is_a?(Hash) == true
      spacetype_data = @standards_data['space_types']['table']
    else
      spacetype_data = @standards_data['space_types']
    end
    spacetype_data.each do |spacedata|
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setStandardsSpaceType(spacedata['space_type'])
      space_type.setStandardsBuildingType(spacedata['building_type'])
      space_type.setName("#{spacedata['building_type']} #{spacedata['space_type']}")
      # Loads
      space_type_apply_internal_loads(space_type: space_type)

      # Schedules
      space_type_apply_internal_load_schedules(space_type)
      space_type_apply_thermostat_schedules(space_type)
    end
  end

  ##
  # Returns minimum outdoor air (OA) supply rates (in L/s) for a dwelling space,
  # based on selected ventilation standard: (i) "a622" (ANSI/ASHRAE 62.2 2016,
  # recommended), (ii) "a621" (ANSI/ASHRAE 62.1 2016) or (iii) "nbc932"
  # (National Building Code of Canada 2025). The method doesn't double check
  # whether a space's spacetype is actually a dwelling - users must do this
  # beforehand. Relies on dwelling and bedroom counts to estimate the likely
  # number of dwellings in a multi-dwelling space.
  #
  # @param space [OpenStudio::Model::Space] a dwelling space
  # @param std [String] user-selected dwelling ventilation standard
  #
  # @return [Float] estimated OA rates in L/s
  def dwelling_oa(space = nil, std = "a622")
    return 0 unless space.is_a?(OpenStudio::Model::Space)

    std = "a622" unless ["a622", "a621", "nbc932"].include?(std)
    nD  = BTAP::Geometry::Spaces.nDwellings(space)
    nB  = BTAP::Geometry::Spaces.nBedrooms(space)
    pZ  = nB/nD.to_i + 1 # zone population
    pZ *= nD
    aZ  = space.floorArea

    # NBC 9.32 OA rates strictly based on bedroom count.
    if std == "nbc932"
      return nD * case (nB.to_f / nD).to_i
                  when 1 then 16
                  when 2 then 18
                  when 3 then 22
                  when 4 then 26
                  else        30
                  end
    elsif std == "a621"
      rA = 0.30
      rP = 2.50
    else       # "a622"
      rA = 0.15
      rP = 3.50
    end

    (rA * aZ) + (rP * pZ)
  end

  ##
  # Sets dwelling unit outdoor air (OA) supply and exhaust air (EXH) ventilation
  # requirements, based on user-selected ventilation standard: (i) "a622"
  # (ANSI/ASHRAE 62.2 2016, recommended), (ii) "a621" (ANSI/ASHRAE 62.1 2016),
  # (iii) "nbc932" (National Building Code of Canada 2025). An empty string
  # defaults to BTAP's current solution: ANSI/ASHRAE 62.1 yet with NECB
  # occupancy count. The method doesn't double check whether a space's spacetype
  # is actually a dwelling - users must do this beforehand.
  #
  # @param spaces [Set<OpenStudio::Model::Space>] target space(s)
  # @param std [String] user-selected dwelling ventilation standard
  # @param ventless [Boolean] whether clothes dryers are ventless
  #
  # @return [Boolean] true if successful
  def set_dwelling_ventilation(spaces = nil, std = "a622", ventless = false)
    ventless = false unless [true, false].include?(ventless)
    spaces   = spaces.is_a?(OpenStudio::Model::Space) ? [spaces] : spaces
    spaces   = spaces.respond_to?(:to_a) ? spaces.to_a : []
    return false if spaces.empty?
    return false unless ["a622", "a621", "nbc932"].include?(std)

    ref = case std
          when "nbc932" then "NBC Canada 9.32 2025"
          when "a621"   then "ANSI/ASHRAE 62.1 2016"
          else               "ANSI/ASHRAE 62.2 2016"
          end

    spaces.each do |space|
      next unless space.respond_to?(:setSpaceType)

      # Dwelling ventilation depends largely on bedroom count: either directly
      # (NBC 2020 9.32 requirements), or indirectly by setting the number of
      # occupants per bedroom (ANSI/ASHRAE 62.1 and 62.2 2016). By default, each
      # dwelling space in BTAP MURB prototype models holds a single unit. The
      # LEEPMultiTower is an outlier: it holds spaces that clearly encompass
      # multiple dwelling units:
      #   - Space 1087 : 281 m2 (3025 ft2) ... 4 or 5 units?
      #   - Space 1083 : 281 m2 (3025 ft2) ... 4 or 5 units?
      #   - Space 1029 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1041 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1035 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1053 : 565 m2 (6071 ft2) ... 8 or 9 units?
      #   - Space 1038 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1081 : 565 m2 (6071 ft2) ... 8 or 9 units?
      #   - Space 1008 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1002 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1055 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1005 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #   - Space 1032 : 253 m2 (2723 ft2) ... 3 or 4 units?
      #
      # If BTAP can't automatically determine the number of bedrooms in a given
      # OpenStudio space, or whether a space aggregates more than one dwelling
      # unit, it can't reliably establish the number of people for OA & EXH rate
      # calculations using any of the candidate procedures.
      nD = BTAP::Geometry::Spaces.nDwellings(space)
      nB = BTAP::Geometry::Spaces.nBedrooms(space) # considers dwelling count

      # Dwellings require separate exhaust paths for intermittent use of kitchen
      # hoods and clothes dryers - their exhausted air should not be directed
      # towards ERV/HRV equipment, for instance. They are in fact exempted from
      # NECB-required energy recovery requirements, as they exhaust smoke,
      # grease-laden vapours and/or dust (5.2.10.1.3).
      #
      # There is limited field evidence on the time-varying use of kitchen
      # hood and dryer exhaust ventilation in new Canadian MURBs, e.g.
      #   - number of discrete uses per unit/bedroom count
      #   - average duration of each cycle
      #   - distribution of user-selected kitchen hood exhaust flow rates
      #   - time of day, weekday vs weekend
      #   - diversity in scheduling between dwellings
      #
      # Postulates below are largely based on this recent study:
      #
      #   Rouleau et Gosselin (2019) "Preliminary investigation on the use of
      #   exhaust fans in dwellings and their impact on energy balance",
      #   Proceedings of the Symposium on Energy Efficiency in Buildings and
      #   Industry (Sherbrooke, 2019), www.mdpi.com/2504-3900/23/1/8.
      #
      # For instance, the average duration of a kitchen range hood is estimated
      # to be approximately 1 hour/day for 2-bedroom units - 30 minutes for
      # 1-bedroom units. NBC 2025 9.32.3, as well as both ANSI/ASHRAE 2016 62.1
      # and 62.2, require an intermittent vented kitchen range hood EXH rate of
      # at least 50 L/s:
      #
      #   1-bed: 50 L/s x 900s/24h x 1h/3600s x (1+1) = ~1.0 L/s
      #   2-bed: 50 L/s x 900s/24h x 1h/3600s x (2+1) = ~1.5 L/s
      qHOOD = 50.0 * 900/24/3600 * ((nB.to_f/nD).to_i + 1) * nD

      # Clothes dryers may exhaust anywhere from 50 to 100 L/s, depending on the
      # load and make/model. A commonly cited rate is approximately 70 L/s. The
      # average cycle duration is estimated to be around 20 minutes, while the
      # number of cycles per week is based on bedroom count (+1):
      #
      #   1-bed: 70 L/s x 1200s/168h x 1h/3600s x (1+1) = ~0.30 L/s
      #   2-bed: 70 L/s x 1200s/168h x 1h/3600s x (2+1) = ~0.40 L/s
      qDRYER = 70.0 * 1200/168/3600 * ((nB.to_f/nD).to_i + 1) * nD

      # By default, both kitchen hood exhaust and clothes dryer exhaust are
      # added as distinct OpenStudio 'FanZoneExhaust' objects. While vented
      # kitchen hoods are expected in dwellings, it is not uncommon to encounter
      # ventless clothes dryers in more recent MURBs.

      # It is suggested (for now) to simply spread out aggregate exhaust air
      # rates in each dwelling over each 24-hour period. This remains a coarse
      # approximation, potentially adjusted through scheduling in the future.

      # Each BTAP dwelling is assumed to include a single bathroom. Contrary to
      # kitchen hood and clothes dryer exhaust air, bathroom exhaust air can be
      # ducted towards ERV/HRV equipment (i.e. dwelling 'return' air), whether
      # dealing with a central MAU or local HRV per dwelling.
      #
      # Both ANSI/ASHRAE 62.1 and 62.2 2016 requires either (per bathroom):
      #   - demand-controlled (intermittent) local exhaust of 25 L/s, or
      #   - continuous local exhaust of 10 L/s (62.2) or 12.5 L/s (62.1)
      #
      # Setting aside the continuous option, the challenge is reasonably
      # estimating the number of times bathroom exhaust fans may be activated by
      # dwelling occupants. Most wall-mounted bathroom exhaust controls limit
      # fan operation to a maximum of 30 consecutive minutes (or 1,800 seconds).
      # The number of distinct 30-min fan uses within a day is estimated based
      # on the number of bedrooms (+1). As with kitchen hood and clothes dryer
      # exhaust rates, bathroom exhaust needs are simply spread out over a 24h
      # period, yielding a continuous 1 to 2 L/s per dwelling:
      #
      #   qWC = 25 L/s x 1800s/24h x 1h/3600s x (nb bedrooms + 1) [L/s]
      #
      # 3 examples cases:
      #   - 1-bed: 25 L/s x 1800s/24h x 1h/3600s x (1+1) = ~1.0 L/s
      #   - 2-bed: 25 L/s x 1800s/24h x 1h/3600s x (2+1) = ~1.5 L/s
      #   - 3-bed: 25 L/s x 1800s/24h x 1h/3600s x (3+1) = ~2.0 L/s
      #
      # Bathroom exhaust rates (L/s per dwelling) are rounded off to the first
      # decimal, given the high degree of uncertainty in terms of actual
      # occupancy densities and occupant behaviour.
      qWC = 25.0 * 1800/24/3600 * ((nB.to_f/nD).to_i + 1) * nD

      # For a (small) 43 m2 studio, the intermittent 25 L/s bathroom EXH rate is
      # approximately twice the required OA rate of ~12.5 L/s (at 0.29 L/s per
      # m2). OA supply would need to be temporarily boosted as (additional)
      # makeup air. It is for this reason that dwelling OA rates in BTAP are
      # increased, despite spreading EXH needs over a 24-hour period.
      qOA = dwelling_oa(space, std) + qWC

      # Ensure EXH are <= 10% of supply rates. Raise OA rates if needed.
      qEXH  = qHOOD
      qEXH += qDRYER unless ventless
      qOA   = [qOA, 10 * qEXH].max

      # Each dwelling space inherits:
      #   - 1x 'DesignSpecificationOutdoorAir' object
      #   - associated 'AdditionalProperties' object
      space.resetDesignSpecificationOutdoorAir
      oa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space.model)
      oa.setName("#{space.nameString} OA Design Specs")
      oa.setOutdoorAirFlowRate(qOA/1000) # m3/s
      space.setDesignSpecificationOutdoorAir(oa)

      # Add supplyfan exhaust flows as OA AdditionalProperties. Ensure IP units.
      ft2    = OpenStudio.convert(space.floorArea, 'm^2', 'ft^2').get
      qOA    = OpenStudio.convert(qOA, "L/s", "cfm").get
      qHOOD  = OpenStudio.convert(qHOOD, "L/s", "cfm").get
      qDRYER = OpenStudio.convert(qDRYER, "L/s", "cfm").get

      notes = oa.additionalProperties
      notes.setFeature("Ref OA cfm", qOA)
      notes.setFeature("Ref OA per area", 0.0)
      notes.setFeature("Ref OA per person", 0.0)
      notes.setFeature("Ref OA ach", 0.0)
      notes.setFeature("Ref occupancy per 1000ft2", 0.0)
      notes.setFeature("Ref standard", ref)
      notes.setFeature("Ref space type", "Dwelling unit")
      notes.setFeature("HOOD EXH cfm", qHOOD)
      notes.setFeature("DRYER EXH cfm", qDRYER)
    end

    true
  end

  ##
  # Sets the selected internal loads to standards-based or typical values. Get
  # all load instances for each selected category. Remove all but the first
  # instance if multiple instances. Add a new instance/definition if no instance
  # exists. Modify the definition for the remaining instance to have the
  # specified values. If 'set_people' is true, assign reasonable clothing, air
  # velocity, and work efficiency inputs to allow reasonable thermal comfort
  # metrics to be calculated. If 'set_lights' is true, set lighting density,
  # lighting fraction to return air, fraction radiant, and fraction visible.
  # This method does not alter any loads directly assigned to spaces, except for
  # dwellings. Accepted dwelling ventilation options: (i) "a622" (ANSI/ASHRAE
  # 62.2 2016, recommended), (ii) "a621" (ANSI/ASHRAE 62.1 2016), (iii) "nbc932"
  # (National Building Code of Canada 2025). An empty string defaults to BTAP's
  # current solution: ANSI/ASHRAE 62.1 yet with NECB occupancy count. This
  # method skips unoccupied spaces like plenums.
  #
  # @author btap (original author?)
  # @author denis@rd2.ca (dwelling ventilation edits)
  #
  # @param space_type [OpenStudio::Model::SpaceType] a spacetype
  # @param set_people [Boolean] whether to set people
  # @param set_lights [Boolean] if true, set lighting
  # @param set_electric_equipment [Boolean] whether to set electric equipment
  # @param set_gas_equipment [Boolean] whether to set gas equipment
  # @param set_ventilation [Boolean] whether to set ventilation rates
  # @param set_infiltration [Boolean] whether to set infiltration rates
  # @param lights_type [String] lighting type
  # @param lights_scale [Float] lighting scaling factor
  # @param murb_oa [String] dwelling ventilation standard
  # @param ventless [Boolean] whether (dwelling) clothes dryers are ventless
  #
  # @return [Boolean] true if successful, false if not
  def space_type_apply_internal_loads(space_type: nil,
                                      set_people: true,
                                      set_lights: true,
                                      set_electric_equipment: true,
                                      set_gas_equipment: true,
                                      set_ventilation: true,
                                      set_infiltration: true,
                                      lights_type: 'NECB_Default',
                                      lights_scale: 1.0,
                                      murb_oa: "a622",
                                      ventless: false)

    murb_oa  = "a622" unless ["a621", "nbc932", ""].include?(murb_oa)
    ventless = false unless [true, false].include?(ventless)
    return false unless space_type.is_a?(OpenStudio::Model::SpaceType)

    # Skip unoccupied spaces, like plenums or undefined spaces.
    space_type.spaces.each do |space|
      return false unless space.partofTotalFloorArea
    end

    # Get the space Type data from @standards data
    spacetype_data = @standards_data['tables']['space_types']['table']

    standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
    standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
    space_type_properties = spacetype_data.detect { |s| (s['building_type'] == standards_building_type) && (s['space_type'] == standards_space_type) }

    # Avoids crash on space_type_properties['occupancy_per_area'].to_f below.
    if space_type_properties.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} was not found in the standards data.")
      return false
    end

    # People (JSON property 'occupancy_per_area' == occupants/1000ft2).
    occupancy_per_area = space_type_properties['occupancy_per_area'].to_f
    people_have_info = occupancy_per_area.zero? ? false : true

    if set_people && people_have_info
      instances = space_type.people.sort

      # Remove all but the first instance.
      if instances.empty?
        # Create a new definition and instance.
        definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
        definition.setName("#{space_type.name} People Definition")
        instance = OpenStudio::Model::People.new(definition)
        instance.setName("#{space_type.name} People")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no people, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance.
      space_type.people.sort.each do |inst|
        definition = inst.peopleDefinition

        unless occupancy_per_area.zero?
          definition.setPeopleperSpaceFloorArea(OpenStudio.convert(occupancy_per_area / 1000, 'people/ft^2', 'people/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set occupancy to #{occupancy_per_area} people/1000 ft^2.")
        end

        # Set fraction radiant.
        definition.setFractionRadiant(0.3)

        # Clothing schedule for thermal comfort metrics.
        clothing_sch = space_type.model.getScheduleRulesetByName('Clothing Schedule')

        if clothing_sch.is_initialized
          clothing_sch = clothing_sch.get
        else
          clothing_sch = OpenStudio::Model::ScheduleRuleset.new(space_type.model)
          clothing_sch.setName('Clothing Schedule')
          clothing_sch.defaultDaySchedule.setName('Clothing Schedule Default Winter Clothes')
          clothing_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
          sch_rule = OpenStudio::Model::ScheduleRule.new(clothing_sch)
          sch_rule.daySchedule.setName('Clothing Schedule Summer Clothes')
          sch_rule.daySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.5)
          sch_rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(5), 1))
          sch_rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(9), 30))
        end
        inst.setClothingInsulationSchedule(clothing_sch)

        # Air velocity schedule for thermal comfort metrics.
        air_velo_sch = space_type.model.getScheduleRulesetByName('Air Velocity Schedule')

        if air_velo_sch.is_initialized
          air_velo_sch = air_velo_sch.get
        else
          air_velo_sch = OpenStudio::Model::ScheduleRuleset.new(space_type.model)
          air_velo_sch.setName('Air Velocity Schedule')
          air_velo_sch.defaultDaySchedule.setName('Air Velocity Schedule Default')
          air_velo_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.2)
        end
        inst.setAirVelocitySchedule(air_velo_sch)

        # Work efficiency schedule for thermal comfort metrics.
        work_efficiency_sch = space_type.model.getScheduleRulesetByName('Work Efficiency Schedule')

        if work_efficiency_sch.is_initialized
          work_efficiency_sch = work_efficiency_sch.get
        else
          work_efficiency_sch = OpenStudio::Model::ScheduleRuleset.new(space_type.model)
          work_efficiency_sch.setName('Work Efficiency Schedule')
          work_efficiency_sch.defaultDaySchedule.setName('Work Efficiency Schedule Default')
          work_efficiency_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
        end
        inst.setWorkEfficiencySchedule(work_efficiency_sch)
      end
    end

    # Lights.
    apply_standard_lights(set_lights: set_lights,
                          space_type: space_type,
                          space_type_properties: space_type_properties,
                          lights_type: lights_type,
                          lights_scale: lights_scale)

    # Electric Equipment.
    elec_equip_have_info = false
    elec_equip_per_area = space_type_properties['electric_equipment_per_area'].to_f
    elec_equip_frac_latent = space_type_properties['electric_equipment_fraction_latent'].to_f
    elec_equip_frac_radiant = space_type_properties['electric_equipment_fraction_radiant'].to_f
    elec_equip_frac_lost = space_type_properties['electric_equipment_fraction_lost'].to_f
    elec_equip_have_info = true unless elec_equip_per_area.zero?

    if set_electric_equipment && elec_equip_have_info
      instances = space_type.electricEquipment.sort

      # Remove all but the first instance.
      if instances.empty?
        definition = OpenStudio::Model::ElectricEquipmentDefinition.new(space_type.model)
        definition.setName("#{space_type.name} Elec Equip Definition")
        instance = OpenStudio::Model::ElectricEquipment.new(definition)
        instance.setName("#{space_type.name} Elec Equip")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no electric equipment, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance.
      space_type.electricEquipment.sort.each do |inst|
        definition = inst.electricEquipmentDefinition

        unless elec_equip_per_area.zero?
          definition.setWattsperSpaceFloorArea(OpenStudio.convert(elec_equip_per_area.to_f, 'W/ft^2', 'W/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set electric EPD to #{elec_equip_per_area} W/ft^2.")
        end

        unless elec_equip_frac_latent.zero?
          definition.setFractionLatent(elec_equip_frac_latent)
        end

        unless elec_equip_frac_radiant.zero?
          definition.setFractionRadiant(elec_equip_frac_radiant)
        end

        unless elec_equip_frac_lost.zero?
          definition.setFractionLost(elec_equip_frac_lost)
        end
      end
    end

    # Gas Equipment.
    gas_equip_have_info = false
    gas_equip_per_area = space_type_properties['gas_equipment_per_area'].to_f
    gas_equip_frac_latent = space_type_properties['gas_equipment_fraction_latent'].to_f
    gas_equip_frac_radiant = space_type_properties['gas_equipment_fraction_radiant'].to_f
    gas_equip_frac_lost = space_type_properties['gas_equipment_fraction_lost'].to_f
    gas_equip_have_info = true unless gas_equip_per_area.zero?

    if set_gas_equipment && gas_equip_have_info
      instances = space_type.gasEquipment.sort

      # Remove all but the first instance.
      if instances.empty?
        definition = OpenStudio::Model::GasEquipmentDefinition.new(space_type.model)
        definition.setName("#{space_type.name} Gas Equip Definition")
        instance = OpenStudio::Model::GasEquipment.new(definition)
        instance.setName("#{space_type.name} Gas Equip")
        instance.setSpaceType(space_type)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no gas equipment, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance.
      space_type.gasEquipment.sort.each do |inst|
        definition = inst.gasEquipmentDefinition

        unless gas_equip_per_area.zero?
          definition.setWattsperSpaceFloorArea(OpenStudio.convert(gas_equip_per_area.to_f, 'Btu/hr*ft^2', 'W/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set gas EPD to #{elec_equip_per_area} Btu/hr*ft^2.")
        end

        unless gas_equip_frac_latent.zero?
          definition.setFractionLatent(gas_equip_frac_latent)
        end

        unless gas_equip_frac_radiant.zero?
          definition.setFractionRadiant(gas_equip_frac_radiant)
        end

        unless gas_equip_frac_lost.zero?
          definition.setFractionLost(gas_equip_frac_lost)
        end
      end
    end

    # Ventilation.
    ventilation_per_area = space_type_properties['ventilation_per_area'].to_f
    ventilation_per_person = space_type_properties['ventilation_per_person'].to_f
    ventilation_ach = space_type_properties['ventilation_air_changes'].to_f
    ventilation_occupancy_per_area = space_type_properties['ventilation_occupancy_rate_people_per_1000ft2'].to_f

    ventilation_have_info = false
    ventilation_have_info = true unless ventilation_per_area.zero?
    ventilation_have_info = true unless ventilation_per_person.zero?
    ventilation_have_info = true unless ventilation_ach.zero?

    # Get the design OA or create a new one if none exists.
    ventilation = space_type.designSpecificationOutdoorAir

    if ventilation.is_initialized
      ventilation = ventilation.get
    else
      ventilation = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
      ventilation.setName("#{space_type.name} Ventilation")
      space_type.setDesignSpecificationOutdoorAir(ventilation)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no ventilation specification, one has been created.")
    end

    if set_ventilation && ventilation_have_info
      # Modify the ventilation properties.
      ventilation.setOutdoorAirMethod('Sum')

      unless ventilation_per_area.zero?
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(ventilation_per_area.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation per area to #{ventilation_per_area} cfm/ft^2.")
      end

      unless ventilation_per_person.zero?
        # The occupancy per area rate for ventilation is different from the occupancy used for other loads as the occupancy assumption in the applicable
        # ventilation standard is followed.  The mod_ventilation_per_person rate adjusts the per person ventilation rate (from the standard) so that the
        # correct ventilation rate (per the standard) is calculated when using the NECB occupant density (defined as occupancy_per_area in the space_types.json file)
        # Later the method thermal_zone_convert_outdoor_air_to_per_area (in standards) uses the space occupancy which is the NECB figure to get the total vent rate.
        mod_ventilation_per_person = ventilation_per_person * ventilation_occupancy_per_area / occupancy_per_area
        ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(mod_ventilation_per_person.to_f, 'ft^3/min*person', 'm^3/s*person').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation per person to #{mod_ventilation_per_person} cfm/person.")
      end

      unless ventilation_ach.zero?
        ventilation.setOutdoorAirFlowAirChangesperHour(ventilation_ach)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation to #{ventilation_ach} ACH.")
      end

      # Add information about the source to an additional properties object. Used in unit testing but could be useful elsewhere.
      notes = ventilation.additionalProperties
      notes.setFeature("Ref OA cfm", 0.0)
      notes.setFeature("Ref OA per area", space_type_properties['ventilation_per_area'].to_f)
      notes.setFeature("Ref OA per person", space_type_properties['ventilation_per_person'].to_f)
      notes.setFeature("Ref OA ach", space_type_properties['ventilation_air_changes'].to_f)
      notes.setFeature("HOOD EXH cfm", 0.0)
      notes.setFeature("DRYER EXH cfm", 0.0)
      notes.setFeature("Ref occupancy per 1000ft2", space_type_properties['ventilation_occupancy_rate_people_per_1000ft2'].to_f)
      notes.setFeature("Ref standard", space_type_properties['ventilation_occupancy_standard'].to_s)
      notes.setFeature("Ref space type", space_type_properties['ventilation_standard_space_type'].to_s)
    elsif set_ventilation && !ventilation_have_info
      # All space types must have a design spec OA
      # object for ventilation controls to work correctly,
      # even if the values are all zero.
      ventilation.setOutdoorAirFlowperFloorArea(0)
      ventilation.setOutdoorAirFlowperPerson(0)
      ventilation.setOutdoorAirFlowAirChangesperHour(0)
    end

    # If user selects a valid ventilation standard for a dwelling spacetype, set
    # 'DesignSpecificationOutdoorAir' definitions at the space level - see
    # 'set_dwelling_ventilation' (above) for rationale. Keeping (now possibly
    # contradictory) spacetype 'DesignSpecificationOutdoorAir' definition just
    # in case - may be preferable to delete altogether (@todo).
    if space_type.nameString.downcase.include?("dwelling") && !murb_oa.empty?
      set_dwelling_ventilation(space_type.spaces, murb_oa, ventless)
    end

    # Infiltration.
    infiltration_have_info = false
    infiltration_per_area_ext = space_type_properties['infiltration_per_exterior_area'].to_f
    infiltration_per_area_ext_wall = space_type_properties['infiltration_per_exterior_wall_area'].to_f
    infiltration_ach = space_type_properties['infiltration_air_changes'].to_f

    unless infiltration_per_area_ext.zero? && infiltration_per_area_ext_wall.zero? && infiltration_ach.zero?
      infiltration_have_info = true
    end

    return unless set_infiltration && infiltration_have_info

    # Remove all but the first instance.
    instances = space_type.spaceInfiltrationDesignFlowRates.sort

    if instances.empty?
      instance = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(space_type.model)
      instance.setName("#{space_type.name} Infiltration")
      instance.setSpaceType(space_type)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no infiltration objects, one has been created.")
      instances << instance
    elsif instances.size > 1
      instances.each_with_index do |inst, i|
        next if i.zero?

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
        inst.remove
      end
    end

    # Modify each instance.
    space_type.spaceInfiltrationDesignFlowRates.sort.each do |inst|
      unless infiltration_per_area_ext.zero?
        inst.setFlowperExteriorSurfaceArea(OpenStudio.convert(infiltration_per_area_ext.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration to #{ventilation_ach} per ft^2 exterior surface area.")
      end

      unless infiltration_per_area_ext_wall.zero?
        inst.setFlowperExteriorWallArea(OpenStudio.convert(infiltration_per_area_ext_wall.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration to #{infiltration_per_area_ext_wall} per ft^2 exterior wall area.")
      end

      unless infiltration_ach.zero?
        inst.setAirChangesperHour(infiltration_ach)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set infiltration to #{ventilation_ach} ACH.")
      end
    end
  end
end
