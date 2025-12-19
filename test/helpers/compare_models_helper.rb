# Compare two osm files and find differences.
# Assumes that objects with the same name in each file should
# be identical.  Cannot use handles for comparison because handles
# change for auto-generated models.
#
# @param model_true [OpenStudio::Model::Model] the "true" model
# @param model_compare [OpenStudio::Model::Model] the model to be
# compared to the "true" model
# @param look_for_renamed_objects [Boolean] if true, objects that have no match based
# on name alone will be compared with all objects of the same type on a field-by-field basis.
# This finds objects that have been renamed but are otherwise
# identical between models, but significantly slows down the comparison.
# @return [Array<String>] a list of differences between the two models
def compare_osm_files(model_true, model_compare, look_for_renamed_objects = false)

  only_model_true = [] # objects only found in the true model
  only_model_compare = [] # objects only found in the compare model
  both_models = [] # objects found in both models
  renamed_object_aliases = Hash.new([]) # Hash of renamed objects
  diffs = [] # differences between the two models

  # Define types of objects to skip entirely during the comparison
  object_types_to_skip = [
    'OS:EnergyManagementSystem:Sensor', # Names are UIDs
    'OS:EnergyManagementSystem:Program', # Names are UIDs
    'OS:EnergyManagementSystem:Actuator', # Names are UIDs
    'OS:EnergyManagementSystem:OutputVariable', # getString() returns UIDs instead of variable name
    'OS:Connection', # Names are UIDs
    'OS:PortList', # Names are UIDs
    'OS:Building', # Name includes timestamp of creation
    'OS:ModelObjectList', # Names are UIDs
    'OS:ZoneHVAC:EquipmentList', # Names appear to be created non-deterministically
    'OS:AvailabilityManagerAssignmentList', # Names appear to be created non-deterministically
    'OS:Schedule:Rule', # Names appear to be created non-deterministically
    'OS:ScheduleTypeLimits', # Names appear to be created non-deterministically
    'OS:Rendering:Color', # Rendering colors don't matter
    'OS:Output:Meter', # Output meter objects may be different and don't affect results
    'OS:ProgramControl', # Deprecated object no longer translated to EnergyPlus
    'OS:StandardsInformation:Material',
    'OS:StandardsInformation:Construction',
    'OS:SimulationControl', # Sizing run and weather run may be different
    'OS:AdditionalProperties', # Does not impact simulation results
    'OS:Output:Variable', # Does not impact simulation results
    'OS:Table:Lookup' # ERV table independent variable name lists are not deterministic
  ]

  # Fill model object lists with all object types to be compared
  model_true.getModelObjects.sort.each do |obj|
    next if object_types_to_skip.include?(obj.iddObject.name) # Skip comparison of certain object types
    only_model_true << obj
  end

  model_compare.getModelObjects.sort.each do |obj|
    next if object_types_to_skip.include?(obj.iddObject.name) # Skip comparison of certain object types
    only_model_compare << obj
  end

  # diffs << "before name match only_model_true = #{only_model_true.size}"
  # diffs << "before name match only_model_compare = #{only_model_compare.size}"
  # diffs << "before name match both_models = #{both_models.uniq.size}"

  # Match up the objects
  only_model_true, only_model_compare, both_models, renamed_object_aliases, diffs = match_objects!(model_true,
                                                                                                   model_compare,
                                                                                                   only_model_true,
                                                                                                   only_model_compare,
                                                                                                   both_models,
                                                                                                   renamed_object_aliases,
                                                                                                   diffs,
                                                                                                   object_types_to_skip,
                                                                                                   look_for_renamed_objects)
  # require 'json'
  # diffs << "renamed"
  # diffs << JSON.pretty_generate(renamed_object_aliases)
  #
  # diffs << "after name match only_model_true = #{only_model_true.size}"
  # diffs << "after name match only_model_compare = #{only_model_compare.size}"
  # diffs << "after name match both_models = #{both_models.uniq.size}"

  # Report a diff for each object found in only the true model
  if only_model_true.size > 0
    only_model_true.each do |true_object|
      diffs << "A #{true_object.iddObject.name} called '#{object_name(true_object)}' only found in true model"
    end
  end

  # Report a diff for each object found in only the compare model
  if only_model_true.size > 0
    only_model_compare.each do |compare_object|
      diffs << "A #{compare_object.iddObject.name} called '#{object_name(compare_object)}' only found in compare model"
    end
  end

  # Compare objects found in both models field by field
  both_models.uniq.each do |b|
    true_object = b[0]
    compare_object = b[1]
    obj_diffs = compare_objects_field_by_field(true_object, compare_object, renamed_object_aliases)
    obj_diffs.each do |obj_diff|
      msg = "For #{true_object.iddObject.name} called '#{object_name(true_object)}'"
      msg += "  'Name': true model = #{object_name(true_object)}, compare model = '#{object_name(compare_object)}'" unless object_name(true_object) == object_name(compare_object)
      msg += obj_diff
      diffs << msg
    end
  end

  return diffs.sort
