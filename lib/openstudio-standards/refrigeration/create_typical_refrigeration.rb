module OpenstudioStandards
  # The Refrigeration module provides methods to create, modify, and get information about refrigeration
  module Refrigeration
    # @!group Create Typical Refrigeration
    # Methods to add typical refrigeration

    # Adds typical refrigeration to a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param template [String] Technology or standards level, either 'old', 'new', or 'advanced'
    # @param separate_system_size_limit [Float] The area in square feet above which a refrigeration system will be split into multiple systems. Currently not used.
    # @return [Boolean] returns true if successful, false if not
    def self.create_typical_refrigeration(model,
                                          template: 'new',
                                          separate_system_size_limit: 0.0)
      # get refrigeration equipment list based on space types and area
      ref_equip_list = OpenstudioStandards::Refrigeration.typical_refrigeration_equipment_list(model)

      if ref_equip_list[:cases].empty? && ref_equip_list[:walkins].empty?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', 'The model space types do not typical have refrigeration cases or walkins. No refrigeration system will be added.')
        return true
      end

      # create cases
      medium_temperature_cases = []
      low_temperature_cases = []
      ref_equip_list[:cases].each_with_index do |ref_case, index|
        case_ = OpenstudioStandards::Refrigeration.create_case(model,
                                                               template: template,
                                                               case_type: ref_case[:case_type],
                                                               case_length: ref_case[:length],
                                                               defrost_start_hour: index,
                                                               thermal_zone: ref_case[:case_zone])
        if case_.caseOperatingTemperature > -3.0
          medium_temperature_cases << case_
        else
          low_temperature_cases << case_
        end
      end

      # create walkins
      medium_temperature_walkins = []
      low_temperature_walkins = []
      ref_equip_list[:walkins].each_with_index do |walkin, index|
        ref_walkin = OpenstudioStandards::Refrigeration.create_walkin(model,
                                                                      name: walkin[:walkin_name],
                                                                      template: template,
                                                                      walkin_type: walkin[:walkin_type],
                                                                      defrost_start_hour: index,
                                                                      thermal_zone: walkin[:walkin_zone])
        if ref_walkin.operatingTemperature > -3.0
          medium_temperature_walkins << ref_walkin
        else
          low_temperature_walkins << ref_walkin
        end
      end

      # @todo Disable self-contained refrigeration units until we have efficiency data and cases and walkins can connect to those systems and simulate correctly.
      # refrigeration_space_type_area = OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get
      # if refrigeration_space_type_area < separate_system_size_limit
      #   # each case is self-contained
      #   medium_temperature_cases.each { |ref_equip| OpenstudioStandards::Refrigeration.create_compressor_rack(model, ref_equip, template: template) }
      #   low_temperature_cases.each { |ref_equip| OpenstudioStandards::Refrigeration.create_compressor_rack(model, ref_equip, template: template) }

      #   # each walkin gets its own refrigeration system
      #   medium_temperature_walkins.each { |ref_equip| OpenstudioStandards::Refrigeration.create_refrigeration_system(model, [ref_equip], template: template, operation_type: 'MT') }
      #   low_temperature_walkins.each { |ref_equip| OpenstudioStandards::Refrigeration.create_refrigeration_system(model, [ref_equip], template: template, operation_type: 'LT') }
      # else
      medium_temperature_equip = medium_temperature_cases + medium_temperature_walkins
      OpenstudioStandards::Refrigeration.create_refrigeration_system(model, medium_temperature_equip,
                                                                     template: template,
                                                                     operation_type: 'MT')
      low_temperature_equip = low_temperature_cases + low_temperature_walkins
      OpenstudioStandards::Refrigeration.create_refrigeration_system(model, low_temperature_equip,
                                                                     template: template,
                                                                     operation_type: 'LT')
      # end

      return true
    end

    # Whether a refrigeration data row describes a standards space type.
    #
    # @param record [Hash] a refrigeration CSV row
    # @param standards_space_type [String] the space type's standardsSpaceType
    # @param standards_building_type [String, nil] the space type's standardsBuildingType
    # @param tagged_names [Array<String>] all-level names in the data table
    # @return [Boolean] true if the row applies to the space type and building type
    def self.refrigeration_record_applies?(record, standards_space_type, standards_building_type, tagged_names: [])
      return false if standards_space_type.nil?

      record_building_type = record[:standards_building_type].to_s
      record_building_type = record[:building_type].to_s if record_building_type.empty?
      return false unless record_building_type.empty? || record_building_type == standards_building_type.to_s

      names = record[:all_level_space_type].to_s.split('|').map(&:strip)
      space_type_name = standards_space_type.to_s
      return true if names.include?(space_type_name)

      return true if space_type_name.include?(' - ') &&
                     !tagged_names.include?(space_type_name) &&
                     names.include?(space_type_name.split(' - ').first)

      record[:space_type].to_s == space_type_name
    end

    # Return the best-matching refrigeration rows for a space type.
    #
    # Explicit all-level or prototype-name rows take precedence over the existing generic
    # refrigeration_space_type rows. The building type remains part of the match because a
    # shared all-level space type such as retail is refrigerated only in some buildings.
    #
    # @param records [Array<Hash>] rows from a refrigeration data table
    # @param space_type [OpenStudio::Model::SpaceType] the model space type being matched
    # @return [Array<Hash>] the matching rows, preferring explicit building-specific data
    def self.refrigeration_records_for_space_type(records, space_type)
      standards_space_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
      standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
      refrigeration_space_type = if space_type.additionalProperties.hasFeature('refrigeration_space_type')
                                   space_type.additionalProperties.getFeatureAsString('refrigeration_space_type').to_s
                                 end
      tagged_names = refrigeration_tagged_names(records)

      explicit_records = records.select do |record|
        refrigeration_record_applies?(record, standards_space_type, standards_building_type, tagged_names: tagged_names)
      end
      return explicit_records unless explicit_records.empty?

      space_type_name_is_tagged = records.any? do |record|
        names = record[:all_level_space_type].to_s.split('|').map(&:strip)
        names.include?(standards_space_type.to_s) ||
          record[:space_type].to_s == standards_space_type.to_s ||
          (standards_space_type.to_s.include?(' - ') &&
           !tagged_names.include?(standards_space_type.to_s) &&
           names.include?(standards_space_type.to_s.split(' - ').first))
      end
      return [] if space_type_name_is_tagged
      return [] if refrigeration_space_type.nil? || refrigeration_space_type.empty?

      property_records = records.select { |record| record[:refrigeration_space_type].to_s == refrigeration_space_type }
      return [] if property_records.empty?

      specific_records = property_records.select do |record|
        building_type = record[:standards_building_type].to_s
        building_type = record[:building_type].to_s if building_type.empty?
        !building_type.empty? && building_type == standards_building_type.to_s
      end
      return specific_records unless specific_records.empty?

      property_records.select do |record|
        record[:standards_building_type].to_s.empty? && record[:building_type].to_s.empty?
      end
    end

    # All all-level space type names tagged in refrigeration data.
    #
    # @param records [Array<Hash>] rows from a refrigeration data table
    # @return [Array<String>] unique tagged names
    def self.refrigeration_tagged_names(records)
      records.flat_map { |record| record[:all_level_space_type].to_s.split('|').map(&:strip) }.reject(&:empty?).uniq
    end

    # Returns the typical refrigeration equipment in a model based on space types
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Hash] Hash of refrigeration case lengths and walkin area
    def self.typical_refrigeration_equipment_list(model)
      # load refrigeration cases data
      cases_csv = "#{File.dirname(__FILE__)}/data/typical_refrigerated_cases.csv"
      unless File.file?(cases_csv)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find file: #{cases_csv}")
        return false
      end
      cases_tbl = CSV.table(cases_csv, encoding: 'ISO8859-1:utf-8')
      cases_hsh = cases_tbl.map(&:to_hash)

      # load refrigeration walkin data
      walkins_csv = "#{File.dirname(__FILE__)}/data/typical_refrigerated_walkins.csv"
      unless File.file?(walkins_csv)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find file: #{walkins_csv}")
        return false
      end
      walkins_tbl = CSV.table(walkins_csv, encoding: 'ISO8859-1:utf-8')
      walkins_hsh = walkins_tbl.map(&:to_hash)

      # loop through space types to get collection of cases and walkins
      cases_list = []
      walkins_list = []
      model.getSpaceTypes.sort.each do |space_type|
        total_space_type_floor_area_m2 = space_type.floorArea
        total_space_type_floor_area_ft2 = OpenStudio.convert(total_space_type_floor_area_m2, 'm^2', 'ft^2').get

        ref_thermal_zone = OpenstudioStandards::SpaceType.space_type_get_largest_thermal_zone(space_type)

        ref_cases = OpenstudioStandards::Refrigeration.refrigeration_records_for_space_type(cases_hsh, space_type)
        ref_walkins = OpenstudioStandards::Refrigeration.refrigeration_records_for_space_type(walkins_hsh, space_type)

        # create list of cases
        ref_cases.each do |ref_case|
          length_modifier = total_space_type_floor_area_ft2 / ref_case[:reference_space_type_area_ft2]
          case_length = OpenStudio.convert(ref_case[:length_ft] * length_modifier, 'ft', 'm').get
          cases_list << { case_type: ref_case[:case_type], length: case_length, case_zone: ref_thermal_zone }
        end

        # create list of walkins
        ref_walkins.each do |ref_walkin|
          area_modifier = total_space_type_floor_area_ft2 / ref_walkin[:reference_space_type_area_ft2]
          # round to the nearest 120 ft2, with a minimum size of 80 ft2 and maximum size of 480 ft2
          walkin_size_ft2 = (120.0 * ((ref_walkin[:size_ft2] * area_modifier) / 120.0).round).clamp(80.0, 480.0).to_int
          walkin_lookup_name = "#{ref_walkin[:walkin_type]} - #{walkin_size_ft2}SF"
          walkin_lookup_name = "#{walkin_lookup_name} with no glass door" if walkin_lookup_name.include? 'Cooler'
          walkins_list << { walkin_name: ref_walkin[:walkin_name], walkin_type: walkin_lookup_name, walkin_zone: ref_thermal_zone }
        end
      end

      equipment_list = {
        cases: cases_list,
        walkins: walkins_list
      }

      return equipment_list
    end
  end
end
