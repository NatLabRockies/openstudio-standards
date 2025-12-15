module OpenstudioStandards
  # The SpaceType module provides methods to modify, get, and set information about model space types
  module SpaceType
    # @!group SpaceType

    # Return the largest thermal zone in a space type
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
        largest_thermal_zone = thermal_zones.sort_by { |zone| -zone.floorArea }.first
        return largest_thermal_zone
      end
    end
  end
end
