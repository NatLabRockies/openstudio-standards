module OpenStudioHVAC
  module Systems
    # Zone baseboards (electric or hot-water), ported from openstudio-standards
    # add_zone_baseboards.
    module Baseboards
      # @param model [OpenStudio::Model::Model]
      # @param zone [OpenStudio::Model::ThermalZone]
      # @param baseboard_type [String] 'Electric' or 'Hot Water'
      # @param hw_loop [OpenStudio::Model::PlantLoop, nil] required for 'Hot Water'
      # @return [void]
      def self.add(model, zone, baseboard_type:, hw_loop: nil)
        case baseboard_type
        when 'Electric'
          baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
          baseboard.addToThermalZone(zone)
        when 'Hot Water', 'HotWater'
          raise(ArgumentError, 'a hot water loop is required for Hot Water baseboards') if hw_loop.nil?

          coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model)
          hw_loop.addDemandBranchForComponent(coil)
          baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(
            model, model.alwaysOnDiscreteSchedule, coil
          )
          baseboard.addToThermalZone(zone)
        when 'None', nil
          # no baseboards
        else
          raise(ArgumentError, "'#{baseboard_type}' is not a valid baseboard type")
        end
      end
    end
  end
end
