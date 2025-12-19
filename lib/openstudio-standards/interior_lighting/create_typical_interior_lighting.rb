module OpenstudioStandards
  # The InteriorLighting module provides methods to create, modify, and get information about interior lighting
  module InteriorLighting
    # @!group Create Typical Interior Lighting
    # Methods to create typical interior lighting

    # Create typical interior lighting in a model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param lighting_generation [String] Lighting generation to assume for lighting. Successive generations have more efficient lighting.
    #   Options are 'gen1_t12_incandescent', 'gen2_t8_halogen', 'gen3_t5_cfl', 'gen4_led', 'gen5_led', 'gen6_led', 'gen7_led', 'gen8_led'.
    # @return [Array<OpenStudio::Model::Lights>] Array of OpenStudio Lights objects
    def self.create_typical_interior_lighting(model, lighting_generation: 'gen4_led')
      # collectors for building lighting power and floor area
      interior_lights = []
      building_lighting_floor_area = 0.0
      starting_building_lighting_power = 0.0
      ending_building_lighting_power = 0.0

      # load lighting technology data
      lighting_technologies_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/lighting_technology.json"), symbolize_names: true)
      lighting_technologies = lighting_technologies_data[:lighting_technologies].select { |hash| (hash[:lighting_generation] == lighting_generation) }
      if lighting_technologies.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', "No interior lighting technologies found for lighting generation #{lighting_generation}. No interior lighting will be added to model.")
        return interior_lights
      end

      # load lighting space types data
      lighting_space_type_properties_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/data/lighting_space_types.json"), symbolize_names: true)
      if lighting_space_type_properties_data.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', 'Unable to load lighting space types data. No interior lighting will be added to model.')
        return interior_lights
      end
      lighting_space_type_properties_data = lighting_space_type_properties_data[:lighting_space_types]

      # loop over space types and apply lighting
      model.getSpaceTypes.each do |space_type|
        # get space type area and volume
        space_type_floor_area = space_type.floorArea
        if space_type_floor_area.zero?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', "Space type #{space_type} floor area is zero. Ignoring space type.")
          next
        end

        space_type_volume = 0.0
        space_type.spaces.each do |space|
          space_type_volume += space.volume * space.multiplier
        end

        if space_type_volume.zero?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', "Volume for space type #{space_type.name} is zero. Ignoring space type.")
          next
        elsif space_type_volume.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', "Unable to determine volume for space type #{space_type.name}. Ignoring space type.")
          next
        end

        # calculate average space_type height
        space_type_average_height_m = space_type_volume / space_type_floor_area
        space_type_average_height_ft = OpenStudio.convert(space_type_average_height_m, 'm', 'ft').get

        # get number of people for lighting calculations
        space_type_number_of_people = space_type.getNumberOfPeople(space_type_floor_area)

        # get initial conditions
        building_lighting_floor_area += space_type_floor_area
        starting_space_type_lighting_power = space_type.getLightingPower(space_type_floor_area, space_type_number_of_people)
        starting_building_lighting_power += starting_space_type_lighting_power

        # remove existing lighting objects
        space_type.lights.sort.each(&:remove)

        # remove existing lighting objects from spaces
        space_type.spaces.each do |space|
          space.lights.sort.each(&:remove)
        end

        # get lighting space type from the object
        has_lighting_space_type = space_type.additionalProperties.hasFeature('lighting_space_type')
        unless has_lighting_space_type
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', "Space type '#{space_type.name}' does not have a lighting_space_type property assigned. Ignoring space type.")
          next
        end
        lighting_space_type = space_type.additionalProperties.getFeatureAsString('lighting_space_type').to_s

        # get lighting properties for the lighting space type
        lighting_space_type_properties = lighting_space_type_properties_data.select { |r| (r[:lighting_space_type_name] == lighting_space_type) }
        if lighting_space_type_properties.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', "Unable to find lighting space type data for '#{lighting_space_type}'. Ignoring space type #{space_type.name}.")
          next
        end
        lighting_space_type_properties = lighting_space_type_properties[0]

        # get lighting properties for the lighting space type
        lighting_space_type_target_illuminance_setpoint = lighting_space_type_properties[:lighting_space_type_target_illuminance_setpoint].to_f
        lighting_space_type_target_illuminance_units = lighting_space_type_properties[:lighting_space_type_target_illuminance_units].to_s
        general_lighting_fraction = lighting_space_type_properties[:general_lighting_fraction].to_f
        general_cu = lighting_space_type_properties[:general_lighting_coefficient_of_utilization].to_f
        task_lighting_fraction = lighting_space_type_properties[:task_lighting_fraction].to_f
        task_cu = lighting_space_type_properties[:task_lighting_coefficient_of_utilization].to_f
        supplemental_lighting_fraction = lighting_space_type_properties[:supplemental_lighting_fraction].to_f
        supplemental_cu = lighting_space_type_properties[:supplemental_lighting_coefficient_of_utilization].to_f
        wall_wash_lighting_fraction = lighting_space_type_properties[:wall_wash_lighting_fraction].to_f
        wall_wash_cu = lighting_space_type_properties[:wall_wash_lighting_coefficient_of_utilization].to_f

        # variable holder for lighting technology, default 'na'
        general_lighting_technology_name = 'na'
        task_lighting_technology_name = 'na'
        supplemental_lighting_technology_name = 'na'
        wall_wash_lighting_technology_name = 'na'

        # general lighting
        if general_lighting_fraction > 0
          matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'general') }
          matching_objects = matching_objects.reject { |r| space_type_average_height_ft.to_f.round(1) > r[:fixture_max_height_ft].to_f.round(1) }
          matching_objects = matching_objects.reject { |r| space_type_average_height_ft.to_f.round(1) <= r[:fixture_min_height_ft].to_f.round(1) }
          general_lighting_technology = matching_objects[0]
          luminous_efficacy = general_lighting_technology[:source_efficacy_lumens_per_watt].to_f
          llf = general_lighting_technology[:lighting_loss_factor].to_f

          # ignore depreciation terms (rsdd, llf) when setting installed lighting power
          general_lpd_w_per_m2 = (lighting_space_type_target_illuminance_setpoint * general_lighting_fraction) / (luminous_efficacy * general_cu)
          general_lighting_technology_name = general_lighting_technology[:lighting_technology]

          # general lighting definition
          general_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
          general_lights_definition.setName("#{space_type.name} General Lights Definition")
          general_lights_definition.setWattsperSpaceFloorArea(general_lpd_w_per_m2)
          general_lights_definition.setReturnAirFraction(general_lighting_technology[:return_air_fraction].to_f)
          general_lights_definition.setFractionRadiant(general_lighting_technology[:radiant_fraction].to_f)
          general_lights_definition.setFractionVisible(general_lighting_technology[:visible_fraction].to_f)
          general_lights_definition.additionalProperties.setFeature('lighting_technology', general_lighting_technology_name)
          general_lights_definition.additionalProperties.setFeature('lighting_system_type', 'general')

          # general lighting object
          general_lights = OpenStudio::Model::Lights.new(general_lights_definition)
          general_lights.setName("#{space_type.name} General Lighting")
          general_lights.setSpaceType(space_type)
          interior_lights << general_lights
        end

        # task lighting
        if task_lighting_fraction > 0
          matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'task') }
          task_lighting_technology = matching_objects[0]
          luminous_efficacy = task_lighting_technology[:source_efficacy_lumens_per_watt].to_f
          llf = task_lighting_technology[:lighting_loss_factor].to_f

          # ignore depreciation terms (rsdd, llf) when setting installed lighting power
          task_lpd_w_per_m2 = (lighting_space_type_target_illuminance_setpoint * task_lighting_fraction) / (luminous_efficacy * task_cu)
          task_lighting_technology_name = task_lighting_technology[:lighting_technology]

          # task lighting definition
          task_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
          task_lights_definition.setName("#{space_type.name} Task Lights Definition")
          task_lights_definition.setWattsperSpaceFloorArea(task_lpd_w_per_m2)
          task_lights_definition.setReturnAirFraction(task_lighting_technology[:return_air_fraction].to_f)
          task_lights_definition.setFractionRadiant(task_lighting_technology[:radiant_fraction].to_f)
          task_lights_definition.setFractionVisible(task_lighting_technology[:visible_fraction].to_f)
          task_lights_definition.additionalProperties.setFeature('lighting_technology', task_lighting_technology_name)
          task_lights_definition.additionalProperties.setFeature('lighting_system_type', 'task')

          # task lighting object
          task_lights = OpenStudio::Model::Lights.new(task_lights_definition)
          task_lights.setName("#{space_type.name} Task Lighting")
          task_lights.setSpaceType(space_type)
          interior_lights << task_lights
        end

        # supplemental lighting
        if supplemental_lighting_fraction > 0
          matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'supplemental') }
          supplemental_lighting_technology = matching_objects[0]
          luminous_efficacy = supplemental_lighting_technology[:source_efficacy_lumens_per_watt].to_f
          llf = supplemental_lighting_technology[:lighting_loss_factor].to_f

          # ignore depreciation terms (rsdd, llf) when setting installed lighting power
          supplemental_lpd_w_per_m2 = (lighting_space_type_target_illuminance_setpoint * supplemental_lighting_fraction) / (luminous_efficacy * supplemental_cu)
          supplemental_lighting_technology_name = supplemental_lighting_technology[:lighting_technology]

          # supplemental lighting definition
          supplemental_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
          supplemental_lights_definition.setName("#{space_type.name} Supplemental Lights Definition")
          supplemental_lights_definition.setWattsperSpaceFloorArea(supplemental_lpd_w_per_m2)
          supplemental_lights_definition.setReturnAirFraction(supplemental_lighting_technology[:return_air_fraction].to_f)
          supplemental_lights_definition.setFractionRadiant(supplemental_lighting_technology[:radiant_fraction].to_f)
          supplemental_lights_definition.setFractionVisible(supplemental_lighting_technology[:visible_fraction].to_f)
          supplemental_lights_definition.additionalProperties.setFeature('lighting_technology', supplemental_lighting_technology_name)
          supplemental_lights_definition.additionalProperties.setFeature('lighting_system_type', 'supplemental')

          # supplemental lighting object
          supplemental_lights = OpenStudio::Model::Lights.new(supplemental_lights_definition)
          supplemental_lights.setName("#{space_type.name} Supplemental Lighting")
          supplemental_lights.setSpaceType(space_type)
          interior_lights << supplemental_lights
        end

        # wall wash lighting
        if wall_wash_lighting_fraction > 0
          matching_objects = lighting_technologies.select { |r| (r[:lighting_system_type] == 'wall_wash') }
          wall_wash_lighting_technology = matching_objects[0]
          luminous_efficacy = wall_wash_lighting_technology[:source_efficacy_lumens_per_watt].to_f
          llf = wall_wash_lighting_technology[:lighting_loss_factor].to_f

          # ignore depreciation terms (rsdd, llf) when setting installed lighting power
          wall_wash_lpd_w_per_m2 = (lighting_space_type_target_illuminance_setpoint * wall_wash_lighting_fraction) / (luminous_efficacy * wall_wash_cu)
          wall_wash_lighting_technology_name = wall_wash_lighting_technology[:lighting_technology]

          # wall wash lighting definition
          wall_wash_lights_definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
          wall_wash_lights_definition.setName("#{space_type.name} Wall Wash Lights Definition")
          wall_wash_lights_definition.setWattsperSpaceFloorArea(wall_wash_lpd_w_per_m2)
          wall_wash_lights_definition.setReturnAirFraction(wall_wash_lighting_technology[:return_air_fraction].to_f)
          wall_wash_lights_definition.setFractionRadiant(wall_wash_lighting_technology[:radiant_fraction].to_f)
          wall_wash_lights_definition.setFractionVisible(wall_wash_lighting_technology[:visible_fraction].to_f)
          wall_wash_lights_definition.additionalProperties.setFeature('lighting_technology', wall_wash_lighting_technology_name)
          wall_wash_lights_definition.additionalProperties.setFeature('lighting_system_type', 'wall_wash')

          # wall wash lighting object
          wall_wash_lights = OpenStudio::Model::Lights.new(wall_wash_lights_definition)
          wall_wash_lights.setName("#{space_type.name} Wall Wash Lighting")
          wall_wash_lights.setSpaceType(space_type)
          interior_lights << wall_wash_lights
        end

        # calculate ending lighting power
        ending_space_type_lighting_power = space_type.getLightingPower(space_type_floor_area, space_type_number_of_people)
        ending_building_lighting_power += ending_space_type_lighting_power

        if space_type_floor_area > 0
          starting_space_type_lpd = OpenStudio.convert(starting_space_type_lighting_power / space_type_floor_area, 'W/m^2', 'W/ft^2').get
          ending_space_type_lpd = OpenStudio.convert(ending_space_type_lighting_power / space_type_floor_area, 'W/m^2', 'W/ft^2').get
        else
          starting_space_type_lpd = 0.0
          ending_space_type_lpd = 0.0
        end

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.InteriorLighting', "Setting space type '#{space_type.name}' with lighting space type '#{lighting_space_type}' to lighting generation '#{lighting_generation}', general '#{general_lighting_technology_name}', task '#{task_lighting_technology_name}', supplemental '#{supplemental_lighting_technology_name}', wall_wash '#{wall_wash_lighting_technology_name}'.  Starting LPD #{starting_space_type_lpd.round(2)} W/ft2, ending LPD #{ending_space_type_lpd.round(2)} W/ft2.")
      end

      if building_lighting_floor_area > 0
        starting_building_lpd = OpenStudio.convert(starting_building_lighting_power / building_lighting_floor_area, 'W/m^2', 'W/ft^2').get
        ending_building_lpd = OpenStudio.convert(ending_building_lighting_power / building_lighting_floor_area, 'W/m^2', 'W/ft^2').get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.InteriorLighting', 'Building lighting floor area is zero. This can happen if space types are not assigned to spaces. Unable to report out building level LPDs.')
        starting_building_lpd = 0
        ending_building_lpd = 0
      end
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.InteriorLighting', "Building lighting started with #{starting_building_lighting_power.round(2)} W (average LPD #{starting_building_lpd.round(2)} W/ft2) and ended with #{ending_building_lighting_power.round(2)} W (average LPD #{ending_building_lpd.round(2)} W/ft2).")

      return interior_lights
    end
  end
end
