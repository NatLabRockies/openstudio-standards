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

      # Find the thermal zones most suited for holding the display cases
      unless ref_equip_list[:cases].empty?
        thermal_zone_case = OpenstudioStandards::Refrigeration.refrigeration_case_zone(model)
        if thermal_zone_case.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', 'Attempted to add display cases to the model, but could find no thermal zone to put them into.')
          return false
        end
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
                                                               thermal_zone: thermal_zone_case)
        if case_.caseOperatingTemperature > -3.0
          medium_temperature_cases << case_
        else
          low_temperature_cases << case_
        end
      end

      # Find the thermal zones most suited for holding the walkins
      unless ref_equip_list[:walkins].empty?
        thermal_zone_walkin = OpenstudioStandards::Refrigeration.refrigeration_walkin_zone(model)
        if thermal_zone_walkin.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', 'Attempted to add walkins to the model, but could find no thermal zone to put them into.')
          return false
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
                                                                      thermal_zone: thermal_zone_walkin)
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
        total_space_floor_area_m2 = space_type.floorArea
        total_space_floor_area_ft2 = OpenStudio.convert(total_space_floor_area_m2, 'm^2', 'ft^2').get

        next unless space_type.standardsSpaceType.is_initialized
        next unless space_type.standardsBuildingType.is_initialized

        standards_space_type = space_type.standardsSpaceType.get
        standards_building_type = space_type.standardsBuildingType.get

        # create list of cases
        ref_cases = cases_hsh.select { |hash| (hash[:space_type] == standards_space_type) && (hash[:building_type] == standards_building_type) }
        ref_cases.each do |ref_case|
          length_modifier = total_space_floor_area_ft2 / ref_case[:reference_space_type_area_ft2]
          case_length = OpenStudio.convert(ref_case[:length_ft] * length_modifier, 'ft', 'm').get
          cases_list << { case_type: ref_case[:case_type], length: case_length }
        end

        # create list of walkins
        ref_walkins = walkins_hsh.select { |hash| (hash[:space_type] == standards_space_type) && (hash[:building_type] == standards_building_type) }
        ref_walkins.each do |ref_walkin|
          area_modifier = total_space_floor_area_ft2 / ref_walkin[:reference_space_type_area_ft2]
          # round to the nearest 120 ft2, with a minimum size of 80 ft2 and maximum size of 480 ft2
          walkin_size_ft2 = (120.0 * ((ref_walkin[:size_ft2] * area_modifier) / 120.0).round).clamp(80.0, 480.0).to_int
          walkin_lookup_name = "#{ref_walkin[:walkin_type]} - #{walkin_size_ft2}SF"
          walkin_lookup_name = "#{walkin_lookup_name} with no glass door" if walkin_lookup_name.include? 'Cooler'
          walkins_list << { walkin_name: ref_walkin[:walkin_name], walkin_type: walkin_lookup_name }
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
