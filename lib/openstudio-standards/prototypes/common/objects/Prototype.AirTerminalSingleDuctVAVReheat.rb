class Standard
  # @!group AirTerminalSingleDuctVAVReheat
  # Set the initial minimum damper position based on OA rate of the space and the template.
  # Defaults to basic behavior, but this method is overridden by all of the ASHRAE-based templates.
  # Zones with low OA per area get lower initial guesses.
  # Final position will be adjusted upward as necessary by Standards.AirLoopHVAC.apply_minimum_vav_damper_positions
  #
  # @param air_terminal_single_duct_vav_reheat [OpenStudio::Model::AirTerminalSingleDuctVAVReheat] the air terminal object
  # @param zone_oa_per_area [Double] the zone outdoor air per area in m^3/s*m^2
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_vav_reheat_apply_initial_prototype_damper_position(air_terminal_single_duct_vav_reheat, zone_oa_per_area)
    min_damper_position = 0.3

    # Set the minimum flow fraction
    air_terminal_single_duct_vav_reheat.setConstantMinimumAirFlowFraction(min_damper_position)

    return true
  end

  # Sets VAV reheat and VAV no reheat terminals on an air loop to control for outdoor air
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param air_loop [<OpenStudio::Model::AirLoopHVAC>] air loop to enable DCV on.
  #   Default is nil, which will apply to all air loops
  # @return [OpenStudio::Model::Model] OpenStudio model object
  def model_set_vav_terminals_to_control_for_outdoor_air(model, air_loop: nil)
    vav_reheats = model.getAirTerminalSingleDuctVAVReheats
    vav_no_reheats = model.getAirTerminalSingleDuctVAVNoReheats

    if air_loop.nil?
      # all terminals
      vav_reheats.each do |vav_reheat|
        vav_reheat.setControlForOutdoorAir(true)
      end
      vav_no_reheats.each do |vav_no_reheat|
        vav_no_reheat.setControlForOutdoorAir(true)
      end
    else
      vav_reheats.each do |vav_reheat|
        next if vav_reheat.airLoopHVAC.get.name.to_s != air_loop.name.to_s

        vav_reheat.setControlForOutdoorAir(true)
      end
      vav_no_reheats.each do |vav_no_reheat|
        next if vav_no_reheat.airLoopHVAC.get.name.to_s != air_loop.name.to_s

        vav_no_reheat.setControlForOutdoorAir(true)
      end
    end
    return model
  end
end
