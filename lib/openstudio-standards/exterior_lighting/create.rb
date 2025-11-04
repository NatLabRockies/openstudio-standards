module OpenstudioStandards
  # The Exterior Lighting module provides methods create, modify, and get information about model exterior lighting
  module ExteriorLighting
    # @!group Create

    # create an ExtertiorLights object from inputs
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String] the name of the exterior lights
    # @param power [Double] the watts value, can be watts or watts per area or length
    # @param units [String] units for the power, either 'W', 'W/ft' or 'W/ft^2'
    # @param multiplier [Double] the multiplier for the lighting, representing ft or ft^2
    # @param schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object. If nil, will default to always on.
    # @param control_option [String] Options are 'ScheduleNameOnly' and 'AstronomicalClock'.
    #   'ScheduleNameOnly' will follow the schedule. 'AstronomicalClock' will follow the schedule, but turn off lights when the sun is up.
    # @return [OpenStudio::Model::ExteriorLights] OpenStudio ExteriorLights object
    def self.model_create_exterior_lights(model,
                                          name: nil,
                                          power: 1.0,
                                          units: 'W',
                                          multiplier: 1.0,
                                          schedule: nil,
                                          control_option: 'AstronomicalClock')
      # default name
      if name.nil?
        name = "Exterior Lights #{power.round(2)} #{units}"
      else
        end_use_category = name
        name = "#{name} #{power.round(2)} #{units}"
      end

      # warn if incorrect control option
      unless OpenStudio::Model::ExteriorLights.validControlOptionValues.include? control_option
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ExteriorLighting', "Invalid control option #{control_option}. Use either ScheduleNameOnly' or 'AstronomicalClock'. Defaulting to 'AstronomicalClock'.")
        control_option = 'AstronomicalClock'
      end

      # default schedule
      schedule = model.alwaysOnDiscreteSchedule if schedule.nil?

      # create exterior light definition
      exterior_lights_definition = OpenStudio::Model::ExteriorLightsDefinition.new(model)
      exterior_lights_definition.setName("#{name} Def (#{units})")
      exterior_lights_definition.setDesignLevel(power)

      # creating exterior lights object
      exterior_lights = OpenStudio::Model::ExteriorLights.new(exterior_lights_definition, schedule)
      exterior_lights.setMultiplier(multiplier)
      exterior_lights.setName(name)
      exterior_lights.setControlOption(control_option)
      exterior_lights.setEndUseSubcategory(end_use_category)

      return exterior_lights
    end

    # Create typical exterior lighting in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] standard object to use for lighting properties. If set, will override lighting_generation.
    # @param lighting_generation [String] lighting generation to use for lighting properties. Currently defaulted to a mix of Metal Halide, High Pressure Sodium, and LEDs.
    # @param lighting_zone [Integer] exterior lighting zone number, 0-4
    # @param onsite_parking_fraction [Double] onsite parking fraction, 0-1
    # @param add_base_site_allowance [Boolean] whether to include the base site allowance
    # @param use_model_for_entries_and_canopies [Boolean] use building geometry for number of entries and canopy size
    # @param control_option [String] Options are 'ScheduleNameOnly' and 'AstronomicalClock'.
    #   'ScheduleNameOnly' will follow the schedule. 'AstronomicalClock' will follow the schedule, but turn off lights when the sun is up.
    # @return [Array<OpenStudio::Model::ExteriorLights>] Array of OpenStudio ExteriorLights object
    def self.create_typical_exterior_lighting(model,
                                              standard: nil,
                                              lighting_generation: 'default',
                                              lighting_zone: 3,
                                              onsite_parking_fraction: 1.0,
                                              add_base_site_allowance: false,
                                              use_model_for_entries_and_canopies: false,
                                              control_option: 'AstronomicalClock')
      exterior_lights = []
      installed_power = 0.0
      # get the exterior lighting properties from standard or the lighting_generation
      if standard.nil?
        exterior_lighting_properties = OpenstudioStandards::ExteriorLighting.exterior_lighting_properties(lighting_generation: lighting_generation)
        lookup_key = lighting_generation
      else
        lookup_key = standard.template
        if ['90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', '90.1-2016', '90.1-2019 PRM'].include?(lookup_key)
          exterior_lighting_properties = {}
        else
          search_criteria = {
            'lighting_zone' => lighting_zone
          }
          exterior_lighting_properties = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
        end
      end

      # make sure lighting properties were found
      if exterior_lighting_properties.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ExteriorLighting', "Exterior lighting properties not found for #{lookup_key}, ext lighting zone #{lighting_zone}, none will be added to model.")
        return exterior_lights
      end

      # get model specific areas to for exterior lighting
      area_length_count_hash = OpenstudioStandards::ExteriorLighting.model_get_exterior_lighting_sizes(model)

      # create schedules for exterior lighting objects using midnight to 6am setback or shutdown
      start_setback_shutoff = { hr: 24, min: 0 }
      end_setback_shutoff = { hr: 6, min: 0 }
      shuttoff = false
      setback = false

      if exterior_lighting_properties.key?('building_facade_and_landscape_automatic_shut_off')
        if exterior_lighting_properties['building_facade_and_landscape_automatic_shut_off'] == 1
          facade_automatic_shut_off = true
        else
          facade_automatic_shut_off = false
        end
      else
        search_criteria = {
          'template' => lookup_key,
          'lighting_zone' => lighting_zone,
          'allowance_type' => 'building facades',
          'allowance_unit' => 'W/ft2'
        }
        exterior_lighting_building_facade_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
        if exterior_lighting_building_facade_req['daylight_off_control'] == 'REQ'
          facade_automatic_shut_off = true
        else
          facade_automatic_shut_off = false
        end
      end

      if facade_automatic_shut_off
        ext_lights_sch_facade_and_landscape = OpenStudio::Model::ScheduleRuleset.new(model)
        default_day = ext_lights_sch_facade_and_landscape.defaultDaySchedule
        default_day.addValue(OpenStudio::Time.new(0, end_setback_shutoff[:hr], end_setback_shutoff[:min], 0), 0.0)
        default_day.addValue(OpenStudio::Time.new(0, start_setback_shutoff[:hr], start_setback_shutoff[:min], 0), 1.0)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Facade and Landscape exterior lights shut off from #{start_setback_shutoff} to #{end_setback_shutoff}")
      else
        ext_lights_sch_facade_and_landscape = model.alwaysOnDiscreteSchedule
      end

      occupancy_setback_reduction = 0.0
      if exterior_lighting_properties.key?('occupancy_setback_reduction')
        if !exterior_lighting_properties['occupancy_setback_reduction'].nil? && (exterior_lighting_properties['occupancy_setback_reduction'] > 0.0)
          occupancy_setback_reduction = exterior_lighting_properties['occupancy_setback_reduction']
        end
      else
        unless ['90.1-2004', '90.1-2007', 'DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'DEER 1985', 'DEER 1996', 'DEER 2003', 'DEER 2007', 'DEER Pre-1975'].include?(lookup_key)
          occupancy_setback_reduction = 0.3
        end
      end

      if occupancy_setback_reduction > 0
        ext_lights_sch_other = OpenStudio::Model::ScheduleRuleset.new(model)
        setback_value = 1.0 - occupancy_setback_reduction
        default_day = ext_lights_sch_other.defaultDaySchedule
        default_day.addValue(OpenStudio::Time.new(0, end_setback_shutoff[:hr], end_setback_shutoff[:min], 0), setback_value)
        default_day.addValue(OpenStudio::Time.new(0, start_setback_shutoff[:hr], start_setback_shutoff[:min], 0), 1.0)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Non Facade and Landscape lights reduce by #{occupancy_setback_reduction * 100} % from #{start_setback_shutoff} to #{end_setback_shutoff}")
      else
        ext_lights_sch_other = model.alwaysOnDiscreteSchedule
      end

      # add exterior lights for parking area
      if !area_length_count_hash[:parking_area_and_drives_area].nil? && area_length_count_hash[:parking_area_and_drives_area] > 0
        # lighting values
        multiplier = area_length_count_hash[:parking_area_and_drives_area] * onsite_parking_fraction

        # get power
        if exterior_lighting_properties.key?('parking_areas_and_drives')
          power = exterior_lighting_properties['parking_areas_and_drives']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'parking lots and drives'
          }
          exterior_lighting_parking_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          power = exterior_lighting_parking_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power.round(2)} W/ft^2 of lighting for #{multiplier} ft^2 of parking area.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Parking Areas and Drives',
                                                                                        power: power,
                                                                                        units: 'W/ft^2',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add exterior lights for facades
      if !area_length_count_hash[:building_facades].nil? && area_length_count_hash[:building_facades] > 0
        # lighting values
        multiplier = area_length_count_hash[:building_facades]

        # get power
        if exterior_lighting_properties.key?('building_facades')
          power = exterior_lighting_properties['building_facades']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'building facades',
            'allowance_unit' => 'W/ft2'
          }
          exterior_lighting_facade_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          power = exterior_lighting_facade_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power.round(2)} W/ft^2 of lighting for #{multiplier} ft^2 of building facade area.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Building Facades',
                                                                                        power: power,
                                                                                        units: 'W/ft^2',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_facade_and_landscape,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add exterior lights for main entries
      if !area_length_count_hash[:main_entries].nil? && area_length_count_hash[:main_entries] > 0
        # lighting values
        multiplier = area_length_count_hash[:main_entries]

        # get power
        if exterior_lighting_properties.key?('main_entries')
          power = exterior_lighting_properties['main_entries']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'main entries'
          }
          exterior_lighting_entries_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          # change of reference for 90.1-2019 and onwards
          if exterior_lighting_entries_req.nil?
            search_criteria = {
              'template' => lookup_key,
              'lighting_zone' => lighting_zone,
              'allowance_type' => 'pedestrian and vehicular entrances and exists'
            }
            exterior_lighting_entries_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          end
          power = exterior_lighting_entries_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power.round(2)} W/ft of lighting for #{multiplier} ft of main entry length.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Main Entries',
                                                                                        power: power,
                                                                                        units: 'W/ft',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add exterior lights for other doors
      if !area_length_count_hash[:other_doors].nil? && area_length_count_hash[:other_doors] > 0
        # lighting values
        multiplier = area_length_count_hash[:other_doors]

        # get power
        if exterior_lighting_properties.key?('other_doors')
          power = exterior_lighting_properties['other_doors']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'other doors'
          }
          exterior_lighting_doors_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          # change of reference for 90.1-2019 and onwards
          if exterior_lighting_doors_req.nil?
            search_criteria = {
              'template' => lookup_key,
              'lighting_zone' => lighting_zone,
              'allowance_type' => 'pedestrian and vehicular entrances and exists'
            }
            exterior_lighting_doors_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          end
          power = exterior_lighting_doors_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power.round(2)} W/ft of lighting for #{multiplier} ft of other doors.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Other Doors',
                                                                                        power: power,
                                                                                        units: 'W/ft',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add exterior lights for entry canopies
      if !area_length_count_hash[:canopy_entry_area].nil? && area_length_count_hash[:canopy_entry_area] > 0
        # lighting values
        multiplier = area_length_count_hash[:canopy_entry_area]

        # get power
        if exterior_lighting_properties.key?('entry_canopies')
          power = exterior_lighting_properties['entry_canopies']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'canopies'
          }
          exterior_lighting_canopies_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          # change of reference for 90.1-2010 and onwards
          if exterior_lighting_parking_req.nil?
            search_criteria = {
              'template' => lookup_key,
              'lighting_zone' => lighting_zone,
              'allowance_type' => 'entry canopies'
            }
            exterior_lighting_canopies_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          end
          power = exterior_lighting_canopies_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power} W/ft^2 of lighting for #{multiplier} ft^2 of building entry canopies.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Entry Canopies',
                                                                                        power: power,
                                                                                        units: 'W/ft^2',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add exterior lights for emergency canopies
      if !area_length_count_hash[:canopy_emergency_area].nil? && area_length_count_hash[:canopy_emergency_area] > 0
        # lighting values
        multiplier = area_length_count_hash[:canopy_emergency_area]

        # get power
        if exterior_lighting_properties.key?('loading_areas_for_emergency_vehicles')
          power = exterior_lighting_properties['loading_areas_for_emergency_vehicles']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'loading areas for law enforcement, fire, ambulance and other emergency service vehicles (uncovered)'
          }
          exterior_lighting_emergency_canopies_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          power = exterior_lighting_emergency_canopies_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power} W/ft^2 of lighting for #{multiplier} ft^2 of building emergency canopies.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Emergency Canopies',
                                                                                        power: power,
                                                                                        units: 'W/ft^2',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add exterior lights for drive through windows
      if !area_length_count_hash[:drive_through_windows].nil? && area_length_count_hash[:drive_through_windows] > 0
        # lighting values
        multiplier = area_length_count_hash[:drive_through_windows]

        # get power
        if exterior_lighting_properties.key?('drive_through_windows_and_doors')
          power = exterior_lighting_properties['drive_through_windows_and_doors']
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'drive-up windows at fast food restaurant'
          }
          exterior_lighting_emergency_drive_through_req = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          power = exterior_lighting_emergency_drive_through_req['allowance']
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power} W/drive through window of lighting for #{multiplier} drive through windows.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Drive Through Windows',
                                                                                        power: power,
                                                                                        units: 'W/ft^2',
                                                                                        multiplier: multiplier,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
        installed_power += power * multiplier
      end

      # add base site allowance
      if add_base_site_allowance
        # lighting values
        if exterior_lighting_properties.key?('base_site_allowance_power')
          if !exterior_lighting_properties['base_site_allowance_power'].nil?
            power = exterior_lighting_properties['base_site_allowance_power']
          elsif !exterior_lighting_properties['base_site_allowance_fraction'].nil?
            power = exterior_lighting_properties['base_site_allowance_fraction'] * installed_power # should be of allowed vs. installed, but hard to calculate
          else
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', 'Cannot determine target base site allowance power, will set to 0 W.')
            power = 0.0
          end
        else
          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'base site allowance'
          }
          exterior_lighting_base_allowance = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          power = exterior_lighting_base_allowance['allowance']

          search_criteria = {
            'template' => lookup_key,
            'lighting_zone' => lighting_zone,
            'allowance_type' => 'additional unrestricted allowance'
          }
          exterior_lighting_add_base_allowance = standard.standards_lookup_table_first(table_name: 'exterior_lighting', search_criteria: search_criteria)
          if !exterior_lighting_add_base_allowance.nil?
            power += exterior_lighting_add_base_allowance['allowance'] * installed_power / 100.0 # should be of allowed vs. installed, but hard to calculate
          end
        end

        # create exterior lights
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ExteriorLighting', "Added #{power} W of non landscape tradable exterior lighting. Will follow occupancy setback reduction.")
        ext_lights = OpenstudioStandards::ExteriorLighting.model_create_exterior_lights(model,
                                                                                        name: 'Base Site Allowance',
                                                                                        power: power,
                                                                                        units: 'W',
                                                                                        multiplier: 1.0,
                                                                                        schedule: ext_lights_sch_other,
                                                                                        control_option: control_option)
        exterior_lights << ext_lights
      end

      return exterior_lights
    end
  end
end
