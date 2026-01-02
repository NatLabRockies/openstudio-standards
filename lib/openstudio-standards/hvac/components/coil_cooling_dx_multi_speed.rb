module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Component:Coil
    # Methods to create, modify, and get information about HVAC coil objects

    # Return the capacity in W of a CoilCoolingDXMultiSpeed
    #
    #
    # @param coil_cooling_dx_multi_speed [OpenStudio::Model::CoilCoolingDXMultiSpeed] coil cooling dx multi speed object
    # @param multiplier [Double] zone multiplier, if applicable
    # @return [Double] capacity in W
    def self.coil_cooling_dx_multi_speed_get_capacity(coil_cooling_dx_multi_speed, multiplier: nil)
      capacity_w = nil
      clg_stages = coil_cooling_dx_multi_speed.stages
      if clg_stages.last.grossRatedTotalCoolingCapacity.is_initialized
        capacity_w = clg_stages.last.grossRatedTotalCoolingCapacity.get
      elsif (clg_stages.size == 1) && coil_cooling_dx_multi_speed.stages[0].autosizedSpeedRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_multi_speed.stages[0].autosizedSpeedRatedTotalCoolingCapacity.get
      elsif (clg_stages.size == 2) && coil_cooling_dx_multi_speed.stages[1].autosizedGrossRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_multi_speed.stages[1].autosizedGrossRatedTotalCoolingCapacity.get
      elsif (clg_stages.size == 3) && coil_cooling_dx_multi_speed.stages[2].autosizedGrossRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_multi_speed.stages[2].autosizedSpeedRatedTotalCoolingCapacity.get
      elsif (clg_stages.size == 4) && coil_cooling_dx_multi_speed.stages[3].autosizedGrossRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil_cooling_dx_multi_speed.stages[3].autosizedGrossRatedTotalCoolingCapacity.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC.coil_cooling_dx_multi_speed', "For #{coil_cooling_dx_multi_speed.name} capacity is not available.")
        return capacity_w
      end

      if !multiplier.nil? && multiplier > 1
        total_cap = capacity_w
        capacity_w /= multiplier
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC.coil_cooling_dx_multi_speed', "For #{coil_cooling_dx_multi_speed.name}, total capacity of #{OpenStudio.convert(total_cap, 'W', 'kBtu/hr').get.round(2)}kBTU/hr was divided by the zone multiplier of #{multiplier} to give #{capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get.round(2)}kBTU/hr.")
      end

      return capacity_w
    end
  end
end
