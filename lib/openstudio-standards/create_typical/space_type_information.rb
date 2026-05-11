module OpenstudioStandards
  # The CreateTypical module provides methods to create and modify an entire building energy model of a typical building
  module CreateTypical
    # @!group Space Type Information
    # Assigns information like number of units, number of beds, number of students, etc. to spaces in the model. Some methods that add exterior lighting or elevators require this information

    # Assign information like number of units, number of beds, number of students, etc. to spaces in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param assign_properties_to_spaces [Boolean] Assign properties to Space objects
    # @return [Hash] A hash of space properties
    def self.model_get_space_information(model, assign_properties_to_spaces: true)
      spaces_hash = {}

      model.getSpaces.sort.each do |space|
        space_type = space.spaceType.is_initialized ? space.spaceType.get : nil
        next if space_type.nil?

        # skip space if not part of floor area
        next unless space.partofTotalFloorArea

        standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
        standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
        next if standards_space_type.nil?

        effective_number_of_spaces = space.multiplier
        floor_area = space.floorArea * space.multiplier
        number_of_people = space.numberOfPeople * space.multiplier

        # determine number of units
        number_of_units = 0
        case standards_space_type
        when 'GuestRoom', 'GuestRm', 'GuestRmOcc', 'GuestRmUnOcc', 'GuestRoom123Occ', 'GuestRoom123Vac', 'GuestRoom4Occ', 'GuestRoom4Vac', 'PatientRoom', 'PatRoom'
          average_unit_size = OpenStudio.convert(350.0, 'ft^2', 'm^2').get
          average_unit_size = OpenStudio.convert(280.0, 'ft^2', 'm^2').get if standards_building_type == 'LargeHotel'
          number_of_units = floor_area / average_unit_size
        when 'Apartment', 'ResBedroom', 'ResLiving'
          average_unit_size = OpenStudio.convert(950.0, 'ft^2', 'm^2').get
          number_of_units = floor_area / average_unit_size
        when 'Strip mall - type 1', 'Strip mall - type 2', 'Strip mall - type 3'
          average_unit_size = OpenStudio.convert(2250.0, 'ft^2', 'm^2').get
          number_of_units = floor_area / average_unit_size
        end

        # determine number of beds
        number_of_beds = 0
        case standards_space_type
        when 'PatientRoom', 'PatRoom', 'HspSurgOutptLab', 'HspNursing', 'ICU_PatRm', 'ICU_Open'
          number_of_beds = number_of_people
        end

        # determine number of students
        number_of_students = 0
        case standards_space_type
        when 'Classroom'
          # assume 1 teacher
          number_of_students = number_of_people - 1.0
        end

        # populate space hash
        spaces_hash[space] = {}
        spaces_hash[space][:standards_building_type] = standards_building_type
        spaces_hash[space][:standards_space_type] = standards_space_type
        spaces_hash[space][:effective_number_of_spaces] = effective_number_of_spaces
        spaces_hash[space][:floor_area] = floor_area
        spaces_hash[space][:number_of_people] = number_of_people
        spaces_hash[space][:number_of_units] = number_of_units
        spaces_hash[space][:number_of_beds] = number_of_beds
        spaces_hash[space][:number_of_students] = number_of_students

        if assign_properties_to_spaces
          space.additionalProperties.setFeature('number_of_units', number_of_units)
          space.additionalProperties.setFeature('number_of_beds', number_of_beds)
          space.additionalProperties.setFeature('number_of_students', number_of_students)
        end
      end

      return spaces_hash
    end

    # Assign information like number of units, number of beds, number of students, etc. to space types in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param assign_properties_to_space_types [Boolean] Aggregate and assign properties to SpaceType objects
    # @return [Hash] A hash of space type properties
    def self.model_get_space_type_information(model, assign_properties_to_space_types: true)
      space_properties = OpenstudioStandards::CreateTypical.model_get_space_information(model, assign_properties_to_spaces: false)

      space_type_hash = {}
      model.getSpaceTypes.sort.each do |space_type|
        standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
        standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
        next if standards_space_type.nil?

        effective_number_of_spaces = 0
        floor_area = 0.0
        number_of_people = 0
        number_of_units = 0
        number_of_beds = 0
        number_of_students = 0
        space_type.spaces.sort.each do |space|
          # skip space if not part of floor area
          next unless space.partofTotalFloorArea

          effective_number_of_spaces += space_properties[space][:effective_number_of_spaces]
          floor_area += space_properties[space][:floor_area]
          number_of_people += space_properties[space][:number_of_people]
          number_of_units += space_properties[space][:number_of_units]
          number_of_beds += space_properties[space][:number_of_beds]
          number_of_students += space_properties[space][:number_of_students]
        end

        space_type_hash[space_type] = {}
        space_type_hash[space_type][:standards_building_type] = standards_building_type
        space_type_hash[space_type][:standards_space_type] = standards_space_type
        space_type_hash[space_type][:effective_number_of_spaces] = effective_number_of_spaces
        space_type_hash[space_type][:floor_area] = floor_area
        space_type_hash[space_type][:number_of_people] = number_of_people
        space_type_hash[space_type][:number_of_units] = number_of_units
        space_type_hash[space_type][:number_of_beds] = number_of_beds
        space_type_hash[space_type][:number_of_students] = number_of_students

        if assign_properties_to_space_types
          space_type.additionalProperties.setFeature('number_of_units', number_of_units)
          space_type.additionalProperties.setFeature('number_of_beds', number_of_beds)
          space_type.additionalProperties.setFeature('number_of_students', number_of_students)
        end
      end

      return space_type_hash
    end

    # Assign information like number of units, number of beds, number of students, etc. to the building object in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param assign_properties_to_building [Boolean] Aggregate and assign properties to the Building object
    # @return [Hash] A hash of building properties
    def self.model_get_building_information(model, assign_properties_to_building: true)
      space_type_properties = OpenstudioStandards::CreateTypical.model_get_space_type_information(model, assign_properties_to_space_types: false)

      building = model.getBuilding
      building_hash = {}
      building_hash[:standards_building_type] = building.standardsBuildingType.is_initialized ? building.standardsBuildingType.get : nil
      building_hash[:effective_number_of_spaces] = space_type_properties.values.sum { |v| v[:effective_number_of_spaces] || 0 }
      building_hash[:floor_area] = space_type_properties.values.sum { |v| v[:floor_area] || 0 }
      building_hash[:number_of_people] = space_type_properties.values.sum { |v| v[:number_of_people] || 0 }
      building_hash[:number_of_units] = space_type_properties.values.sum { |v| v[:number_of_units] || 0 }
      building_hash[:number_of_beds] = space_type_properties.values.sum { |v| v[:number_of_beds] || 0 }
      building_hash[:number_of_students] = space_type_properties.values.sum { |v| v[:number_of_students] || 0 }

      if assign_properties_to_building
        building.additionalProperties.setFeature('number_of_units', building_hash[:number_of_units])
        building.additionalProperties.setFeature('number_of_beds', building_hash[:number_of_beds])
        building.additionalProperties.setFeature('number_of_students', building_hash[:number_of_students])
      end

      return building_hash
    end
  end
end
