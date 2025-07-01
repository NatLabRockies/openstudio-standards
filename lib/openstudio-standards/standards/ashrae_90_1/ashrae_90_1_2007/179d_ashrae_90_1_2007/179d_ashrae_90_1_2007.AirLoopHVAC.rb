class ACM179dASHRAE9012007
  # @!group AirLoopHVAC

  def air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac, climate_zone)
    return false  # TODO: for testing only
  end

# Check if an air loop in user model needs to have DCV per air loop related requiremends in ASHRAE 90.1-2019 6.4.3.8
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] flag of whether air loop in user model is required to have DCV
  def user_model_air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac)
    return false  # TODO: for testing only

    # all zones in the same airloop in user model are set with the same value, so use the first zone under the loop
    dcv_airloop_user_exception = air_loop_hvac.thermalZones[0].additionalProperties.getFeatureAsBoolean('airloop user specified DCV exception').get
    return false if dcv_airloop_user_exception

    # check the following conditions at airloop level
    # has air economizer OR design outdoor airflow > 3000 cfm

    has_economizer = air_loop_hvac_economizer?(air_loop_hvac)

    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_flow_m3_per_s = get_airloop_hvac_design_oa_from_sql(air_loop_hvac)
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, DCV not applicable because it has no OA intake.")
      return false
    end
    # oa_flow_m3_per_s can be false if the sizing run failed or sql not avail
    if oa_flow_m3_per_s != false
      puts "oa_flow_m3_per_s: #{oa_flow_m3_per_s}"
      oa_flow_cfm = OpenStudio.convert(oa_flow_m3_per_s, 'm^3/s', 'cfm').get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, DCV not applicable because oa_flow_m3_per_s is FALSE.")
      return false
    end
    any_zones_req_dcv = false
    air_loop_hvac.thermalZones.sort.each do |zone|
      if user_model_zone_demand_control_ventilation_required?(zone)
        any_zones_req_dcv = true
        break
      end
    end

    return true if any_zones_req_dcv && (has_economizer || (oa_flow_cfm > 3000))

    return false
  end

  # Check if a zone in user model needs to have DCV per zone related requiremends in ASHRAE 90.1-2019 6.4.3.8
  # @author Xuechen (Jerry) Lei, PNNL
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
  # @return [Boolean] flag of whether thermal zone in user model is required to have DCV
  def user_model_zone_demand_control_ventilation_required?(thermal_zone)
    dcv_zone_user_exception = thermal_zone.additionalProperties.getFeatureAsBoolean('zone user specified DCV exception').get
    return false if dcv_zone_user_exception

    # check the following conditions at zone level
    # zone > 500 sqft AND design occ > 25 ppl/ksqft

    area_served_m2 = 0
    num_people = 0
    thermal_zone.spaces.each do |space|
      area_served_m2 += space.floorArea
      num_people += space.numberOfPeople
    end
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get
    occ_per_1000_ft2 = num_people / area_served_ft2 * 1000

    return true if (area_served_ft2 > 500) && (occ_per_1000_ft2 > 25)

    return false
  end

  # Check if the air loop in baseline model needs to have DCV
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] flag of whether the air loop in baseline is required to have DCV
  def baseline_air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac)
    any_zone_req_dcv = false
    air_loop_hvac.thermalZones.each do |zone|
      if baseline_thermal_zone_demand_control_ventilation_required?(zone)
        any_zone_req_dcv = true
      end
    end
    return any_zone_req_dcv # baseline airloop needs dcv if any zone it serves needs dcv
  end

  # Check if the thermal zone in baseline model needs to have DCV
  #
  # @author Xuechen (Jerry) Lei, PNNL
  # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
  # @return [Boolean] flag of whether thermal zone in baseline is required to have DCV
  def baseline_thermal_zone_demand_control_ventilation_required?(thermal_zone)
    # zone needs dcv if user model has dcv and baseline does not meet apxg exception
    if thermal_zone.additionalProperties.hasFeature('apxg no need to have DCV')
      # meaning it was served by an airloop in the user model, does not mean much here, conditional as a safeguard
      # in case it was not served by an airloop in the user model
      if !thermal_zone.additionalProperties.getFeatureAsBoolean('apxg no need to have DCV').get && # does not meet apxg exception (need to have dcv if user model has it
         thermal_zone.additionalProperties.getFeatureAsBoolean('zone DCV implemented in user model').get
        return true
      end
    end
    return false
  end

  # Get the air loop HVAC design outdoor air flow rate by reading Standard 62.1 Summary from the sizing sql
  # @author Xuechen (Jerry) Lei, PNNL
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Double] Design outdoor air flow rate (m^3/s)
  def get_airloop_hvac_design_oa_from_sql(air_loop_hvac)
    return false unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
    return false unless air_loop_hvac.model.sqlFile.is_initialized
    cooling_oa = air_loop_hvac.model.sqlFile.get.execAndReturnFirstDouble(
      "SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName = 'System Ventilation Requirements for Cooling' AND ColumnName LIKE 'Outdoor Air Intake Flow%Vot' AND RowName='#{air_loop_hvac.name.to_s.upcase}'"
    )
    heating_oa = air_loop_hvac.model.sqlFile.get.execAndReturnFirstDouble(
      "SELECT Value FROM TabularDataWithStrings WHERE ReportName='Standard62.1Summary' AND ReportForString='Entire Facility' AND TableName = 'System Ventilation Requirements for Heating' AND ColumnName LIKE 'Outdoor Air Intake Flow%Vot' AND RowName='#{air_loop_hvac.name.to_s.upcase}'"
    )
    return [cooling_oa.to_f, heating_oa.to_f].max
  end

  # Set the minimum VAV damper positions.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param has_ddc [Boolean] if true, will assume that there is DDC control of vav terminals.
  #   If false, assumes otherwise.
  # @return [Boolean] returns true if successful, false if not
  def air_loop_hvac_apply_minimum_vav_damper_positions(air_loop_hvac, has_ddc = true)
    air_loop_hvac.thermalZones.each do |zone|
      zone.equipment.each do |equip|
        if equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
          zone_oa = thermal_zone_outdoor_airflow_rate(zone)
          vav_terminal = equip.to_AirTerminalSingleDuctVAVReheat.get
          air_terminal_single_duct_vav_reheat_apply_minimum_damper_position(vav_terminal, zone_oa, has_ddc)
        elsif equip.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized
          zone_oa = thermal_zone_outdoor_airflow_rate(zone)
          fp_vav_terminal = equip.to_AirTerminalSingleDuctParallelPIUReheat.get
          air_terminal_single_duct_parallel_piu_reheat_apply_minimum_primary_airflow_fraction(fp_vav_terminal, zone_oa)
        end
      end
    end

    return true
  end
  # Set default fan curve to be VSD with static pressure reset
  # NOTE: 179D overrides it because we want the use the proper fan coefs,
  # and not the ones from 'Multi Zone VAV with VSD and SP Setpoint Reset'
  # @return [string] name of appropriate curve for this code version
  def air_loop_hvac_set_vsd_curve_type
    return 'Multi Zone VAV with VSD and Fixed SP Setpoint'
  end

end
