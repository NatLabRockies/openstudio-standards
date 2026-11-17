class ASHRAE9012022 < ASHRAE901
  # @!group CoolingTowerVariableSpeed

  include ASHRAE9012019CoolingTower

  # Apply the efficiency, plus Multicell heat rejection with VSD
  #
  # @param cooling_tower_variable_speed [OpenStudio::Model::CoolingTowerVariableSpeed] variable speed cooling tower
  # @return [Boolean] returns true if successful, false if not
  def cooling_tower_variable_speed_apply_efficiency_and_curves(cooling_tower_variable_speed)
    cooling_tower_apply_minimum_power_per_flow(cooling_tower_variable_speed)
    cooling_tower_variable_speed.setCellControl('MaximalCell')
    return true
  end
end

