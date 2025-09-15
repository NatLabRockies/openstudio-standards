class ACM179dASHRAE9012007
  # @!group PlanarSurface

  # If construction properties can be found based on the template,
  # the standards intended surface type, the standards construction type,
  # the climate zone, and the occupancy type,
  # create a construction that meets those properties and assign it to this surface.
  # 179D 90.1-2007
  #
  # @param planar_surface [OpenStudio::Model:PlanarSurface] surface object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param previous_construction_map [Hash] a hash where the keys are an array of inputs
  #   [template, climate_zone, intended_surface_type, standards_construction_type, occ_type]
  #   and the values are the constructions.  If supplied, constructions will be pulled
  #   from this hash if already created to avoid creating duplicate constructions.
  # @return [Hash] returns a hash where the key is an array of inputs
  #   [template, climate_zone, intended_surface_type, standards_construction_type, occ_type]
  #   and the value is the newly created construction.
  #   This can be used to avoid creating duplicate constructions.
  # @todo Align the standard construction enumerations in the
  # spreadsheet with the enumerations in OpenStudio (follow CBECC-Com).
  def planar_surface_apply_standard_construction(planar_surface, climate_zone, previous_construction_map = {}, wwr_building_type = nil, wwr_info = {}, surface_category)
    # Skip surfaces not in a space
    return previous_construction_map if planar_surface.space.empty?

    space = planar_surface.space.get
    if surface_category == 'ExteriorSubSurface'
      surface_type = planar_surface.subSurfaceType
    else
      surface_type = planar_surface.surfaceType
    end

    # Skip surfaces that don't have a construction
    # return previous_construction_map if planar_surface.construction.empty?
    if !planar_surface.construction.empty?
      construction = planar_surface.construction.get
    else
      # Get appropriate default construction if not defined inside surface object
      construction = nil
      space_type = space.spaceType.get
      if space.defaultConstructionSet.is_initialized
        cons_set = space.defaultConstructionSet.get
        construction = get_default_surface_cons_from_surface_type(surface_category, surface_type, cons_set)
      end
      if construction.nil? && space_type.defaultConstructionSet.is_initialized
        cons_set = space_type.defaultConstructionSet.get
        construction = get_default_surface_cons_from_surface_type(surface_category, surface_type, cons_set)
      end
      if construction.nil? && space.buildingStory.get.defaultConstructionSet.is_initialized
        cons_set = space.buildingStory.get.defaultConstructionSet.get
        construction = get_default_surface_cons_from_surface_type(surface_category, surface_type, cons_set)
      end
      if construction.nil? && space.model.building.get.defaultConstructionSet.is_initialized
        cons_set = space.model.building.get.defaultConstructionSet.get
        construction = get_default_surface_cons_from_surface_type(surface_category, surface_type, cons_set)
      end

      return previous_construction_map if construction.nil?
    end

    # Determine if residential or nonresidential
    # based on the space type.
    occ_type = 'Nonresidential'
    if space_residential?(space)
      occ_type = 'Residential'
    end

    # Get the climate zone set
    climate_zone_set = model_find_climate_zone_set(planar_surface.model, climate_zone)

    # Get the intended surface type
    standards_info = construction.standardsInformation
    surf_type = standards_info.intendedSurfaceType

    if surf_type.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "Could not determine the intended surface type for #{planar_surface.name} from #{construction.name}.  This surface will not have the standard applied.")
      return previous_construction_map
    end
    surf_type = surf_type.get

    # Get the standards type, which is based on different fields
    # if is intended for a window, a skylight, or something else.
    # Mapping is between standards-defined enumerations and the
    # enumerations available in OpenStudio.
    stds_type = nil
    # Windows and Glass Doors
    if surf_type == 'ExteriorWindow' || surf_type == 'GlassDoor'
      stds_type = standards_info.fenestrationFrameType
      if stds_type.is_initialized
        stds_type = stds_type.get
        if !wwr_building_type.nil?
          stds_type = 'Any Vertical Glazing'
        end
        case stds_type
        when 'Metal Framing', 'Metal Framing with Thermal Break'
          stds_type = 'Metal framing (all other)'
        when 'Non-Metal Framing'
          stds_type = 'Nonmetal framing (all)'
        when 'Any Vertical Glazing'
          stds_type = 'Any Vertical Glazing'
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "The standards fenestration frame type #{stds_type} cannot be used on #{surf_type} in #{planar_surface.name}.  This surface will not have the standard applied.")
          return previous_construction_map
        end
      else
        if !wwr_building_type.nil?
          stds_type = 'Any Vertical Glazing'
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "Could not determine the standards fenestration frame type for #{planar_surface.name} from #{construction.name}.  This surface will not have the standard applied.")
          return previous_construction_map
        end
      end
    # Skylights
    elsif surf_type == 'Skylight'
      stds_type = standards_info.fenestrationType
      if stds_type.is_initialized
        stds_type = stds_type.get
        case stds_type
        when 'Glass Skylight with Curb'
          stds_type = 'Glass with Curb'
        when 'Plastic Skylight with Curb'
          stds_type = 'Plastic with Curb'
        when 'Plastic Skylight without Curb', 'Glass Skylight without Curb'
          stds_type = 'Without Curb'
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "The standards fenestration type #{stds_type} cannot be used on #{surf_type} in #{planar_surface.name}.  This surface will not have the standard applied.")
          return previous_construction_map
        end
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "Could not determine the standards fenestration type for #{planar_surface.name} from #{construction.name}.  This surface will not have the standard applied.")
        return previous_construction_map
      end
    # Exterior Doors
    elsif surf_type == 'ExteriorDoor'
      stds_type = standards_info.standardsConstructionType
      if stds_type.is_initialized
        stds_type = stds_type.get
        case stds_type
        when 'RollUp', 'Rollup', 'NonSwinging', 'Nonswinging'
          stds_type = 'NonSwinging'
        else
          stds_type = 'Swinging'
        end
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "Could not determine the standards construction type for exterior door #{planar_surface.name}.  This door will not have the standard applied.")
        return previous_construction_map
      end
    # All other surface types
    else
      stds_type = standards_info.standardsConstructionType
      if stds_type.is_initialized
        stds_type = stds_type.get
      else
        if planar_surface.outsideBoundaryCondition == 'Surface' && surface_category == 'NA'
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlanarSurface', "Standards construction is not needed and not applied for interior wall: #{planar_surface.name}.")
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "Could not determine the standards construction type for #{planar_surface.name}.  This surface will not have the standard applied.")
        end
        return previous_construction_map
      end
    end

    # Check if the construction type was already created.
    # If yes, use that construction.  If no, make a new one.

    # for multi-building type - search for the surface wwr type
    surface_std_wwr_type = wwr_building_type
    new_construction = nil
    type = [template, climate_zone, surf_type, stds_type, occ_type]
    # Only apply the surface_std_wwr_type update when wwr_building_type has Truthy values
    if !wwr_building_type.nil? && (surf_type == 'ExteriorWindow' || surf_type == 'GlassDoor')
      space = planar_surface.space.get
      if space.hasAdditionalProperties && space.additionalProperties.hasFeature('building_type_for_wwr')
        surface_std_wwr_type = space.additionalProperties.getFeatureAsString('building_type_for_wwr').get
      end
      type.push(surface_std_wwr_type)
    end

    if previous_construction_map[type] && !previous_construction_map[type].iddObjectType.valueName.to_s.include?('factorGround')
      new_construction = previous_construction_map[type]
    else
      new_construction = model_find_and_add_construction(planar_surface.model,
                                                         climate_zone_set,
                                                         surf_type,
                                                         stds_type,
                                                         occ_type,
                                                         wwr_building_type: surface_std_wwr_type,
                                                         wwr_info: wwr_info,
                                                         surface: planar_surface)
      if !new_construction == false
        previous_construction_map[type] = new_construction
      end
    end

    # Assign the new construction to the surface
    if new_construction
      planar_surface.setConstruction(new_construction)
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.PlanarSurface', "Set the construction for #{planar_surface.name} to #{new_construction.name}.")
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlanarSurface', "Could not generate a standard construction for #{planar_surface.name}.")
      return previous_construction_map
    end

    return previous_construction_map
  end
end