end

# Gets the "Name" of the object.  For objects with a Name field,
# it returns that value.  For other objects, it returns a customized value
# depending on the object type
def object_name(object)
  # For objects with a name, return the name
  return object.name.get.to_s if object.iddObject.hasNameField

  object_type = object.iddObject.name
  case object_type
  when 'OS:ClimateZones',
       'OS:ConvergenceLimits',
       'OS:Facility',
       'OS:HeatBalanceAlgorithm',
       'OS:LifeCycleCost:Parameters',
       'OS:OutputControl:ReportingTolerances',
       'OS:ProgramControl',
       'OS:RadianceParameters',
       'OS:RunPeriodControl:DaylightSavingTime',
       'OS:ShadowCalculation',
       'OS:SimulationControl',
       'OS:Site:GroundTemperature:BuildingSurface',
       'OS:Site:GroundTemperature:FCfactorMethod',
       'OS:Site:WaterMainsTemperature',
       'OS:Sizing:Parameters',
       'OS:SurfaceConvectionAlgorithm:Inside',
       'OS:SurfaceConvectionAlgorithm:Outside',
       'OS:Timestep',
       'OS:WeatherFile',
       'OS:YearDescription',
       'OS:ZoneAirContaminantBalance',
       'OS:ZoneAirHeatBalanceAlgorithm',
       'OS:ZoneCapacitanceMultiplier:ResearchSpecial'
    # Objects that are unique (1 per model)
    name = object_type
  when 'OS:Sizing:Zone', 'OS:Sizing:Plant', 'OS:Sizing:System', 'OS:StandardsInformation:Construction', 'OS:WaterHeater:Sizing'
    # Objects referencing a parent in the first field
    parent = object.getTarget(1).get
    name = "#{object_type} #{parent.name.get.to_s}"
  else
    name = "#{object.iddObject.name}"
    puts "ERROR - no name defined for #{object.iddObject.name}"
  end

  return name
end

# Finds object by compare_name if object does not have name field
def get_unnamed_object_by_compare_name(model_compare, object)
  get_objects_method = "get#{object.iddObject.name.gsub('OS:','').gsub(':','')}s"
  if model_compare.respond_to?(get_objects_method)
    model_compare.send(get_objects_method).each do |compare_object|
      if object_name(compare_object) == object_name(object)
        return compare_object
      end
     end
  end
  return nil
end

