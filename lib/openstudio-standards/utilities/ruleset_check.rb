module OpenStudioStandards
  module RulesetChecking
    # building type hash map
    BUILDING_MAP = {
      'All others' => {
        'lighting' => 'OFFICE_OPEN_PLAN',
        'ventilation' => 'OFFICE_BUILDINGS_OFFICE_SPACE',
        'shw' => 'ALL_OTHERS'
      },
      'Grocery store' => {
        'lighting' => 'SALES_AREA',
        'ventilation' => 'RETAIL_SUPERMARKET',
        'shw' => 'ALL_OTHERS'
      },
      'Healthcare (outpatient)' => {
        'lighting' => 'HEALTHCARE_FACILITY_PATIENT_ROOM',
        'ventilation' => 'OUTPATIENT_HEALTH_CARE_FACILITIES_URGENT_CARE_EXAMINATION_ROOM',
        'shw' => 'HEALTH_CARE_CLINIC'
      },
      'Hospital' => {
        'lighting' => 'HEALTHCARE_FACILITY_PATIENT_ROOM',
        'ventilation' => 'OUTPATIENT_HEALTH_CARE_FACILITIES_GENERAL_EXAMINATION_ROOM',
        'shw' => 'HOSPITAL_AND_OUTPATIENT_SURGERY'
      },
      'Hotel/motel <= 75 rooms' => {
        'lighting' => 'GUEST_ROOM',
        'ventilation' => 'HOTELS_MOTELS_RESORTS_DORMITORIES_BEDROOM_LIVING_ROOM',
        'shw' => 'HOTEL'
      },
      'Hotel/motel > 75 rooms' => {
        'lighting' => 'GUEST_ROOM',
        'ventilation' => 'HOTELS_MOTELS_RESORTS_DORMITORIES_BEDROOM_LIVING_ROOM',
        'shw' => 'HOTEL'
      },
      'Office 5,000 to 50,000 sq ft' => {
        'lighting' => 'OFFICE_OPEN_PLAN',
        'ventilation' => 'OFFICE_BUILDINGS_OFFICE_SPACE',
        'shw' => 'OFFICE'
      },
      'Office <= 5,000 sq ft' => {
        'lighting' => 'OFFICE_OPEN_PLAN',
        'ventilation' => 'OFFICE_BUILDINGS_OFFICE_SPACE',
        'shw' => 'OFFICE'
      },
      'Office > 50,000 sq ft' => {
        'lighting' => 'OFFICE_OPEN_PLAN',
        'ventilation' => 'OFFICE_BUILDINGS_OFFICE_SPACE',
        'shw' => 'OFFICE'
      },
      'Restaurant (full service)' => {
        'lighting' => 'DINING_AREA_ALL_OTHERS',
        'ventilation' => 'FOOD_AND_BEVERAGE_SERVICE_RESTAURANT_DINING_ROOMS',
        'shw' => 'DINING_FAMILY'
      },
      'Restaurant (quick service)' => {
        'lighting' => 'DINING_AREA_CAFETERIA_OR_FAST_FOOD_DINING',
        'ventilation' => 'FOOD_AND_BEVERAGE_SERVICE_CAFETERIA_FAST_FOOD_DINING',
        'shw' => 'DINING_BAR_LOUNGE_LEISURE'
      },
      'Retail (stand alone)' => {
        'lighting' => 'RETAIL_FACILITIES_DRESSING_FITTING_ROOM',
        'ventilation' => 'RETAIL_SALES_EXCEPT_OTHER_SPECIFIC_RETAIL',
        'shw' => 'shw_type_retail_stand_alone'
      },
      'Retail (strip mall)' => {
        'lighting' => 'RETAIL_FACILITIES_MALL_CONCOURSE',
        'ventilation' => 'RETAIL_MALL_COMMON_AREAS',
        'shw' => 'RETAIL'
      },
      'School (primary)' => {
        'lighting' => 'CLASSROOM_LECTURE_HALL_TRAINING_ROOM_SCHOOL',
        'ventilation' => 'EDUCATIONAL_FACILITIES_CLASSROOMS_AGES_5_TO_8',
        'shw' => 'SCHOOL_UNIVERSITY'
      },
      'School (secondary and university)' => {
        'lighting' => 'CLASSROOM_LECTURE_HALL_TRAINING_ROOM_SCHOOL',
        'ventilation' => 'EDUCATIONAL_FACILITIES_CLASSROOMS_AGE_9_PLUS',
        'shw' => 'SCHOOL_UNIVERSITY'
      },
      'Warehouse (nonrefrigerated)' => {
        'lighting' => 'WAREHOUSE_STORAGE_AREA_MEDIUM_TO_BULKY_PALLETIZED_ITEMS',
        'ventilation' => 'MISCELLANEOUS_SPACES_WAREHOUSES',
        'shw' => 'WAREHOUSE'
      }
    }
    # Export OpenStudio model to epJson file.
    #
    # @param model [OpenStudio::Model::Model]
    # @param save_dir [String] epJson save directory
    # @param model_name [String] the name of the epJson file.
    # @return [Boolean] returns true if successful, false if not
    def self.export_epjson(model, save_dir, model_name)
      forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      workspace = forward_translator.translateModel(model)
      workspace_epjson_str = OpenStudio::EPJSON::toJSONString(workspace)
      begin
        output_path = "#{save_dir}/#{model_name}.epjson"
        epjson_model = File.open(output_path, 'w')
        epjson_model.puts(workspace_epjson_str)
      rescue StandardError => e
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.RulesetChecking', "Failed writing epjson file. Error message #{e}")
        return false
      ensure
        epjson_model.close if epjson_model
      end
      return true
    end

    # Add tags to the space object to indicate space types for RMD generator
    # Since OpenStudio SDK does not support space tags, this function is designed to be used in Eplus measure
    # Which requires the import of IDF model and OpenStudio model
    #
    # @param idf_model [OpenStudio::IDF]
    # @param space [OpenStudio::Model::Space]
    # @return [Boolean]
    def self.tag_spaces(idf_model, space)
      # all spaces from PRMs shall have the additional properties of building_type_for_wwr.
      # In this implementation, we will use this data to populate the rest of space types.
      bldg_type_wwr = get_additional_property_as_string(space, 'building_type_for_wwr', 'All others')
      bldg_types = BUILDING_MAP[bldg_type_wwr]
      idf_space = idf_model.getObjectsByName(space.name.to_s)[0]
      space_tag_index = OpenStudioStandards::RulesetChecking::find_index_of_string(idf_space, 'Space Type')
      tag_1_index = space_tag_index + 1
      tag_2_index = space_tag_index + 2

      idf_space.setString(space_tag_index, bldg_types['lighting'])
      idf_space.setString(tag_1_index, bldg_types['ventilation'])
      idf_space.setString(tag_2_index, bldg_types['shw'])
    end

    # Revise the output variables to prepare data export for RPD generation
    #
    # @param model [OpenStudio::Model::Model]
    # @return [Boolean] returns true if successful, false if not
    def self.export_json_output(model)
      # clear out the output, output:variable, output:schedule, outputcontrol:table:style and output:table:summaryreports
      # reformt it a different set.
      # reset output json
      output_json = model.getOutputJSON
      output_json ||= OpenStudio::Model::OutputJSON.new(model)
      output_json.setOptionType('TimeSeriesAndTabular')
      output_json.setOutputJSON(true)
      output_json.setOutputCBOR(false)
      output_json.setOutputMessagePack(false)

      # reset output schedule
      output_schedules = model.getOutputSchedules
      output_schedules ||= OpenStudio::Model::OutputSchedules.new(model)
      output_schedules.setKeyField('Hourly')

      # reset output control table style
      outputcontrol_table_style = model.getOutputControlTableStyle
      outputcontrol_table_style ||= OpenStudio::Model::OutputControlTableStyle.new(model)
      outputcontrol_table_style.setColumnSeparator('HTML')
      outputcontrol_table_style.setUnitConversion('None')

      # reset output table summary reports
      output_table_summaryreports = model.getOutputTableSummaryReports
      output_table_summaryreports ||= OpenStudio::Model::OutputTableSummaryReports.new(model)
      output_table_summaryreports.removeAllSummaryReports
      output_table_summaryreports.addSummaryReport('AllSummaryAndMonthly')

      # remove all output variables
      model.getOutputVariables.each(&:remove)
      output_variable = OpenStudio::Model::OutputVariable.new('Schedule Value', model)
      output_variable.setReportingFrequency('hourly')
      output_variable.setKeyValue('*')
    end

    # Count the number of lines of a idf object and return the last index
    # (e.g. find the index of "!- Fan Inlet Node Name")
    # @param idf_object
    # @return index if found
    def self.find_last_index_of_idf_object(idf_object)
      split_object = idf_object.to_s.split("\n")
      # remove the object title.
      split_object.length - 1
    end

    # Find the index of the E+ object which has a commented line with the search string
    # If the index is not found, this function returns the last index of the object + 1
    # (e.g. find the index of "!- Fan Inlet Node Name")
    # @param idf_object
    # @param search_string [String]
    # @return index if found
    def self.find_index_of_string(idf_object, search_string)

      split_object = idf_object.to_s.split("\n")

      index_counter = 0

      split_object.each do |line|
        if line.include? search_string
          # subtract 1 because the first line is the object type, not a index
          return index_counter - 1
        else
          index_counter += 1
        end
      end
      find_last_index_of_idf_object(idf_object)
    end
  end
end
