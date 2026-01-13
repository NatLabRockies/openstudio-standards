class Standard
  # @!group CoolingTowerTwoSpeed

  include CoolingTower

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param cooling_tower_two_speed [OpenStudio::Model::CoolingTowerTwoSpeed] two speed cooling tower
  # @return [Boolean] returns true if successful, false if not
  def cooling_tower_two_speed_apply_efficiency_and_curves(cooling_tower_two_speed)
    cooling_tower_apply_minimum_power_per_flow(cooling_tower_two_speed)

    return true
  end
end