# Returns an array of differences between two objects, on a field-by-field
# basis, excluding certain fields populated by UIDs or non-deterministic names
# generated by OpenStudio.
#
# @param true_object [OpenStudio::Model::ModelObject] the object that will be considered truth
# @param compare_object [OpenStudio::Model::ModelObject] the object that will be compared to the truth
# @param alias_hash [Hash] a hash that maps the name of an object in the true model
# to an array of corresponding objects that have been renamed but are otherwise identical in the
# compare model.
def compare_objects_field_by_field(true_object, compare_object, alias_hash = Hash.new([]))

  idd_object = true_object.iddObject

  true_object_num_fields = true_object.numFields
  compare_object_num_fields = compare_object.numFields

  # loop over fields skipping handle
  diffs = []
  (1...[true_object_num_fields, compare_object_num_fields].max).each do |i|

    field_name = idd_object.getField(i).get.name

    # Don't compare the name field because this is how
    # the objects were deemed to be the same in both files
    next if field_name == 'Name'

    # Don't compare fields populated with IDs
    next if field_name.include?('Node Name')
    next if field_name.include?('Branch Name')
    next if field_name.include?('Inlet Port')
    next if field_name.include?('Outlet Port')
    next if field_name.include?('Inlet Node')
    next if field_name.include?('Outlet Node')
    next if field_name.include?('Setpoint Node or NodeList Name')
    next if field_name.include?('Port List')
    next if field_name.include?('Cooling Control Zone or Zone List Name')
    next if field_name.include?('Heating Control Zone or Zone List Name')
    next if field_name.include?('Heating Zone Fans Only Zone or Zone List Name')

    # Don't compare fields populated by auto-generated names
    next if field_name.include?('Availability Manager List Name')
    next if field_name.include?('Control Zone or Zone List Name')
    next if field_name.include?('Thermostat Name')

    # Don't compare fields populated by auto-created objects
    next if field_name.include?('Demand Mixer Name')
    next if field_name.include?('Demand Splitter Name')
    next if field_name.include?('Demand Splitter A Name')
    next if field_name.include?('Demand Splitter B Name')
    next if field_name.include?('Supply Mixer Name')
    next if field_name.include?('Supply Splitter Name')

    # Don't compare names of schedules used by water use equipment and water use connections
    next if field_name.include?('Target Temperature Schedule Name')
    next if field_name.include?('Sensible Fraction Schedule Name')
    next if field_name.include?('Latent Fraction Schedule Name')
    next if field_name.include?('Water Use Equipment Name')

    # Don't compare field added in OS 3.2 release (temporary)
    # checking this field in older versions will require different regression models by version
    next if field_name.include?('Drain Water Heat Exchanger Type')
    next if field_name.include?('Drain Water Heat Exchanger Destination')

    # Don't compare the names of schedule type limits
    # because they appear to be created non-deteministically
    next if field_name.include?('Schedule Type Limits Name')

    # Fields that don't matter
    next if field_name.include?('Group Rendering Name')
    next if field_name.include?('Url') # Location EPW file is stored on disk

    # Don't compare curve names (temporarily, for PNNL merge)
    next if field_name.include?('Curve Name')

    # Get the value from the true object
    true_value = ""
    if i < true_object_num_fields
      true_value = true_object.getString(i).to_s.downcase
    end
    true_value = " - " if true_value.empty?

    # Get the same value from the compare object
    compare_value = ""
    if i < true_object_num_fields
      compare_value = compare_object.getString(i).to_s.downcase
    end
    compare_value = " - " if compare_value.empty?

    # Round long numeric fields
    true_value = '0.0' if true_value == '0'
    compare_value = '0.0' if compare_value == '0'
    true_value = true_value.to_f.round(5) unless true_value.to_f.zero?
    compare_value = compare_value.to_f.round(5) unless compare_value.to_f.zero?

    # Check true value directly against compare value
    next if compare_value == true_value

    # Check numeric values if numeric
    if (compare_value.is_a? Numeric) && (true_value.is_a? Numeric)
      diff = true_value.to_f - compare_value.to_f
      unless true_value.zero?
        # next if absolute value is less than a tenth of a percent difference
        next if (diff / true_value.to_f).abs < 0.001
      end
    end

    # Check true value to aliases from compare model
    renamed_in_true = alias_hash[true_value].uniq
    if renamed_in_true.map(&:downcase).include?(compare_value)
      # puts "found equality for '#{compare_value}' in [#{renamed_in_true.join(', ')}]"
      next
    end

    # Check compare value to aliases from true model
    renamed_in_compare = alias_hash[compare_value].uniq
    if renamed_in_compare.map(&:downcase).include?(true_value)
      # puts "found equality for '#{compare_value}' in [#{renamed_in_compare.join(', ')}]"
      next
    end

    # Report the difference
    diffs << "  '#{field_name}': true model = '#{true_value}', compare model = '#{compare_value}'"
    # diffs << "For #{true_object.iddObject.name} called '#{object_name(true_object)}' field '#{field_name}': true model = #{true_value}, compare model = #{compare_value}"
  end

  return diffs
end

# Finds objects in the supplied model that match the supplied object
# on a field-by-field basis, excluding the handle, name, fields populated by UIDs, etc.
#
# @return [Array<OpenStudio::WorkSpaceObject>] an array of matching objects
def find_object_matches_field_by_field(true_object, compare_model, alias_hash = Hash.new([]))
  matching_objects = []
  # Check against each of the objects in the compare model
  compare_model.getModelObjects.sort.each do |compare_object|
    # Skip objects of different types
    next unless compare_object.iddObject.name == true_object.iddObject.name
    # Compare field by field
    obj_diffs = compare_objects_field_by_field(true_object, compare_object, alias_hash)
    # If there are no differences, this is an obvious match
    if obj_diffs.empty?
      matching_objects << compare_object
      # puts "renamed: #{object_name(true_object)} matches #{object_name(compare_object)}"
      next
    end
    # Give large non-resource objects some fuzzy matching.
    # If an object has more than 10 fields, if 80% of the fields
    # match, perhaps these are the same objects but they have differences beyond the name.
    # next if true_object.to_ResourceObject.is_initialized # Skip ResourceObjects like curves, schedules, etc.
    # num_fields = [true_object.numFields, compare_object.numFields].max
    # if num_fields > 10 && obj_diffs.size/num_fields < 0.2
    #   matching_objects << compare_object
    #   puts "renamed: #{object_name(true_object)} fuzzy matches #{object_name(compare_object)}"
    # end
  end

  return matching_objects
