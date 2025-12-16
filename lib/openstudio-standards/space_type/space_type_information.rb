module OpenstudioStandards
  # The SpaceType module provides methods to modify, get, and set information about model space types
  module SpaceType
    # @!group SpaceType

    # Return the largest thermal zone in a space type
    # If multiple zones of the same size exist, the first one alphabetically will be returned.
    #
    # @param space_type [OpenStudio::Model::Space Type] OpenStudio space type  object
    # @return [OpenStudio::Model::ThermalZone] returns the largest thermal zone in the space type
    def self.space_type_get_largest_thermal_zone(space_type)
      thermal_zones = []
      space_type.spaces.each do |space|
        if space.thermalZone.is_initialized
          thermal_zones << space.thermalZone.get
        end
      end
      if thermal_zones.empty?
        return nil
      else
        max_floor_area = 0.0
        largest_thermal_zone = nil
        thermal_zones.sort_by { |zone| zone.name.to_s }.each do |zone|
          if zone.floorArea > max_floor_area
            largest_thermal_zone = zone
            max_floor_area = zone.floorArea
          end
        end
        return largest_thermal_zone
      end
    end
  end
end
