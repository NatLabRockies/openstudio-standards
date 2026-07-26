class ACM179dACM2019
  ACM_OFFICE_SPACE_TYPES_NAMES_MAP = {
    'SmallOffice' => 'WholeBuilding - Sm Office',
    'MediumOffice' => 'WholeBuilding - Md Office',
    'LargeOffice' => 'WholeBuilding - Lg Office',
  }.freeze

  def space_type_get_acm_standards_data(space_type, throw_if_not_found: false)
    standards_building_type = if space_type.standardsBuildingType.is_initialized
                                acm_building_type_for_lookup(space_type.standardsBuildingType.get, throw_if_not_found: false)
                              else
                                acm_building_type_for_lookup(model_get_primary_building_type(space_type.model, remap_office: false), throw_if_not_found: false)
                              end
    return acm_lookup_failure([], throw_if_not_found) if standards_building_type.nil?

    criteria = []
    if space_type.standardsSpaceType.is_initialized
      acm_space_type_candidates(standards_building_type, space_type.standardsSpaceType.get).each do |space_type_name|
        criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
      end
    end
    acm_space_type_candidates(standards_building_type, whole_building_space_type_name(space_type.model, standards_building_type)).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    acm_space_type_candidates(standards_building_type, space_type.nameString).each do |space_type_name|
      criteria << acm_space_type_search_criteria(standards_building_type, space_type_name)
    end
    criteria << acm_space_type_search_criteria(standards_building_type, '- undefined -')

    acm_find_space_type_properties(criteria.uniq, throw_if_not_found:)
  end

  def space_type_get_standards_data(space_type, throw_if_not_found: false)
    space_type_get_acm_standards_data(space_type, throw_if_not_found:)
  end

  def whole_building_space_type_name(model, building_type)
    return 'WholeBuilding' unless ['Office', 'SmallOffice', 'MediumOffice', 'LargeOffice'].include?(building_type)

    ACM_OFFICE_SPACE_TYPES_NAMES_MAP[model_remap_office(model, model.getBuilding.floorArea)]
  end

  def acm_space_type_search_criteria(building_type, space_type)
    {
      'template' => template,
      'building_type' => building_type,
      'space_type' => space_type,
    }
  end

  def acm_space_type_candidates(building_type, space_type)
    candidates = [space_type]
    candidates << space_type.delete_prefix("#{building_type} ")
    candidates.concat(candidates.map { |name| name.sub(/\s+-\s+90\.1(?:-PRM)?-2019\z/, '') })
    PROTOTYPE_TO_PRM_LPD_SPACE_TYPE.each do |prototype_space_type, prm_space_type|
      candidates << prototype_space_type if prm_space_type == space_type
    end
    candidates << PRM_WHOLE_BUILDING_ACM_SPACE_TYPE[space_type]
    candidates << ACM_WHOLE_BUILDING_SPACE_TYPE_FALLBACK[building_type] if space_type == 'WholeBuilding'
    candidates.compact.uniq
  end

  def acm_find_space_type_properties(criteria, throw_if_not_found: false, log_failure: true)
    criteria.each do |search_criteria|
      row = model_find_object(standards_data['space_types'] || [], search_criteria)
      unless row.nil?
        OpenStudio.logFree(OpenStudio::Debug, '179d.acm.SpaceType', "ACM space type lookup succeeded: #{search_criteria}.")
        return row
      end
    end

    return {} unless log_failure || throw_if_not_found

    acm_lookup_failure(criteria, throw_if_not_found)
  end

  def acm_lookup_failure(criteria, throw_if_not_found)
    msg = "179D ACM space type properties lookup failed: #{criteria}."
    if throw_if_not_found
      OpenStudio.logFree(OpenStudio::Error, '179d.acm.SpaceType', msg)
      raise msg
    end

    OpenStudio.logFree(OpenStudio::Warn, '179d.acm.SpaceType', msg)
    {}
  end
end