end

# Check all objects that didn't have a matching name
# against all unmatched objects of the same type in the other file.
# If all fields except for the name match, assume these are actually the same object with a different name
# and add them to the array to be compared
# This method is recursive because after it finds that some objects have been renamed, it needs to re-compare
# all remaining unmatched objects because they might have been unmatched due to having fields
# referencing renamed object names be different.
# @param look_for_renamed_objects [Boolean] if true, objects that have no match based
# on name alone will be compared with all objects of the same type in the model_compare
# on a field-by-field basis.  This finds objects that have been renamed but are otherwise
# identical between models, but has a significant speed penalty.
def match_objects!(model_true, model_compare, unmatched_true_objects, unmatched_compare_objects, object_pairs, renamed_object_aliases, diffs, object_types_to_skip, look_for_renamed_objects = false)
  # puts "running match_objects!"
  # Determine the number of renamed objects before matching
  num_renamed_objects_before = renamed_object_aliases.size

  # Find objects in the true model only or in both models
  model_true.getModelObjects.sort.each do |true_object|
    next if object_types_to_skip.include?(true_object.iddObject.name) # Skip comparison of certain object types

    # Start by looking for unique model objects
    get_unique_object_method = "get#{true_object.iddObject.name.gsub('OS:','').gsub(':','')}"
    # Methods for SurfaceConvectionAlgorithms don't match convention
    get_unique_object_method = 'getInsideSurfaceConvectionAlgorithm' if get_unique_object_method == 'getSurfaceConvectionAlgorithmInside'
    get_unique_object_method = 'getOutsideSurfaceConvectionAlgorithm' if get_unique_object_method == 'getSurfaceConvectionAlgorithmOutside'
    if model_compare.respond_to?(get_unique_object_method) && model_compare.method(get_unique_object_method).arity.zero?
      compare_object = model_compare.send(get_unique_object_method)
      object_pairs << [true_object, compare_object]
      # puts "compare '#{object_name(compare_object)}' matches true '#{object_name(true_object)}'"
      next
    end

    # Look for non-unique model objects without a name
    unless true_object.iddObject.hasNameField
      # get objects with no name
      compare_object = get_unnamed_object_by_compare_name(model_compare, true_object)
      unless compare_object.nil?
        object_pairs << [true_object, compare_object]
        # puts "compare '#{object_name(compare_object)}' matches true '#{object_name(true_object)}'"
        next
      end
    end

    # Next, look for an object with the same name
    compare_workspace_object = model_compare.getObjectByTypeAndName(true_object.iddObject.type, object_name(true_object))
    if compare_workspace_object.is_initialized
      compare_object = model_compare.getModelObject(compare_workspace_object.get.handle).get
      object_pairs << [true_object, compare_object]
      # puts "compare '#{object_name(compare_object)}' matches true '#{object_name(true_object)}'"
      next
    end

    # If not found by name, try to find based on field-by-field comparison
    if look_for_renamed_objects
      matching_compare_objects = find_object_matches_field_by_field(true_object, model_compare, renamed_object_aliases)
      if matching_compare_objects.size > 0
        matching_compare_objects.each do |matching_compare_object|
          object_pairs << [true_object, matching_compare_object]
          # puts "compare '#{object_name(matching_compare_object)}' renamed matches true '#{object_name(true_object)}'"
          renamed_object_aliases[object_name(matching_compare_object)] += [object_name(true_object)] # Record the alias
        end
        next
      end
    end
  end

  # If no objects were renamed, remove all objects found in a pair from the unmatched true/compare object arrays,
  # otherwise call recursively.
  num_renamed_objects_after = renamed_object_aliases.size
  if num_renamed_objects_before == num_renamed_objects_after
    object_pairs.uniq.each do |pair|
      true_obj = pair[0]
      compare_obj = pair[1]
      # diffs << "#{true_obj.class}, #{compare_obj.class}"
      unmatched_true_objects.delete(true_obj)
      unmatched_compare_objects.delete(compare_obj)
    end

    # puts "final renamed_object_aliases"
    # puts renamed_object_aliases

    return [unmatched_true_objects,
            unmatched_compare_objects,
            object_pairs,
            renamed_object_aliases,
            diffs]
  else
    match_objects!(model_true,
                   model_compare,
                   unmatched_true_objects,
                   unmatched_compare_objects,
                   object_pairs,
                   renamed_object_aliases,
                   diffs,
                   object_types_to_skip,
                   look_for_renamed_objects)
  end

end
