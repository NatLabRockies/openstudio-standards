class Standard
  # @!group People

  # Apply people from ventilation standards data to a space type
  # Create a DesignSpecificationOutdoorAir air object and assign it to the SpaceType
  #
  # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object to apply people to
  # @param thermal_comfort_models [Array<String>] optional argument to determine which thermal comfort model to use. Can select multiple with an array. Options are Fanger, Pierce, KSU, AdaptiveASH55, AdaptiveCEN15251, CoolingEffectASH55, and AnkleDraftASH55.
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_people(space_type, thermal_comfort_models: ['AdaptiveASH55'])
    # Skip plenums
    if space_type.name.get.to_s.downcase.include?('plenum')
      return false
    end

    if space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum')
      return false
    end

    # Get the standards data
    # @todo replace this look from standards_data['space_types'] to ventilation data directly, use 62.1 as a Standard
    space_type_properties = space_type_get_standards_data(space_type)

    # Ensure space_type_properties available
    if space_type_properties.nil? || space_type_properties.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} was not found in the standards data.")
      return false
    end

    # People
    people_have_info = false
    occupancy_per_area = space_type_properties['occupancy_per_area'].to_f
    people_have_info = true unless occupancy_per_area.zero?

    if people_have_info
      # Remove all but the first instance
      instances = space_type.people.sort
      if instances.empty?
        # Create a new definition and instance
        definition = OpenStudio::Model::PeopleDefinition.new(space_type.model)
        definition.setName("#{space_type.name} People Definition")
        instance = OpenStudio::Model::People.new(definition)
        instance.setName("#{space_type.name} People")
        instance.setSpaceType(space_type)
        thermal_comfort_models.each { |m| definition.pushThermalComfortModelType(m)}
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no people, one has been created.")
        instances << instance
      elsif instances.size > 1
        instances.each_with_index do |inst, i|
          next if i.zero?

          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "Removed #{inst.name} from #{space_type.name}.")
          inst.remove
        end
      end

      # Modify the definition of the instance
      space_type.people.sort.each do |inst|
        definition = inst.peopleDefinition
        unless occupancy_per_area.zero?
          definition.setPeopleperSpaceFloorArea(OpenStudio.convert(occupancy_per_area / 1000, 'people/ft^2', 'people/m^2').get)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set occupancy to #{occupancy_per_area} people/1000 ft^2.")
        end

        # set fraction radiant
        definition.setFractionRadiant(0.3)

        # Clothing schedule for thermal comfort metrics
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

        # Air velocity schedule for thermal comfort metrics
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

        # Work efficiency schedule for thermal comfort metrics
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

    return true
  end
end
