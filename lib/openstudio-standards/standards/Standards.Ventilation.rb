class Standard
  # @!group Ventilation

  # Apply ventilation from standards data to a space type
  # Create a DesignSpecificationOutdoorAir air object and assign it to the SpaceType
  #
  # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object to apply ventilation to
  # @return [Boolean] returns true if successful, false if not
  def space_type_apply_ventilation(space_type)
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

    # Ventilation
    ventilation_have_info = false
    ventilation_per_area = space_type_properties['ventilation_per_area'].to_f
    ventilation_per_person = space_type_properties['ventilation_per_person'].to_f
    ventilation_ach = space_type_properties['ventilation_air_changes'].to_f
    ventilation_have_info = true unless ventilation_per_area.zero?
    ventilation_have_info = true unless ventilation_per_person.zero?
    ventilation_have_info = true unless ventilation_ach.zero?

    # Get the design OA or create a new one if none exists
    ventilation = space_type.designSpecificationOutdoorAir
    if ventilation.is_initialized
      ventilation = ventilation.get
    else
      ventilation = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space_type.model)
      ventilation.setName("#{space_type.name} Ventilation")
      space_type.setDesignSpecificationOutdoorAir(ventilation)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} had no ventilation specification, one has been created.")
    end

    if ventilation_have_info
      # Modify the ventilation properties
      ventilation_method = model_ventilation_method(space_type.model)
      ventilation.setOutdoorAirMethod(ventilation_method)
      unless ventilation_per_area.zero?
        ventilation.setOutdoorAirFlowperFloorArea(OpenStudio.convert(ventilation_per_area.to_f, 'ft^3/min*ft^2', 'm^3/s*m^2').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation per area to #{ventilation_per_area} cfm/ft^2.")
      end
      unless ventilation_per_person.zero?
        ventilation.setOutdoorAirFlowperPerson(OpenStudio.convert(ventilation_per_person.to_f, 'ft^3/min*person', 'm^3/s*person').get)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation per person to #{ventilation_per_person} cfm/person.")
      end
      unless ventilation_ach.zero?
        ventilation.setOutdoorAirFlowAirChangesperHour(ventilation_ach)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SpaceType', "#{space_type.name} set ventilation to #{ventilation_ach} ACH.")
      end
    elsif !ventilation_have_info
      # All space types must have a design spec OA object for ventilation controls to work correctly, even if the values are all zero.
      ventilation.setOutdoorAirFlowperFloorArea(0)
      ventilation.setOutdoorAirFlowperPerson(0)
      ventilation.setOutdoorAirFlowAirChangesperHour(0)
    end

    return true
  end
end
