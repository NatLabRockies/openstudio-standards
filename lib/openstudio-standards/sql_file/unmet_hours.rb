module OpenstudioStandards
  # The SqlFile module provides methods to get information from the EnergyPlus .sql file after a run
  module SqlFile
    # @!group Unmet Hours

    # Gets the annual occupied unmet heating hours from zone temperature time series in the sql file
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param tolerance [Double] tolerance in degrees Rankine to log an unmet hour
    # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
    # @return [Hash] Hash with 'sum' of heating unmet hours and 'zone_temperature_differences' of all zone unmet hours data
    # @todo account for operative temperature thermostats
    def self.model_get_annual_occupied_unmet_heating_hours_detailed(model, tolerance: 1.0, occupied_percentage_threshold: 0.05)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SqlFile', "Calculating zone heating occupied unmet hours with #{tolerance} R tolerance.  This may take some time.")
      # get model sql file
      sql_file = OpenstudioStandards::SqlFile.model_get_sql_file(model)

      # std to access thermal zone methods. Replace when thermal zone methods are moved to modules
      std = Standard.build('90.1-2013')

      # convert tolerance to Kelvin
      tolerance_k = OpenStudio.convert(tolerance, 'R', 'K').get

      ann_env_pd = OpenstudioStandards::SqlFile.model_get_weather_run_period(model)
      unless ann_env_pd
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', 'Could not get annual run period.')
        return false
      end

      # for each zone calculate unmet hours and store in array
      bldg_unmet_hours = []
      bldg_occ_unmet_hours = []
      zone_data = []
      model.getThermalZones.each do |zone|
        # skip zones that aren't heated
        next unless OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone)

        # get zone air temperatures
        zone_temp_timeseries = sql_file.timeSeries(ann_env_pd, 'Hourly', 'Zone Air Temperature', zone.name.get)
        if zone_temp_timeseries.empty?
          # try mean air temperature instead
          zone_temp_timeseries = sql_file.timeSeries(ann_env_pd, 'Hourly', 'Zone Mean Air Temperature', zone.name.get)
          if zone_temp_timeseries.empty?
            # no air temperature found
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', "Could not find zone air temperature timeseries for zone '#{zone.name.get}'")
            return false
          end
        end
        zone_temp_timeseries = zone_temp_timeseries.get.values

        # get zone thermostat heating setpoint temperatures
        zone_setpoint_temp_timeseries = sql_file.timeSeries(ann_env_pd, 'Hourly', 'Zone Thermostat Heating Setpoint Temperature', zone.name.get)
        if zone_setpoint_temp_timeseries.empty?
          # no setpoint temperature found
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', "Could not find heating setpoint temperature timeseries for zone '#{zone.name.get}'")
          return false
        end
        zone_setpoint_temp_timeseries = zone_setpoint_temp_timeseries.get.values

        # calculate zone occupancy by making a new ruleset schedule
        occ_schedule_ruleset = OpenstudioStandards::ThermalZone.thermal_zone_get_occupancy_schedule(zone)
        occ_values = OpenstudioStandards::Schedules.schedule_ruleset_get_hourly_values(occ_schedule_ruleset)

        # calculate difference accounting for unmet hours tolerance
        zone_temperature_diff = zone_setpoint_temp_timeseries.map.with_index { |t, x| (zone_temp_timeseries[x] - t) }
        zone_unmet_hours = zone_temperature_diff.map { |x| (x + tolerance_k) < 0 ? 1 : 0 }
        zone_occ_unmet_hours = []
        for i in (0..zone_unmet_hours.size - 1)
          bldg_unmet_hours[i] = 0 if bldg_unmet_hours[i].nil?
          bldg_occ_unmet_hours[i] = 0 if bldg_occ_unmet_hours[i].nil?
          bldg_unmet_hours[i] += zone_unmet_hours[i]
          if occ_values[i] >= occupied_percentage_threshold
            zone_occ_unmet_hours[i] = zone_unmet_hours[i]
            bldg_occ_unmet_hours[i] += zone_unmet_hours[i]
          else
            zone_occ_unmet_hours[i] = 0
          end
        end

        # log information for zone
        # could reduce the number of returned variables if this poses a storage or data transfer problem
        zone_data << {
          'zone_name' => zone.name,
          'zone_area' => zone.floorArea,
          'zone_air_temperatures' => zone_temp_timeseries.map { |t| t.round(3) },
          'zone_air_setpoint_temperatures' => zone_setpoint_temp_timeseries.map { |t| t.round(3) },
          'zone_air_temperature_differences' => zone_temperature_diff.map { |d| d.round(3) },
          'zone_occupancy' => occ_values.map { |x| x.round(3) },
          'zone_unmet_hours' => zone_unmet_hours,
          'zone_occupied_unmet_hours' => zone_occ_unmet_hours,
          'sum_zone_unmet_hours' => zone_unmet_hours.count { |x| x > 0 },
          'sum_zone_occupied_unmet_hours' => zone_occ_unmet_hours.count { |x| x > 0 }
        }
      end

      occupied_unmet_heating_hours_detailed = { 'sum_bldg_unmet_hours' => bldg_unmet_hours.count { |x| x > 0 },
                                                'sum_bldg_occupied_unmet_hours' => bldg_occ_unmet_hours.count { |x| x > 0 },
                                                'bldg_unmet_hours' => bldg_unmet_hours,
                                                'bldg_occupied_unmet_hours' => bldg_occ_unmet_hours,
                                                'zone_data' => zone_data }
      return occupied_unmet_heating_hours_detailed
    end

    # Gets the annual occupied unmet cooling hours from zone temperature time series in the sql file
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
    # @param tolerance [Double] tolerance in degrees Rankine to log an unmet hour
    # @return [Hash] Hash with 'sum' of cooling unmet hours and 'zone_temperature_differences' of all zone unmet hours data
    # @todo account for operative temperature thermostats
    def self.model_get_annual_occupied_unmet_cooling_hours_detailed(model, tolerance: 1.0, occupied_percentage_threshold: 0.05)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SqlFile', "Calculating zone cooling occupied unmet hours with #{tolerance} R tolerance. This may take some time.")
      # get model sql file
      sql_file = OpenstudioStandards::SqlFile.model_get_sql_file(model)

      # std to access thermal zone methods. Replace when thermal zone methods are moved to modules
      std = Standard.build('90.1-2013')

      # convert tolerance to Kelvin
      tolerance_k = OpenStudio.convert(tolerance, 'R', 'K').get

      ann_env_pd = OpenstudioStandards::SqlFile.model_get_weather_run_period(model)
      unless ann_env_pd
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', 'Could not get annual run period.')
        return false
      end

      # for each zone calculate unmet hours and store in array
      bldg_unmet_hours = []
      bldg_occ_unmet_hours = []
      zone_data = []
      model.getThermalZones.each do |zone|
        # skip zones that aren't cooled
        next unless OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)

        # get zone air temperatures
        zone_temp_timeseries = sql_file.timeSeries(ann_env_pd, 'Hourly', 'Zone Air Temperature', zone.name.get)
        if zone_temp_timeseries.empty?
          # try mean air temperature instead
          zone_temp_timeseries = sql_file.timeSeries(ann_env_pd, 'Hourly', 'Zone Mean Air Temperature', zone.name.get)
          if zone_temp_timeseries.empty?
            # no air temperature found
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', "Could not find zone air temperature timeseries for zone '#{zone.name.get}'")
            return false
          end
        end
        zone_temp_timeseries = zone_temp_timeseries.get.values

        # get zone thermostat heating setpoint temperatures
        zone_setpoint_temp_timeseries = sql_file.timeSeries(ann_env_pd, 'Hourly', 'Zone Thermostat Cooling Setpoint Temperature', zone.name.get)
        if zone_setpoint_temp_timeseries.empty?
          # no setpoint temperature found
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', "Could not find cooling setpoint temperature timeseries for zone '#{zone.name.get}'")
          return false
        end
        zone_setpoint_temp_timeseries = zone_setpoint_temp_timeseries.get.values

        # calculate zone occupancy by making a new ruleset schedule
        occ_schedule_ruleset = OpenstudioStandards::ThermalZone.thermal_zone_get_occupancy_schedule(zone)
        occ_values = OpenstudioStandards::Schedules.schedule_ruleset_get_hourly_values(occ_schedule_ruleset)

        # calculate difference accounting for unmet hours tolerance
        zone_temperature_diff = zone_setpoint_temp_timeseries.map.with_index { |t, x| (t - zone_temp_timeseries[x]) }
        zone_unmet_hours = zone_temperature_diff.map { |x| (x - tolerance_k) > 0 ? 1 : 0 }
        zone_occ_unmet_hours = []
        for i in (0..zone_unmet_hours.size - 1)
          bldg_unmet_hours[i] = 0 if bldg_unmet_hours[i].nil?
          bldg_occ_unmet_hours[i] = 0 if bldg_occ_unmet_hours[i].nil?
          bldg_unmet_hours[i] += zone_unmet_hours[i]
          if occ_values[i] >= occupied_percentage_threshold
            zone_occ_unmet_hours[i] = zone_unmet_hours[i]
            bldg_occ_unmet_hours[i] += zone_unmet_hours[i]
          else
            zone_occ_unmet_hours[i] = 0
          end
        end

        # log information for zone
        # could reduce the number of returned variables if this poses a storage or data transfer problem
        zone_data << {
          'zone_name' => zone.name,
          'zone_area' => zone.floorArea,
          'zone_air_temperatures' => zone_temp_timeseries.map { |t| t.round(3) },
          'zone_air_setpoint_temperatures' => zone_setpoint_temp_timeseries.map { |t| t.round(3) },
          'zone_air_temperature_differences' => zone_temperature_diff.map { |d| d.round(3) },
          'zone_occupancy' => occ_values.map { |x| x.round(3) },
          'zone_unmet_hours' => zone_unmet_hours,
          'zone_occupied_unmet_hours' => zone_occ_unmet_hours,
          'sum_zone_unmet_hours' => zone_unmet_hours.count { |x| x > 0 },
          'sum_zone_occupied_unmet_hours' => zone_occ_unmet_hours.count { |x| x > 0 }
        }
      end

      occupied_unmet_cooling_hours_detailed = { 'sum_bldg_unmet_hours' => bldg_unmet_hours.count { |x| x > 0 },
                                                'sum_bldg_occupied_unmet_hours' => bldg_occ_unmet_hours.count { |x| x > 0 },
                                                'bldg_unmet_hours' => bldg_unmet_hours,
                                                'bldg_occupied_unmet_hours' => bldg_occ_unmet_hours,
                                                'zone_data' => zone_data }
      return occupied_unmet_cooling_hours_detailed
    end

    # Gets the annual occupied unmet heating hours from the sql file
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param tolerance [Double] tolerance in degrees Rankine to log an unmet hour
    #   If this is unspecified, the tolerance will be the tolerance specified in OutputControl:ReportingTolerances.
    #   If there isn't an OutputControl:ReportingTolerances object, the EnergyPlus default is 0.2 degrees Kelvin.
    #   If a tolerance is defined and does not match the tolerance defined in OutputControl:ReportingTolerances,
    #   this method will compare the zone temperature and setpoint temperature timeseries for each zone.
    #   Generally, it is much faster to define tolerances with the OutputControl:ReportingTolerances object.
    # @return [Double] occupied heating unmet hours
    def self.model_get_annual_occupied_unmet_heating_hours(model, tolerance: nil)
      reporting_tolerances = model.getOutputControlReportingTolerances
      model_tolerance = reporting_tolerances.toleranceforTimeHeatingSetpointNotMet
      model_tolerance_r = OpenStudio.convert(model_tolerance, 'K', 'R')

      # get model sql file
      sql_file = OpenstudioStandards::SqlFile.model_get_sql_file(model)

      use_detailed = false
      unless tolerance.nil?
        # check to see if input argument tolerance matches model tolerance
        tolerance_k = OpenStudio.convert(tolerance, 'R', 'K').get
        unless (model_tolerance - tolerance_k).abs < 1e-3
          # input argument tolerance does not match model tolerance; need to recalculate unmet hours
          use_detailed = true
        end
      end

      if use_detailed
        # calculate unmet hours for each zone using zone time series
        zones_unmet_hours = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours_detailed(model, tolerance: tolerance)
        heating_unmet_hours = zones_unmet_hours['sum_bldg_occupied_unmet_hours']
      else
        # use default EnergyPlus unmet hours reporting
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SqlFile', "Calculating heating unmet hours with #{model_tolerance_r} R tolerance")

        # setup the queries
        heating_setpoint_unmet_query = "SELECT Value
                                      FROM TabularDataWithStrings
                                      WHERE ReportName='SystemSummary'
                                      AND ReportForString='Entire Facility'
                                      AND TableName='Time Setpoint Not Met'
                                      AND RowName = 'Facility'
                                      AND ColumnName='During Occupied Heating'"
        # get the info
        heating_setpoint_unmet = sql_file.execAndReturnFirstDouble(heating_setpoint_unmet_query)

        # make sure all the data are available
        if heating_setpoint_unmet.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', 'Could not get unmet heating hours information.')
          return false
        end

        heating_unmet_hours = heating_setpoint_unmet.get
      end

      return heating_unmet_hours
    end

    # Gets the annual occupied unmet cooling hours from the sql file
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param tolerance [Double] tolerance in degrees Rankine to log an unmet hour
    #   If this is unspecified, the tolerance will be the tolerance specified in OutputControl:ReportingTolerances.
    #   If there isn't an OutputControl:ReportingTolerances object, the EnergyPlus default is 0.2 degrees Kelvin.
    #   If a tolerance is defined and does not match the tolerance defined in OutputControl:ReportingTolerances,
    #   this method will compare the zone temperature and setpoint temperature timeseries for each zone.
    #   Generally, it is much faster to define tolerances with the OutputControl:ReportingTolerances object.
    # @return [Double] occupied cooling unmet hours
    def self.model_get_annual_occupied_unmet_cooling_hours(model, tolerance: nil)
      reporting_tolerances = model.getOutputControlReportingTolerances
      model_tolerance = reporting_tolerances.toleranceforTimeHeatingSetpointNotMet
      model_tolerance_r = OpenStudio.convert(model_tolerance, 'K', 'R')

      # get model sql file
      sql_file = OpenstudioStandards::SqlFile.model_get_sql_file(model)

      use_detailed = false
      unless tolerance.nil?
        # check to see if input argument tolerance matches model tolerance
        tolerance_k = OpenStudio.convert(tolerance, 'R', 'K').get
        unless (model_tolerance - tolerance_k).abs < 1e-3
          # input argument tolerance does not match model tolerance; need to recalculate unmet hours
          use_detailed = true
        end
      end

      if use_detailed
        # calculate unmet hours for each zone using zone time series
        zones_unmet_hours = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours_detailed(model, tolerance: tolerance)
        cooling_unmet_hours = zones_unmet_hours['sum_bldg_occupied_unmet_hours']
      else
        # use default EnergyPlus unmet hours reporting
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.SqlFile', "Calculating cooling unmet hours with #{model_tolerance_r} R tolerance")

        # setup the queries
        cooling_setpoint_unmet_query = "SELECT Value
                                      FROM TabularDataWithStrings
                                      WHERE ReportName='SystemSummary'
                                      AND ReportForString='Entire Facility'
                                      AND TableName='Time Setpoint Not Met'
                                      AND RowName = 'Facility'
                                      AND ColumnName='During Occupied Cooling'"
        # get the info
        cooling_setpoint_unmet = sql_file.execAndReturnFirstDouble(cooling_setpoint_unmet_query)

        # make sure all the data are available
        if cooling_setpoint_unmet.empty?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', 'Could not get unmet cooling hours information.')
          return false
        end

        cooling_unmet_hours = cooling_setpoint_unmet.get
      end

      return cooling_unmet_hours
    end

    # Gets the annual occupied unmet hours from the sql file
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Double, Boolean] the total number of unmet heating or cooling hours, or false if results are missing
    def self.model_get_annual_occupied_unmet_hours(model)
      heating_setpoint_unmet = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours(model)
      cooling_setpoint_unmet = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours(model)
      return false unless heating_setpoint_unmet && cooling_setpoint_unmet

      # aggregate heating and cooling hrs
      heating_or_cooling_setpoint_unmet = heating_setpoint_unmet + cooling_setpoint_unmet

      return heating_or_cooling_setpoint_unmet
    end

    # Determine the number of unmet occupied heating load hours for a thermal zone
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Double] occupied heating unmet hours
    def self.thermal_zone_get_annual_occupied_unmet_heating_hours(thermal_zone)
      # get the model sql file
      sql_file = OpenstudioStandards::SqlFile.model_get_sql_file(thermal_zone.model)

      # run unmet load hours query for the specific thermal zone
      query = "SELECT Value
              FROM tabulardatawithstrings
              WHERE ReportName='SystemSummary'
              AND ReportForString='Entire Facility'
              AND TableName='Time Setpoint Not Met'
              AND ColumnName='During Occupied Heating'
              AND RowName='#{thermal_zone.name.to_s.upcase}'
              AND Units='hr'"
      umlh = sql_file.execAndReturnFirstDouble(query)
      if umlh.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', "Could not get unmet occupied heating hours for thermal zone #{thermal_zone.name}.")
        return false
      end

      return umlh.get
    end

    # Determine the number of unmet occupied cooling load hours for a thermal zone
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Double] occupied cooling unmet hours
    def self.thermal_zone_get_annual_occupied_unmet_cooling_hours(thermal_zone)
      # get the model sql file
      sql_file = OpenstudioStandards::SqlFile.model_get_sql_file(thermal_zone.model)

      # run unmet load hours query for the specific thermal zone
      query = "SELECT Value
              FROM tabulardatawithstrings
              WHERE ReportName='SystemSummary'
              AND ReportForString='Entire Facility'
              AND TableName='Time Setpoint Not Met'
              AND ColumnName='During Occupied Cooling'
              AND RowName='#{thermal_zone.name.to_s.upcase}'
              AND Units='hr'"
      umlh = sql_file.execAndReturnFirstDouble(query)
      if umlh.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.SqlFile', "Could not get unmet occupied cooling hours for thermal zone #{thermal_zone.name}.")
        return false
      end

      return umlh.get
    end

    # @!endgroup UnmetHours
  end
end
