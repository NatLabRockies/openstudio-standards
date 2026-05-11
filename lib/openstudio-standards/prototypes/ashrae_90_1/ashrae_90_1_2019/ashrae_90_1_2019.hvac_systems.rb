class ASHRAE9012019 < ASHRAE901
  # @!group hvac_systems

  # Determine which type of fan the cooling tower will have.
  # Variable Speed Fan for ASHRAE 90.1-2019.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] the fan type: TwoSpeed Fan, Variable Speed Fan
  def model_cw_loop_cooling_tower_fan_type(model)
    fan_type = 'Variable Speed Fan'
    return fan_type
  end

  # Create an economizer maximum OA fraction schedule with
  # For ASHRAE 90.1 2019, a maximum of 75% to reflect damper leakage per PNNL
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] HVAC air loop object
  # @param oa_control [OpenStudio::Model::ControllerOutdoorAir] Outdoor air controller object to have this maximum OA fraction schedule
  # @param snc [String] System name
  #
  # @return [OpenStudio::Model::ScheduleRuleset] Generated maximum outdoor air fraction schedule for later use
  def set_maximum_fraction_outdoor_air_schedule(air_loop_hvac, oa_control, snc)
    max_oa_sch_name = "#{snc}_maxOASch"
    max_oa_sch = OpenStudio::Model::ScheduleRuleset.new(air_loop_hvac.model)
    max_oa_sch.setName(max_oa_sch_name)
    max_oa_sch.defaultDaySchedule.setName("#{max_oa_sch_name}_Default")
    max_oa_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.75)
    oa_control.setMaximumFractionofOutdoorAirSchedule(max_oa_sch)
    max_oa_sch
  end
end
