module OpenstudioStandards
  # The Geometry module provides methods to create, modify, and get information about model geometry
  module Geometry
    # Methods to group thermal zones

    # @!group Group

    # Group an array of zones into multiple arrays, one for each story in the building.
    # Zones with spaces on multiple stories will be assigned to only one of the stories.
    # Returns an empty array when the story doesn't contain any of the zones.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio Model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] An array of OpenStudio ThermalZone objects
    # @return [Array<Array<OpenStudio::Model::ThermalZone>>] An array of arrays of OpenStudio ThermalZone objects
    def self.model_group_thermal_zones_by_building_story(model, thermal_zones)
      story_zone_lists = []
      zones_already_assigned = []
      model.getBuildingStorys.sort.each do |story|
        # Get all the spaces on this story
        spaces = story.spaces

        # Get all the thermal zones that serve these spaces
        all_zones_on_story = []
        spaces.each do |space|
          if space.thermalZone.is_initialized
            all_zones_on_story << space.thermalZone.get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Space #{space.name} has no thermal zone, it is not included in the simulation.")
          end
        end

        # Find thermal zones in the list that are on this story
        zones_on_story = []
        thermal_zones.each do |zone|
          if all_zones_on_story.include?(zone)
            # Skip thermal zones that were already assigned to a story.
            # This can happen if a zone has multiple spaces on multiple stories.
            # Stairwells and atriums are typical scenarios.
            next if zones_already_assigned.include?(zone)

            zones_on_story << zone
            zones_already_assigned << zone
          end
        end

        unless zones_on_story.empty?
          story_zone_lists << zones_on_story
        end
      end

      return story_zone_lists
    end

    # Split all zones in the model into groups that are big enough to justify their own HVAC system type.
    # Similar to the logic from 90.1 Appendix G, but without regard to the fuel type of the existing HVAC system (because the model may not have one).
    #
    # @param model [OpenStudio::Model::Model] OpenStudio Model object
    # @param min_area_m2 [Double] the minimum area required to justify a different system type, default 20,000 ft^2
    # @return [Array<Hash>] an array of hashes of area information, with keys area_ft2, type, stories, and zones (an array of zones)
    def self.model_group_thermal_zones_by_occupancy_type(model, min_area_m2: 1858.0608)
      min_area_ft2 = OpenStudio.convert(min_area_m2, 'm^2', 'ft^2').get

      # Get occupancy type, fuel type, and area information for all zones, excluding unconditioned zones.
      # Occupancy types are:
      # Residential
      # NonResidential
      # Use 90.1-2010 so that retail and publicassembly are not split out
      std = Standard.build('90.1-2019') # delete once space methods refactored
      zones = std.model_zones_with_occ_and_fuel_type(model, nil)

      # Ensure that there is at least one conditioned zone
      if zones.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', 'The building does not appear to have any conditioned zones. Make sure zones have thermostat with appropriate heating and cooling setpoint schedules.')
        return []
      end

      # Group the zones by occupancy type
      type_to_area = Hash.new { 0.0 }
      zones_grouped_by_occ = zones.group_by { |z| z['occ'] }

      # Determine the dominant occupancy type by area
      zones_grouped_by_occ.each do |occ_type, zns|
        zns.each do |zn|
          type_to_area[occ_type] += zn['area']
        end
      end
      dom_occ = type_to_area.sort_by { |k, v| v }.reverse[0][0]

      # Get the dominant occupancy type group
      dom_occ_group = zones_grouped_by_occ[dom_occ]

      # Check the non-dominant occupancy type groups to see if they are big enough to trigger the occupancy exception.
      # If they are, leave the group standing alone.
      # If they are not, add the zones in that group back to the dominant occupancy type group.
      occ_groups = []
      zones_grouped_by_occ.each do |occ_type, zns|
        # Skip the dominant occupancy type
        next if occ_type == dom_occ

        # Add up the floor area of the group
        area_m2 = 0
        zns.each do |zn|
          area_m2 += zn['area']
        end
        area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

        # If the non-dominant group is big enough, preserve that group.
        if area_ft2 > min_area_ft2
          occ_groups << [occ_type, zns]
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "The portion of the building with an occupancy type of #{occ_type} is bigger than the minimum area of #{min_area_ft2.round} ft2.  It will be assigned a separate HVAC system type.")
          # Otherwise, add the zones back to the dominant group.
        else
          dom_occ_group += zns
        end
      end
      # Add the dominant occupancy group to the list
      occ_groups << [dom_occ, dom_occ_group]

      # Calculate the area for each of the final groups
      # and replace the zone hashes with an array of zone objects
      final_groups = []
      occ_groups.each do |occ_type, zns|
        # Sum the area and put all zones into an array
        area_m2 = 0.0
        gp_zns = []
        zns.each do |zn|
          area_m2 += zn['area']
          gp_zns << zn['zone']
        end
        area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

        # Determine the number of stories this group spans
        num_stories = OpenstudioStandards::Geometry.thermal_zones_get_number_of_stories_spanned(gp_zns)

        # Create a hash representing this group
        group = {}
        group['area_ft2'] = area_ft2
        group['type'] = occ_type
        group['stories'] = num_stories
        group['zones'] = gp_zns
        final_groups << group

        # Report out the final grouping
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Final system type group: occ = #{group['type']}, area = #{group['area_ft2'].round} ft2, num stories = #{group['stories']}, zones:")
        group['zones'].sort.each_slice(5) do |zone_list|
          zone_names = []
          zone_list.each do |zone|
            zone_names << zone.name.get.to_s
          end
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{zone_names.join(', ')}")
        end
      end

      return final_groups
    end

    # Split all zones in the model into groups that are big enough to justify their own HVAC system type.
    # Similar to the logic from 90.1 Appendix G, but without regard to the fuel type of the existing HVAC system (because the model may not have one).
    #
    # @param model [OpenStudio::Model::Model] OpenStudio Model object
    # @param min_area_m2 [Double] the minimum area required to justify a different system type, default 20,000 ft^2
    # @return [Array<Hash>] an array of hashes of area information, with keys area_ft2, type, stories, and zones (an array of zones)
    def self.model_group_thermal_zones_by_building_type(model, min_area_m2: 1858.0608)
      min_area_ft2 = OpenStudio.convert(min_area_m2, 'm^2', 'ft^2').get

      # Get occupancy type, building type, fuel type, and area information for all zones, excluding unconditioned zones
      std = Standard.build('90.1-2019') # delete once space methods refactored
      zones = std.model_zones_with_occ_and_fuel_type(model, nil)

      # Ensure that there is at least one conditioned zone
      if zones.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', 'The building does not appear to have any conditioned zones. Make sure zones have thermostat with appropriate heating and cooling setpoint schedules.')
        return []
      end

      # Group the zones by building type
      type_to_area = Hash.new { 0.0 }
      zones_grouped_by_bldg_type = zones.group_by { |z| z['bldg_type'] }

      # Determine the dominant building type by area
      zones_grouped_by_bldg_type.each do |bldg_type, zns|
        zns.each do |zn|
          type_to_area[bldg_type] += zn['area']
        end
      end
      dom_bldg_type = type_to_area.sort_by { |k, v| v }.reverse[0][0]

      # Get the dominant building type group
      dom_bldg_type_group = zones_grouped_by_bldg_type[dom_bldg_type]

      # Check the non-dominant building type groups to see if they are big enough to trigger the building exception.
      # If they are, leave the group standing alone.
      # If they are not, add the zones in that group back to the dominant building type group.
      bldg_type_groups = []
      zones_grouped_by_bldg_type.each do |bldg_type, zns|
        # Skip the dominant building type
        next if bldg_type == dom_bldg_type

        # Add up the floor area of the group
        area_m2 = 0
        zns.each do |zn|
          area_m2 += zn['area']
        end
        area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

        # If the non-dominant group is big enough, preserve that group.
        if area_ft2 > min_area_ft2
          bldg_type_groups << [bldg_type, zns]
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "The portion of the building with a building type of #{bldg_type} is bigger than the minimum area of #{min_area_ft2.round} ft2.  It will be assigned a separate HVAC system type.")
          # Otherwise, add the zones back to the dominant group.
        else
          dom_bldg_type_group += zns
        end
      end
      # Add the dominant building type group to the list
      bldg_type_groups << [dom_bldg_type, dom_bldg_type_group]

      # Calculate the area for each of the final groups
      # and replace the zone hashes with an array of zone objects
      final_groups = []
      bldg_type_groups.each do |bldg_type, zns|
        # Sum the area and put all zones into an array
        area_m2 = 0.0
        gp_zns = []
        zns.each do |zn|
          area_m2 += zn['area']
          gp_zns << zn['zone']
        end
        area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

        # Determine the number of stories this group spans
        num_stories = OpenstudioStandards::Geometry.thermal_zones_get_number_of_stories_spanned(gp_zns)

        # Create a hash representing this group
        group = {}
        group['area_ft2'] = area_ft2
        group['type'] = bldg_type
        group['stories'] = num_stories
        group['zones'] = gp_zns
        final_groups << group

        # Report out the final grouping
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Final system type group: bldg_type = #{group['type']}, area = #{group['area_ft2'].round} ft2, num stories = #{group['stories']}, zones:")
        group['zones'].sort.each_slice(5) do |zone_list|
          zone_names = []
          zone_list.each do |zone|
            zone_names << zone.name.get.to_s
          end
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{zone_names.join(', ')}")
        end
      end

      return final_groups
    end

    # @!endgroup Group
  end
end
