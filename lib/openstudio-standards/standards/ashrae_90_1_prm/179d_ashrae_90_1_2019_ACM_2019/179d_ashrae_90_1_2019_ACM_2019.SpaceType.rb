class ACM179dASHRAE901PRM2019
  OFFICE_SPACE_TYPES_NAMES_MAP = {
    'SmallOffice' => 'WholeBuilding - Sm Office',
    'MediumOffice' => 'WholeBuilding - Md Office',
    'LargeOffice' => 'WholeBuilding - Lg Office'
  }.freeze

  def whole_building_space_type_name(model, primary_building_type)
    unless ['Office', 'SmallOffice', 'MediumOffice', 'LargeOffice'].include?(primary_building_type)
      return 'WholeBuilding'
    end

    granular_building_type = model_remap_office(model, model.getBuilding.floorArea)
    return OFFICE_SPACE_TYPES_NAMES_MAP[granular_building_type]
  end

  def space_type_get_standards_data(space_type, throw_if_not_found: false)
    standards_building_type = if space_type.standardsBuildingType.is_initialized
                                model_get_lookup_name(space_type.standardsBuildingType.get)
                              else
                                model_get_primary_building_type(space_type.model, remap_office: false)
                              end
    standards_space_type = if space_type.standardsSpaceType.is_initialized
                             space_type.standardsSpaceType.get
                           end

    search_criteria_list = []
    unless standards_space_type.nil?
      search_criteria_list << {
        'template' => template,
        'building_type' => standards_building_type,
        'space_type' => standards_space_type
      }
    end
    search_criteria_list << {
      'template' => template,
      'building_type' => standards_building_type,
      'space_type' => whole_building_space_type_name(space_type.model, standards_building_type)
    }
    search_criteria_list << {
      'template' => template,
      'building_type' => standards_building_type,
      'space_type' => '- undefined -'
    }

    found_search_criteria = nil
    space_type_properties = nil
    search_criteria_list.uniq.each do |search_criteria|
      space_type_properties = model_find_object(standards_data['space_types'], search_criteria)
      unless space_type_properties.nil?
        found_search_criteria = search_criteria
        break
      end
    end

    if space_type_properties.nil?
      msg = "Space type properties lookup failed: #{search_criteria_list.uniq}."
      if throw_if_not_found
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SpaceType', msg)
        raise msg
      end
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.SpaceType', msg)
      space_type_properties = {}
    else
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.SpaceType', "Space type properties lookup succeeded: #{found_search_criteria}.")
    end

    return space_type_properties
  end

  def set_lpd_on_space_type(space_type, _user_spaces, _user_spacetypes)
    space_type_properties = space_type_get_standards_data(space_type)
    return false if space_type_properties.empty?

    lighting_per_area = space_type_properties['lighting_per_area'].to_f
    return false if lighting_per_area.zero?

    unless space_type.hasAdditionalProperties && space_type.additionalProperties.hasFeature('regulated_lights_name')
      return false
    end

    lights_name = space_type.additionalProperties.getFeatureAsString('regulated_lights_name').to_s
    lights_option = space_type.model.getLightsByName(lights_name)
    return false unless lights_option.is_initialized

    lights = lights_option.get
    lights_definition = lights.lightsDefinition
    lights.setFractionReplaceable(space_type_properties['lighting_fraction_replaceable'].to_f) unless space_type_properties['lighting_fraction_replaceable'].nil?
    lights_definition.setWattsperSpaceFloorArea(OpenStudio.convert(lighting_per_area, 'W/ft^2', 'W/m^2').get)
    lights_definition.setReturnAirFraction(space_type_properties['lighting_fraction_to_return_air'].to_f) unless space_type_properties['lighting_fraction_to_return_air'].nil?
    lights_definition.setFractionRadiant(space_type_properties['lighting_fraction_radiant'].to_f) unless space_type_properties['lighting_fraction_radiant'].nil?
    lights_definition.setFractionVisible(space_type_properties['lighting_fraction_visible'].to_f) unless space_type_properties['lighting_fraction_visible'].nil?

    lighting_schedule_name = space_type_properties['lighting_schedule']
    unless lighting_schedule_name.nil?
      lights.setSchedule(model_add_schedule(space_type.model, lighting_schedule_name))
    end

    OpenStudio.logFree(OpenStudio::Info, 'prm.log', "Setting lighting object #{lights.name.get} lighting per area to #{lighting_per_area} W/ft^2 for 179D 2019.")
    return true
  end

  def space_type_light_sch_change(_model)
    OpenStudio.logFree(OpenStudio::Info, 'prm.log', 'Skipping PRM lighting schedule adjustment for 179D 2019 because ACM schedules are fixed.')
    return true
  end
end
