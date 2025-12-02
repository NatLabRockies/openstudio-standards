module OpenstudioStandards
  # The Weather module provides methods to set and get information for model weather files
  module Weather
    # @!group Modify

    # Set the model WeatherFile object from a parsed .epw file.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param epw_file [OpenStudio::EpwFile] OpenStudio EpwFile object
    # @return [OpenStudio::Model::WeatherFile] OpenStudio WeatherFile object
    def self.model_set_weather_file(model, epw_file)
      weather_file = OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file).get
      weather_file.setCity(epw_file.city)
      weather_file.setStateProvinceRegion(epw_file.stateProvinceRegion)
      weather_file.setCountry(epw_file.country)
      weather_file.setDataSource(epw_file.dataSource)
      weather_file.setWMONumber(epw_file.wmoNumber)
      weather_file.setLatitude(epw_file.latitude)
      weather_file.setLongitude(epw_file.longitude)
      weather_file.setTimeZone(epw_file.timeZone)
      weather_file.setElevation(epw_file.elevation)

      return weather_file
    end

    # Set the model Site object from a parsed .epw file.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param epw_file [OpenStudio::EpwFile] OpenStudio EpwFile object
    # @return [OpenStudio::Model::Site] OpenStudio Site object
    def self.model_set_site_information(model, epw_file)
      weather_name = "#{epw_file.city}_#{epw_file.stateProvinceRegion}_#{epw_file.country}"
      site = model.getSite
      site.setName(weather_name)
      site.setLatitude(epw_file.latitude)
      site.setLongitude(epw_file.longitude)
      site.setTimeZone(epw_file.timeZone)
      site.setElevation(epw_file.elevation)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.modify', "Set Site information to #{weather_name}.")

      return site
    end

    # Set the model SiteWaterMainsTemperature object from a parsed .stat file.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param stat_file [OpenstudioStandards::Weather::StatFile] parsed .stat file object
    # @return [OpenStudio::Model::SiteWaterMainsTemperature] OpenStudio SiteWaterMainsTemperature object
    def self.model_set_site_water_mains_temperature(model, stat_file: nil)
      # get .stat file from model if none provided
      if stat_file.nil?
        weather_file_path = model.getWeatherFile.path.get.to_s
        stat_file = OpenstudioStandards::Weather::StatFile.load(weather_file_path.sub('.epw', '.stat'))
      end

      # set site water mains temperature
      water_temp = model.getSiteWaterMainsTemperature
      water_temp.setAnnualAverageOutdoorAirTemperature(stat_file.mean_dry_bulb)
      water_temp.setMaximumDifferenceInMonthlyAverageOutdoorAirTemperatures(stat_file.delta_dry_bulb)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.modify', "Site Water Mains Temperature mean OA dry bulb is #{stat_file.mean_dry_bulb}. Delta OA dry bulb is #{stat_file.delta_dry_bulb}.")

      return water_temp
    end

    # Set the SiteGroundTemperatureShallow object based on undisturbed ground temperatures at 0.5m depth from the .stat file.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param stat_file [OpenstudioStandards::Weather::StatFile] parsed .stat file object
    # @return [OpenStudio::Model::SiteGroundTemperatureShallow] OpenStudio SiteGroundTemperatureShallow object
    def self.model_set_undisturbed_ground_temperature_shallow(model, stat_file: nil)
      # get .stat file from model if none provided
      if stat_file.nil?
        weather_file_path = model.getWeatherFile.path.get.to_s
        stat_file = OpenstudioStandards::Weather::StatFile.load(weather_file_path.sub('.epw', '.stat'))
      end

      if stat_file.monthly_undis_ground_temps_0p5m.empty?
        return false
      end

      # set ground temperature shallow values based on .stat file
      ground_temperature_shallow = model.getSiteGroundTemperatureShallow
      ground_temperature_shallow.setJanuarySurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[0])
      ground_temperature_shallow.setFebruarySurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[1])
      ground_temperature_shallow.setMarchSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[2])
      ground_temperature_shallow.setAprilSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[3])
      ground_temperature_shallow.setMaySurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[4])
      ground_temperature_shallow.setJuneSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[5])
      ground_temperature_shallow.setJulySurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[6])
      ground_temperature_shallow.setAugustSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[7])
      ground_temperature_shallow.setSeptemberSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[8])
      ground_temperature_shallow.setOctoberSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[9])
      ground_temperature_shallow.setNovemberSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[10])
      ground_temperature_shallow.setDecemberSurfaceGroundTemperature(stat_file.monthly_undis_ground_temps_0p5m[11])

      return ground_temperature_shallow
    end

    # Set the SiteGroundTemperatureDeep object based on undisturbed ground temperatures at 4.0m depth from the .stat file.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param stat_file [OpenstudioStandards::Weather::StatFile] parsed .stat file object
    # @return [OpenStudio::Model::SiteGroundTemperatureDeep] OpenStudio SiteGroundTemperatureDeep object
    def self.model_set_undisturbed_ground_temperature_deep(model, stat_file: nil)
      # get .stat file from model if none provided
      if stat_file.nil?
        weather_file_path = model.getWeatherFile.path.get.to_s
        stat_file = OpenstudioStandards::Weather::StatFile.load(weather_file_path.sub('.epw', '.stat'))
      end

      if stat_file.monthly_undis_ground_temps_4p0m.empty?
        return false
      end

      # set ground temperature deep values based on .stat file
      ground_temperature_deep = model.getSiteGroundTemperatureDeep
      ground_temperature_deep.setJanuaryDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[0])
      ground_temperature_deep.setFebruaryDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[1])
      ground_temperature_deep.setMarchDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[2])
      ground_temperature_deep.setAprilDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[3])
      ground_temperature_deep.setMayDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[4])
      ground_temperature_deep.setJuneDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[5])
      ground_temperature_deep.setJulyDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[6])
      ground_temperature_deep.setAugustDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[7])
      ground_temperature_deep.setSeptemberDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[8])
      ground_temperature_deep.setOctoberDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[9])
      ground_temperature_deep.setNovemberDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[10])
      ground_temperature_deep.setDecemberDeepGroundTemperature(stat_file.monthly_undis_ground_temps_4p0m[11])

      return ground_temperature_deep
    end

    # Set ground temperatures in the model.
    # The method will first attempt to find ground temperatures for the SiteGroundTemperatureFCfactorMethod object from the .stat file associated with the model .epw file. If it cannot find the .stat file, it will use values from the model climate zone or climate zone argument specified. If it still can't find ground temperatures, it will set default values for the SiteGroundTemperatureBuildingSurface object instead.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param climate_zone [String] full climate zone string, e.g. "ASHRAE 169-2013-4A"
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_ground_temperatures(model, climate_zone: nil)
      # look for .stat file from .epw file
      full_epw_path = nil
      stat_file_path = nil
      if model.weatherFile.is_initialized
        epw_path = model.weatherFile.get.path
        if epw_path.is_initialized
          if File.exist?(epw_path.get.to_s)
            full_epw_path = epw_path.get.to_s
          else
            # If this is an always-run Measure, need to check a different path
            alt_weath_path = File.expand_path(File.join(__dir__, '../../resources'))
            alt_epw_path = File.expand_path(File.join(alt_weath_path, epw_path.get.to_s))
            if File.exist?(alt_epw_path)
              full_epw_path = alt_epw_path
            end
          end
        end
      end

      if full_epw_path
        stat_file_path = full_epw_path.gsub('.epw', '.stat')
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.weather.Model', 'Could not locate the .epw file, cannot get ground temperatures from the associated .stat file.')
      end

      # if no .stat file found, lookup defaults based on the climate zone
      if stat_file_path.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.weather.Model', 'Could not locate the .stat file. Looking up default values based on the climate zone.')
        if climate_zone.nil?
          # attempt to get the climate zone from the model
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.weather.Model', 'Climate zone not provided. Looking up from model.')
          climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)
        end

        unless climate_zone.nil? || climate_zone.empty?
          # Define the weather file for each climate zone
          climate_zone_weather_file_map = OpenstudioStandards::Weather.climate_zone_weather_file_map
          # Get the weather file name from the hash
          weather_file_name = climate_zone_weather_file_map[climate_zone]
          if weather_file_name.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.weather.Model', "Could not determine the weather file for climate zone: #{climate_zone}, cannot get ground temperatures from .stat file.")
          else
            # Get the path to the stat file
            weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file_name)
            stat_file_path = weather_file_path.gsub('.epw', '.stat')
          end
        end
      end

      # load the lagged ground temperatures for the FC factor method from the .stat file
      stat_file = nil
      ground_temperatures = []
      if !stat_file_path.nil? && File.exist?(stat_file_path)
        stat_file = OpenstudioStandards::Weather::StatFile.load(stat_file_path)
        ground_temperatures = stat_file.monthly_lagged_dry_bulb

        # set the site ground temperature building surface
        ground_temp = model.getSiteGroundTemperatureFCfactorMethod
        ground_temp.setAllMonthlyTemperatures(ground_temperatures)
      end

      # use default surface values if FC factor method ground temperatures unavailable
      if ground_temperatures.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.weather.Model', 'Could not find ground temperatures from the .stat file. Will use generic SiteGroundTemperatureBuildingSurface temperatures, which will skew results.')
        ground_temp = model.getSiteGroundTemperatureBuildingSurface
        ground_temp.setJanuaryGroundTemperature(19.527)
        ground_temp.setFebruaryGroundTemperature(19.502)
        ground_temp.setMarchGroundTemperature(19.536)
        ground_temp.setAprilGroundTemperature(19.598)
        ground_temp.setMayGroundTemperature(20.002)
        ground_temp.setJuneGroundTemperature(21.640)
        ground_temp.setJulyGroundTemperature(22.225)
        ground_temp.setAugustGroundTemperature(22.375)
        ground_temp.setSeptemberGroundTemperature(21.449)
        ground_temp.setOctoberGroundTemperature(20.121)
        ground_temp.setNovemberGroundTemperature(19.802)
        ground_temp.setDecemberGroundTemperature(19.633)
      end
      return true
    end

    # Sets the model ClimateZone object.
    # Clears out any climate zones previously added to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param climate_zone [String] full climate zone string, e.g. "ASHRAE 169-2013-1A"
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_climate_zone(model, climate_zone)
      # Remove previous climate zones from the model
      climate_zones = model.getClimateZones
      climate_zones.clear

      # Split the string into the correct institution and value
      if climate_zone.include?('CEC')
        climate_zones.setClimateZone('CEC', climate_zone.gsub('CEC T24-CEC', '').gsub('T24-CEC', ''))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.modify', "Setting Climate Zone to #{climate_zones.getClimateZones('CEC').first.value}")
      elsif climate_zone.include?('ASHRAE')
        climate_zones.setClimateZone('ASHRAE', climate_zone.gsub(/ASHRAE .*-.*-/, ''))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.modify', "Setting Climate Zone to #{climate_zones.getClimateZones('ASHRAE').first.value}")
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.modify', "Unknown climate zone #{climate_zone}. Climate Zone will not be set.")
      end

      return true
    end

    # Set the model DesignDays from a .ddy file.
    # Can pass in a regular expression list to select design days.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param ddy_file_path [String] path to .ddy file
    # @param ddy_list [Array<Regexp>] list of regular expressions matching design day names to import.
    #  The default (nil) will add the annual heating 99.6% DB and annual cooling 0.4% DB and WB design days.
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_design_days(model,
                                   ddy_file_path: nil,
                                   ddy_list: nil)
      # if not ddy_list provided, use the annual heating 99.6% DB and annual cooling 0.4% DB design days
      if ddy_list.nil? || ddy_list.empty?
        ddy_list = [/Htg 99.6. Condns DB/, /Clg .4% Condns DB=>MWB/, /Clg 0.4% Condns DB=>MCWB/, /Clg .4. Condns WB=>MDB/]
      end

      # remove any existing design day objects
      model.getDesignDays.each(&:remove)

      # get .ddy file from model if none provided
      if ddy_file_path.nil?
        weather_file_path = model.getWeatherFile.path.get.to_s
        ddy_file_path = weather_file_path.sub('.epw', '.ddy')
      end

      unless File.file?(ddy_file_path)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.modify', "Could not find .ddy file: #{ddy_file_path}")
        return false
      end

      ddy_model = OpenStudio::EnergyPlus.loadAndTranslateIdf(ddy_file_path).get

      # warn if no design days in file
      if ddy_model.getDesignDays.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', 'No design days were found in the design day file.')
        return false
      end

      # add design days that match ddy_list regexes
      ddy_model.getDesignDays.sort.each do |d|
        ddy_list.each do |ddy_name_regex|
          if d.name.get.to_s =~ ddy_name_regex
            model.addObject(d)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.modify', "Added design day #{d.name}.")
          end
        end
      end

      # Check to ensure that some design days were added
      if model.getDesignDays.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.modify', "No design days were loaded, check syntax of .ddy file: #{ddy_file_path}.")
        return false
      end

      return true
    end

    # Set the model weather file, site information, climate zone, and design days based on a weather file or climate zone.
    # Either the weather_file_path or the climate_zone argument must be specified.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param weather_file_path [String] absolute path to the .epw file. For weather files included in openStudio-standards, can be found using OpenstudioStandards::Weather::get_standards_weather_file_path(weather_file_name)
    # @param climate_zone [String] full climate zone string, e.g. 'ASHRAE 169-2013-4A'
    # @param ddy_list [Array<Regexp>] list of regexes to match design day names to add to model, e.g. /Clg 1. Condns DB=>MWB/.
    #  The default (nil) will add the annual heating 99.6% DB and annual cooling 0.4% DB and WB design days.
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_weather_file_and_design_days(model,
                                                    weather_file_path: nil,
                                                    climate_zone: nil,
                                                    ddy_list: nil)
      # check that either weather_file_path or climate_zone provided
      if weather_file_path.nil? && climate_zone.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', 'model_set_weather_file_and_design_days must be called with either the weather_file_path or climate_zone argument specified.')
        return false
      end

      # load weather file if specified
      if weather_file_path.nil?
        # look up the standard weather file for the climate zone
        weather_file_path = OpenstudioStandards::Weather.climate_zone_representative_weather_file_path(climate_zone)
        epw_file = OpenStudio::EpwFile.new(weather_file_path)
      else
        epw_file = OpenStudio::EpwFile.new(weather_file_path)
      end

      # set weather file and site information
      OpenstudioStandards::Weather.model_set_weather_file(model, epw_file)
      OpenstudioStandards::Weather.model_set_site_information(model, epw_file)

      # set design days from the .ddy file
      ddy_file_path = weather_file_path.gsub('.epw', '.ddy')
      OpenstudioStandards::Weather.model_set_design_days(model, ddy_file_path: ddy_file_path, ddy_list: ddy_list)

      # set the climate zone
      if climate_zone.nil? || climate_zone.empty?
        # attempt to use the climate zone from the stat file
        stat_file_climate_zone = nil
        stat_file_path = weather_file_path.gsub('.epw', '.stat')
        if File.file?(stat_file_path)
          stat_file = OpenstudioStandards::Weather::StatFile.load(stat_file_path)
          stat_file_climate_zone = stat_file.climate_zone
        end

        if stat_file_climate_zone.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', 'Could not determine and set the climate zone.')
        else
          climate_zone = "ASHRAE 169-2013-#{stat_file_climate_zone}"
          OpenstudioStandards::Weather.model_set_climate_zone(model, climate_zone)
        end
      else
        OpenstudioStandards::Weather.model_set_climate_zone(model, climate_zone)
      end
    end

    # Set the model weather file, site information, climate zone, design days, site water main temperatures, undisturbed ground temperatures, and ground temperatures based on a weather file or climate zone.
    # Either the weather_file_path or the climate_zone argument must be specified.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param weather_file_path [String] absolute path to the .epw file. For weather files included in openStudio-standards, can be found using OpenstudioStandards::Weather::get_standards_weather_file_path(weather_file_name)
    # @param climate_zone [String] full climate zone string, e.g. 'ASHRAE 169-2013-4A'
    # @param ddy_list [Array<Regexp>] list of regexes to match design day names to add to model, e.g. /Clg 1. Condns DB=>MWB/
    #  The default (nil) will add the annual heating 99.6% DB and annual cooling 0.4% DB and WB design days.
    # @return [Boolean] returns true if successful, false if not
    def self.model_set_building_location(model,
                                         weather_file_path: nil,
                                         climate_zone: nil,
                                         ddy_list: nil)
      # check that either weather_file_path or climate_zone provided
      if weather_file_path.nil? && climate_zone.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', "#{__method__} must be called with either the weather_file_path or climate_zone argument specified.")
        return false
      end

      # load weather file if specified
      if weather_file_path.nil?
        # look up the standard weather file for the climate zone
        weather_file_path = OpenstudioStandards::Weather.climate_zone_representative_weather_file_path(climate_zone)
        epw_file = OpenStudio::EpwFile.new(weather_file_path)
      else
        epw_file = OpenStudio::EpwFile.new(weather_file_path)
      end

      # set the model weather file, site information, climate zone, and design days
      OpenstudioStandards::Weather.model_set_weather_file_and_design_days(model,
                                                                          weather_file_path: weather_file_path,
                                                                          climate_zone: climate_zone,
                                                                          ddy_list: ddy_list)

      # set site water mains and undisturbed ground temperatures from the .stat file
      stat_file_climate_zone = nil
      stat_file_path = weather_file_path.gsub('.epw', '.stat')
      if File.file?(stat_file_path)
        stat_file = OpenstudioStandards::Weather::StatFile.load(stat_file_path)
        OpenstudioStandards::Weather.model_set_site_water_mains_temperature(model, stat_file: stat_file)
        if !OpenstudioStandards::Weather.model_set_undisturbed_ground_temperature_shallow(model, stat_file: stat_file)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', "Could not find undisturbed shallow ground temps in .stat file at #{stat_file_path}. Unable to set undisturbed ground temperatures.")
        end

        if !OpenstudioStandards::Weather.model_set_undisturbed_ground_temperature_deep(model, stat_file: stat_file)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', "Could not find undisturbed deep ground temps in .stat file at #{stat_file_path}. Unable to set undisturbed ground temperatures.")
        end

        stat_file_climate_zone = stat_file.climate_zone
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.modify', "Could not find .stat file at #{stat_file_path}. Unable to set site water mains temperature and undisturbed ground temperatures.")
      end

      # set the model ground temperatures
      OpenstudioStandards::Weather.model_set_ground_temperatures(model, climate_zone: climate_zone)

      return true
    end

    # @!endgroup Modify
  end
end
