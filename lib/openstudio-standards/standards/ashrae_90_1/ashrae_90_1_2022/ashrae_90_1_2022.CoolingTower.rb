# A variety of cooling tower methods that are the same regardless of type.
# These methods are available to CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, and CoolingTowerVariableSpeed
module ASHRAE9012019CoolingTower
  # @!group CoolingTower

  # Above this point, centrifugal fan cooling towers must meet the limits of propeller or axial cooling towers instead.
  # @note code_sections 6.5.5.3 limit on centrifugal fan open=circuit cooling towers is 1,100 gallons per minute.
  #
  # @param cooling_tower [OpenStudio::Model::StraightComponent] cooling tower object, allowable types:
  #   CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, CoolingTowerVariableSpeed
  # @return [Double] the limit, in gallons per minute.  Return nil for no limit.
  def cooling_tower_apply_minimum_power_per_flow_gpm_limit(cooling_tower)
    gpm_limit = 1100.0
    return gpm_limit
  end
end

