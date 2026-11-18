class ASHRAE9012022 < ASHRAE901
  # @!group Space

  # Determine if a space should be modeled with an occupancy standby mode
  #
  # @param space [OpenStudio::Model::Space] OpenStudio Space object
  # @return [Boolean] true if occupancy standby mode is to be modeled, false otherwise
  def space_occupancy_standby_mode_required?(space)
    # Get space type
    return false if space.spaceType.empty?

    space_type = space.spaceType.get

    # Get standards space type
    return false if space_type.standardsSpaceType.empty?

    std_space_type = space_type.standardsSpaceType.get

    # Space with standby mode are determined based
    # on note H in Std 62.1 and their automatic partial
    # of full off lighting control requirement in 90.1.
    # In 90.1-2022/62.1-2016 this comes down to office
    # spaces (enclosed =< 250 ft2) and conference/meeting
    # and multipurpose rooms.
    # Currently standards doesn't excatly use the 90.1
    # space description so all spaces types that include
    # office/meeting/conference are flagged as having
    # occupant standby mode.
    if std_space_type.downcase.include?('office') || std_space_type.downcase.include?('meeting') || std_space_type.downcase.include?('conference')
      return true
    end

    return false
  end

  # Modify thermostat schedule to account for a thermostat setback/up
  #
  # @param thermostat [OpenStudio::Model::ThermostatSetpointDualSetpoint] OpenStudio ThermostatSetpointDualSetpoint object
  # @return [Boolean] returns true if successful, false if not
  def space_occupancy_standby_mode(thermostat)
    htg_sch = thermostat.getHeatingSchedule.get
    clg_sch = thermostat.getCoolingSchedule.get

    # Setback heating schedule
    # Setback is 1 deg. F per code requirement
    # Time of the day is arbitrary lack of dynamic occupant modeling
    setup = 1 # deg. F
    htg_sch_mod = { '12' => -1 * OpenStudio.convert(setup, 'R', 'K').get }
    htg_sch_name = "#{htg_sch.name} - occupant standby mode"
    htg_sch_old = thermostat.model.getScheduleRulesetByName(htg_sch_name)
    if htg_sch_old.empty?
      htg_sch_offset = model_offset_schedule_value(htg_sch, htg_sch_mod)
      htg_sch_offset.setName(htg_sch_name)
      thermostat.setHeatingSchedule(htg_sch_offset)
    else
      thermostat.setHeatingSchedule(htg_sch_old.get)
    end

    # Setup cooling schedule
    # Setup is 1 deg. F per code requirement
    # Time of the day is arbitrary lack of dynamic occupant modeling
    setback = 1 # deg. F
    clg_sch_mod = { '12' => OpenStudio.convert(setback, 'R', 'K').get }
    clg_sch_name = "#{clg_sch.name} - occupant standby mode"
    clg_sch_old = thermostat.model.getScheduleRulesetByName(clg_sch_name)
    if clg_sch_old.empty?
      clg_sch_offset = model_offset_schedule_value(clg_sch, clg_sch_mod)
      clg_sch_offset.setName(clg_sch_name)
      thermostat.setCoolingSchedule(clg_sch_offset)
    else
      thermostat.setCoolingSchedule(clg_sch_old.get)
    end

    return true
  end
end
