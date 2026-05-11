module OpenstudioStandards
  # The Weather module provides methods to set and get information for model weather files
  module Weather
    # @!group Information

    # A method to return an array of .epw files names mapped to each climate zone.
    #
    # @param epw_file [String] optional epw_file name for NECB methods
    # @return [Hash] a hash of climate zone weather file pairs
    def self.climate_zone_weather_file_map(epw_file = '')
      # Define the weather file for each climate zone
      climate_zone_weather_file_map = {
        'ASHRAE 169-2006-0A' => 'VNM_SVN_Ho.Chi.Minh-Tan.Son.Nhat.Intl.AP.489000_TMYx.epw',
        'ASHRAE 169-2006-0B' => 'ARE_DU_Dubai.Intl.AP.411940_TMYx.epw',
        'ASHRAE 169-2006-1A' => 'USA_FL_Miami.Intl.AP.722020_TMY3.epw',
        'ASHRAE 169-2006-1B' => 'SAU_RI_Riyadh.AB.404380_TMYx.epw',
        'ASHRAE 169-2006-2A' => 'USA_TX_Houston-Bush.Intercontinental.AP.722430_TMY3.epw',
        'ASHRAE 169-2006-2B' => 'USA_AZ_Phoenix-Sky.Harbor.Intl.AP.722780_TMY3.epw',
        'ASHRAE 169-2006-3A' => 'USA_TN_Memphis.Intl.AP.723340_TMY3.epw',
        'ASHRAE 169-2006-3B' => 'USA_TX_El.Paso.Intl.AP.722700_TMY3.epw',
        'ASHRAE 169-2006-3C' => 'USA_CA_San.Francisco.Intl.AP.724940_TMY3.epw',
        'ASHRAE 169-2006-4A' => 'USA_MD_Baltimore-Washington.Intl.AP.724060_TMY3.epw',
        'ASHRAE 169-2006-4B' => 'USA_NM_Albuquerque.Intl.AP.723650_TMY3.epw',
        'ASHRAE 169-2006-4C' => 'USA_OR_Salem-McNary.Field.726940_TMY3.epw',
        'ASHRAE 169-2006-5A' => 'USA_IL_Chicago-OHare.Intl.AP.725300_TMY3.epw',
        'ASHRAE 169-2006-5B' => 'USA_ID_Boise.Air.Terminal.726810_TMY3.epw',
        'ASHRAE 169-2006-5C' => 'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',
        'ASHRAE 169-2006-6A' => 'USA_VT_Burlington.Intl.AP.726170_TMY3.epw',
        'ASHRAE 169-2006-6B' => 'USA_MT_Helena.Rgnl.AP.727720_TMY3.epw',
        'ASHRAE 169-2006-7A' => 'USA_MN_Duluth.Intl.AP.727450_TMY3.epw',
        'ASHRAE 169-2006-7B' => 'USA_MN_Duluth.Intl.AP.727450_TMY3.epw',
        'ASHRAE 169-2006-8A' => 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw',
        'ASHRAE 169-2006-8B' => 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw',
        'ASHRAE 169-2013-0A' => 'VNM_SVN_Ho.Chi.Minh-Tan.Son.Nhat.Intl.AP.489000_TMYx.epw',
        'ASHRAE 169-2013-0B' => 'ARE_DU_Dubai.Intl.AP.411940_TMYx.epw',
        'ASHRAE 169-2013-1A' => 'USA_HI_Honolulu.Intl.AP.911820_TMY3.epw',
        'ASHRAE 169-2013-1B' => 'IND_DL_New.Delhi-Safdarjung.AP.421820_TMYx.epw',
        'ASHRAE 169-2013-2A' => 'USA_FL_Tampa-MacDill.AFB.747880_TMY3.epw',
        'ASHRAE 169-2013-2B' => 'USA_AZ_Tucson-Davis-Monthan.AFB.722745_TMY3.epw',
        'ASHRAE 169-2013-3A' => 'USA_GA_Atlanta-Hartsfield.Jackson.Intl.AP.722190_TMY3.epw',
        'ASHRAE 169-2013-3B' => 'USA_TX_El.Paso.Intl.AP.722700_TMY3.epw',
        'ASHRAE 169-2013-3C' => 'USA_CA_San.Deigo-Brown.Field.Muni.AP.722904_TMY3.epw',
        'ASHRAE 169-2013-4A' => 'USA_NY_New.York-John.F.Kennedy.Intl.AP.744860_TMY3.epw',
        'ASHRAE 169-2013-4B' => 'USA_NM_Albuquerque.Intl.Sunport.723650_TMY3.epw',
        'ASHRAE 169-2013-4C' => 'USA_WA_Seattle-Tacoma.Intl.AP.727930_TMY3.epw',
        'ASHRAE 169-2013-5A' => 'USA_NY_Buffalo.Niagara.Intl.AP.725280_TMY3.epw',
        'ASHRAE 169-2013-5B' => 'USA_CO_Denver-Aurora-Buckley.AFB.724695_TMY3.epw',
        'ASHRAE 169-2013-5C' => 'USA_WA_Port.Angeles-William.R.Fairchild.Intl.AP.727885_TMY3.epw',
        'ASHRAE 169-2013-6A' => 'USA_MN_Rochester.Intl.AP.726440_TMY3.epw',
        'ASHRAE 169-2013-6B' => 'USA_MT_Great.Falls.Intl.AP.727750_TMY3.epw',
        'ASHRAE 169-2013-7A' => 'USA_MN_International.Falls.Intl.AP.727470_TMY3.epw',
        'ASHRAE 169-2013-7B' => 'USA_MN_International.Falls.Intl.AP.727470_TMY3.epw',
        'ASHRAE 169-2013-8A' => 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw',
        'ASHRAE 169-2013-8B' => 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw',
        # For measure input
        'NECB HDD Method' => epw_file.to_s,
        # For testing
        'NECB-CNEB-5' => epw_file.to_s,
        'NECB-CNEB-6' => epw_file.to_s,
        'NECB-CNEB-7a' => epw_file.to_s,
        'NECB-CNEB-7b' => epw_file.to_s,
        'NECB-CNEB-8' => epw_file.to_s,
        # For DEER
        'CEC T24-CEC1' => 'ARCATA_725945_CZ2010.epw',
        'CEC T24-CEC2' => 'SANTA-ROSA_724957_CZ2010.epw',
        'CEC T24-CEC3' => 'OAKLAND_724930_CZ2010.epw',
        'CEC T24-CEC4' => 'SAN-JOSE-REID_724946_CZ2010.epw',
        'CEC T24-CEC5' => 'SANTA-MARIA_723940_CZ2010.epw',
        'CEC T24-CEC6' => 'TORRANCE_722955_CZ2010.epw',
        'CEC T24-CEC7' => 'SAN-DIEGO-LINDBERGH_722900_CZ2010.epw',
        'CEC T24-CEC8' => 'FULLERTON_722976_CZ2010.epw',
        'CEC T24-CEC9' => 'BURBANK-GLENDALE_722880_CZ2010.epw',
        'CEC T24-CEC10' => 'RIVERSIDE_722869_CZ2010.epw',
        'CEC T24-CEC11' => 'RED-BLUFF_725910_CZ2010.epw',
        'CEC T24-CEC12' => 'SACRAMENTO-EXECUTIVE_724830_CZ2010.epw',
        'CEC T24-CEC13' => 'FRESNO_723890_CZ2010.epw',
        'CEC T24-CEC14' => 'PALMDALE_723820_CZ2010.epw',
        'CEC T24-CEC15' => 'PALM-SPRINGS-INTL_722868_CZ2010.epw',
        'CEC T24-CEC16' => 'BLUE-CANYON_725845_CZ2010.epw'
      }
      return climate_zone_weather_file_map
    end

    # Converts the climate zone in the model into the format used by the openstudio-standards lookup tables.
    # For example,
    #   institution: ASHRAE, value: 6A  becomes: ASHRAE 169-2013-6A.
    #   institution: CEC, value: 3  becomes: CEC T24-CEC3.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [String] the string representation of the climate zone,
    #   empty string if no climate zone is present in the model.
    def self.model_get_climate_zone(model)
      climate_zone = ''
      model.getClimateZones.climateZones.each do |cz|
        if cz.institution == 'ASHRAE'
          next if cz.value == '' # Skip blank ASHRAE climate zones put in by OpenStudio Application

          if cz.value == '7' || cz.value == '8'
            climate_zone = "ASHRAE 169-2013-#{cz.value}A"
          else
            climate_zone = "ASHRAE 169-2013-#{cz.value}"
          end
        elsif cz.institution == 'CEC'
          # Skip blank ASHRAE climate zones put in by OpenStudio Application
          if cz.value == ''
            next
          end

          climate_zone = "CEC T24-CEC#{cz.value}"
        end
      end
      return climate_zone
    end

    # Get the ASHRAE climate zone number.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Integer] ASHRAE climate zone number, 0-8
    def self.model_get_ashrae_climate_zone_number(model)
      # get ashrae climate zone from model
      ashrae_climate_zone = ''
      model.getClimateZones.climateZones.each do |climate_zone|
        if climate_zone.institution == 'ASHRAE'
          ashrae_climate_zone = climate_zone.value
        elsif climate_zone.institution == 'CEC'
          ca_cz_num = climate_zone.value.gsub('CEC T24-CEC', '')
          case ca_cz_num
          when '1'
            ashrae_climate_zone = '4B'
          when '2', '3', '4', '5', '6'
            ashrae_climate_zone = '3C'
          when '7', '8', '9', '10', '11', '12', '13', '14'
            ashrae_climate_zone = '3B'
          when '15'
            ashrae_climate_zone = '2B'
          when '16'
            ashrae_climate_zone = '5B'
          end
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.information', "Using ASHRAE climate zone #{climate_zone} for California climate zone #{climate_zone.value}.")
        end
      end

      if ashrae_climate_zone == ''
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.information', 'Please assign an ASHRAE Climate Zone to your model.')
        return false
      else
        cz_number = ashrae_climate_zone.chars.first.to_i
      end

      # expected climate zone number should be 0 through 8
      if ![0, 1, 2, 3, 4, 5, 6, 7, 8].include? cz_number
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.information', 'ASHRAE climate zone number is not within expected range of 1 to 8.')
        return false
      end

      return cz_number
    end

    # Get the full path to the weather file that is specified in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::OptionalPath] path to weather file
    def self.model_get_full_weather_file_path(model)
      full_epw_path = OpenStudio::OptionalPath.new

      if model.weatherFile.is_initialized
        epw_path = model.weatherFile.get.path
        if epw_path.is_initialized
          if File.exist?(epw_path.get.to_s)
            full_epw_path = OpenStudio::OptionalPath.new(epw_path.get)
          else
            # If this is an always-run Measure, need to check a different path
            alt_weath_path = File.expand_path(File.join(__dir__, '../../resources'))
            alt_epw_path = File.expand_path(File.join(alt_weath_path, epw_path.get.to_s))
            if File.exist?(alt_epw_path)
              full_epw_path = OpenStudio::OptionalPath.new(OpenStudio::Path.new(alt_epw_path))
            else
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Model has been assigned a weather file, but the file is not in the specified location of '#{epw_path.get}'.")
            end
          end
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', 'Model has a weather file assigned, but the weather file path has been deleted.')
        end
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', 'Model has not been assigned a weather file.')
      end

      return full_epw_path
    end

    # Get absolute path of a weather file included within openstudio-standards.
    #
    # @param weather_file_name [String] Name of a weather file included within openstudio-standards, including file extension .epw
    # @return [String] Weather file path
    def self.get_standards_weather_file_path(weather_file_name)
      # Define where the weather files lives
      weather_dir = nil
      if __dir__[0] == ':' # Running from OpenStudio CLI
        # load weather file from embedded files
        epw_string = load_resource_relative("../../../data/weather/#{weather_file_name}")
        ddy_string = load_resource_relative("../../../data/weather/#{weather_file_name.gsub('.epw', '.ddy')}")
        stat_string = load_resource_relative("../../../data/weather/#{weather_file_name.gsub('.epw', '.stat')}")

        # extract to local weather dir
        weather_dir = File.expand_path(File.join(Dir.pwd, 'extracted_files/weather/'))
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.information', "Extracting weather files from OpenStudio CLI to #{weather_dir}")
        FileUtils.mkdir_p(weather_dir)

        path_length = "#{weather_dir}/#{weather_file_name}".length
        if path_length > 260
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.information', "Weather file path length #{path_length} is >260 characters and may cause issues in Windows environments.")
        end
        File.open("#{weather_dir}/#{weather_file_name}", 'wb') do |f|
          f << epw_string
          f.flush
        end
        File.open("#{weather_dir}/#{weather_file_name.gsub('.epw', '.ddy')}", 'wb') do |f|
          f << ddy_string
          f.flush
        end
        File.open("#{weather_dir}/#{weather_file_name.gsub('.epw', '.stat')}", 'wb') do |f|
          f << stat_string
          f.flush
        end
      else
        # loaded gem from system path
        top_dir = File.expand_path('../../..', File.dirname(__FILE__))
        weather_dir = File.expand_path("#{top_dir}/data/weather")
      end

      # Add Weather File
      unless (Pathname.new weather_dir).absolute?
        weather_dir = File.expand_path(File.join(File.dirname(__FILE__), weather_dir))
      end

      weather_file_path = File.join(weather_dir, weather_file_name)

      return weather_file_path
    end

    # Get absolute path of a weather file included within openstudio-standards that is representative of the climate zone.
    #
    # @param climate_zone [String] full climate zone string, e.g. 'ASHRAE 169-2013-4A'
    # @return [String] absolute file path
    def self.climate_zone_representative_weather_file_path(climate_zone)
      climate_zone_weather_file_map = OpenstudioStandards::Weather.climate_zone_weather_file_map
      weather_file_name = climate_zone_weather_file_map[climate_zone]
      if weather_file_name.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.information', "Could not determine weather for climate zone: #{climate_zone}")
        return false
      end

      standards_weather_file_path = OpenstudioStandards::Weather.get_standards_weather_file_path(weather_file_name)
      return standards_weather_file_path
    end

    # Get a list of regular expressions matching the design day categories.
    #
    # For looking up design day objects by type
    # @param category [String] The design day category, e.g. 'All Heating', 'Annual Cooling'.
    # @return [Array<Regexp>] list of regular expressions matching design day names to import.
    def self.ddy_regex_lookup(category)
      ddy_regex_map = {
        'All Heating' => /Htg/,
        'Heating DB' => /Htg.* DB/,
        'Heating 99.6%' => /Htg.*99.6%/,
        'Heating 99%' => /Htg.*99%/,
        'Heating Wind' => /Htg Wind/,
        'All Cooling' => / (0?\.4|1|2|5)\.?0?%/,
        'Annual Cooling' => /Ann Clg/,
        'All Cooling DB' => /DB=>MC?WB/,
        'All Cooling WB' => /WB=>MC?DB/,
        'All Cooling DP' => /Clg.* DP/,
        'All Cooling Enth' => /Clg.* Enth/,
        'Annual Cooling DB' => /Clg.* DB/,
        'Annual Cooling WB' => /Clg.* WB/,
        'Annual Cooling DP' => /Clg.* DP/,
        'Annual Cooling Enth' => /Clg.* Enth/,
        'Cooling 0.4%' => /.4%/,
        'Cooling 2%' => /2%/,
        'Cooling 5%' => /5%/,
        'Annual Cooling 0.4%' => /Ann.*.4%/,
        'Annual Cooling 2%' => /Ann.*2%/,
        'Monthly Cooling' => /Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec/,
        'Monthly 0.4%' => /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*0?.4/,
        'Monthly 2%' => /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*2%/,
        'Monthly 5%' => /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*5%/,
        'Monthly DB' => /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*DB=>MC?WB/,
        'Monthly WB' => /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*WB=>MC?DB/
      }
      valid = ddy_regex_map.keys
      unless valid.include?(category)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.information', "Could not find a matching ddy regular expression for entered category #{category}. Valid categories are #{valid}.")
        return false
      end

      return [ddy_regex_map[category]]
    end

    # Returns the winter design outdoor air dry bulb temperatures in the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Array<Double>] an array of outdoor design dry bulb temperatures in degrees Celsius
    def self.model_get_heating_design_outdoor_temperatures(model)
      heating_design_outdoor_temps = []
      model.getDesignDays.each do |dd|
        next unless dd.dayType == 'WinterDesignDay'

        heating_design_outdoor_temps << dd.maximumDryBulbTemperature
      end

      return heating_design_outdoor_temps
    end

    # Returns the ASHRAE climate zone based on degree days
    #
    # @param hdd18 [Double] Cooling Degree Days, 18C base
    # @param cdd10 [Double] Cooling Degree Days, 10C base
    # @return [String] full climate zone string, e.g. 'ASHRAE 169-2013-4A'
    # @todo support Humid (A) / Dry (B) distinctions based on precipitation per Section A3 of ASHRAE 169
    def self.get_climate_zone_from_degree_days(hdd18, cdd10)
      if cdd10 > 6000
        # Extremely Hot  Humid (0A), Dry (0B)
        return 'ASHRAE 169-2013-0A'

      elsif (cdd10 > 5000) && (cdd10 <= 6000)
        # Very Hot  Humid (1A), Dry (1B)
        return 'ASHRAE 169-2013-1A'

      elsif (cdd10 > 3500) && (cdd10 <= 5000)
        # Hot  Humid (2A), Dry (2B)
        return 'ASHRAE 169-2013-2A'

      elsif ((cdd10 > 2500) && (cdd10 < 3500)) && (hdd18 <= 2000)
        # Warm  Humid (3A), Dry (3B)
        return 'ASHRAE 169-2013-3A' # and 'ASHRAE 169-2013-3B'

      elsif (cdd10 <= 2500) && (hdd18 <= 2000)
        # Warm  Marine (3C)
        return 'ASHRAE 169-2013-3C'

      elsif ((cdd10 > 1500) && (cdd10 < 3500)) && ((hdd18 > 2000) && (hdd18 <= 3000))
        # Mixed  Humid (4A), Dry (4B)
        return 'ASHRAE 169-2013-4A' # and 'ASHRAE 169-2013-4B'

      elsif (cdd10 <= 1500) && ((hdd18 > 2000) && (hdd18 <= 3000))
        # Mixed  Marine
        return 'ASHRAE 169-2013-4C'

      elsif ((cdd10 > 1000) && (cdd10 <= 3500)) && ((hdd18 > 3000) && (hdd18 <= 4000))
        # Cool Humid (5A), Dry (5B)
        return 'ASHRAE 169-2013-5A' # and 'ASHRAE 169-2013-5B'

      elsif (cdd10 <= 1000) && ((hdd18 > 3000) && (hdd18 <= 4000))
        # Cool  Marine (5C)
        return 'ASHRAE 169-2013-5C'

      elsif (hdd18 > 4000) && (hdd18 <= 5000)
        # Cold  Humid (6A), Dry (6B)
        return 'ASHRAE 169-2013-6A' # and 'ASHRAE 169-2013-6B'

      elsif (hdd18 > 5000) && (hdd18 <= 7000)
        # Very Cold (7)
        return 'ASHRAE 169-2013-7A'

      elsif hdd18 > 7000
        # Subarctic/Arctic (8)
        return 'ASHRAE 169-2013-8A'

      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.information', "Could not determine climate zone from #{hdd18} heating degree days base 18°C and #{cdd10} cooling degree days base 10°C.")
        return ''
      end
    end

    # Calculate average global irradiance for the design day
    # Calculated from ASHRAE HOF 2017 Chp 14 Clear-Sky Solar Radiation
    #
    # @param design_day [OpenStudio::Model::DesignDay] OpenStudio DesignDay object
    # @return [Double] average global irradiance over the full day (24 hours) (W/m^2)
    def self.design_day_average_global_irradiance(design_day)
      # get site longitude and time zone longitude
      weather_file = design_day.model.weatherFile.get
      site_longitude_degrees = weather_file.longitude
      site_latitude_degrees = weather_file.latitude
      site_latitude_radians = site_latitude_degrees * (Math::PI / 180.0)
      time_zone_longitude_degrees = 15.0 * weather_file.timeZone

      # day of year
      day_of_year = Date.new(y = 2009, m = design_day.month, d = design_day.dayOfMonth).yday

      # equation of time
      gamma_degrees = 360 * (day_of_year - 1) / 365.0
      gamma_radians = gamma_degrees * (Math::PI / 180.0)
      equation_of_time_minutes = 2.2918 * (0.0075 + (0.1868 * Math.cos(gamma_radians)) - (3.2077 * Math.sin(gamma_radians)) - (1.4615 * Math.cos(2 * gamma_radians)) - (4.089 * Math.sin(2 * gamma_radians)))

      # extraterrestrial normal irradiance, W/m^2
      extraterrestrial_normal_irradiance_degrees = 360 * (day_of_year - 3) / 365.0
      extraterrestrial_normal_irradiance_radians = extraterrestrial_normal_irradiance_degrees * (Math::PI / 180.0)
      extraterrestrial_normal_irradiance = 1367.0 * (1.0 + (0.033 * Math.cos(extraterrestrial_normal_irradiance_radians)))

      # declination
      day_angle_degrees = 360.0 * (day_of_year + 284) / 365.0
      day_angle_radians = day_angle_degrees * (Math::PI / 180.0)
      declination_degrees = 23.45 * Math.sin(day_angle_radians)
      declination_radians = declination_degrees * (Math::PI / 180.0)

      # air mass exponents from optical depth
      tau_b = design_day.ashraeClearSkyOpticalDepthForBeamIrradiance
      tau_d = design_day.ashraeClearSkyOpticalDepthForDiffuseIrradiance
      ab = 1.454 - (0.406 * tau_b) - (0.268 * tau_d) + (0.021 * tau_b * tau_d)
      ad = 0.507 + (0.205 * tau_b) - (0.080 * tau_d) - (0.190 * tau_b * tau_d)

      global_irradiance_array = []
      (0..23).to_a.each do |local_standard_time_hour|
        # apparent solar time
        apparent_solar_time = local_standard_time_hour + (equation_of_time_minutes / 60.0) + ((site_longitude_degrees - time_zone_longitude_degrees) / 15.0)

        # hour angle
        hour_angle_degrees = 15.0 * (apparent_solar_time - 12.0)
        hour_angle_radians = hour_angle_degrees * (Math::PI / 180.0)

        # solar altitude
        solar_altitude_radians = Math.asin((Math.cos(site_latitude_radians) * Math.cos(declination_radians) * Math.cos(hour_angle_radians)) + (Math.sin(site_latitude_radians) * Math.sin(declination_radians)))
        solar_altitude_degrees = solar_altitude_radians * (180.0 / Math::PI)

        # equation 16 air mass
        # equation 17 and 18 irradiance calculation
        if solar_altitude_degrees > 0
          air_mass = 1 / (Math.sin(solar_altitude_radians) + (0.50572 * ((6.07995 + solar_altitude_degrees)**-1.6364)))
          beam_normal_irradiance = extraterrestrial_normal_irradiance * Math.exp(-tau_b * (air_mass**ab))
          diffuse_horizontal_irradiance = extraterrestrial_normal_irradiance * Math.exp(-tau_d * (air_mass**ad))
        else
          air_mass = nil
          beam_normal_irradiance = 0.0
          diffuse_horizontal_irradiance = 0.0
        end
        global_irradiance = beam_normal_irradiance + diffuse_horizontal_irradiance
        global_irradiance_array << global_irradiance

        # puts "For local_standard_time_hour #{local_standard_time_hour}, apparent_solar_time #{apparent_solar_time}, hour_angle_degrees #{hour_angle_degrees}, solar_altitude_degrees #{solar_altitude_degrees}, air_mass #{air_mass}, beam_normal_irradiance #{beam_normal_irradiance}, diffuse_horizontal_irradiance #{diffuse_horizontal_irradiance}"
      end

      average_daily_global_irradiance = global_irradiance_array.sum / 24.0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Weather.information', "For design day #{design_day.name}, day_of_year #{day_of_year}, time zone #{weather_file.timeZone}, site_longitude_degrees #{site_longitude_degrees}, time_zone_longitude_degrees #{time_zone_longitude_degrees}, site_latitude_degrees #{site_latitude_degrees}, equation_of_time_minutes #{equation_of_time_minutes}, declination_degrees #{declination_degrees}, extraterrestrial_normal_irradiance #{extraterrestrial_normal_irradiance}, average_daily_global_irradiance #{average_daily_global_irradiance} W/m^2.")

      return average_daily_global_irradiance
    end

    # Calculate dehumidification degree days from an epw_file
    #
    # @param epw_file [OpenStudio::EpwFile] OpenStudio EpwFile object
    # @param base_humidity_ratio [Double] base humidity ratio, default is 0.010
    # @return [Double] dehumdification degree days
    def self.epw_file_get_dehumidification_degree_days(epw_file, base_humidity_ratio: 0.010)
      # Workaround for case when the weather file contains the February from a leap year but that February only has 28
      # days of data.
      has_leap_day = false

      # Find the first day in February
      feb_index = epw_file.data.find_index { |entry| entry.date.monthOfYear.value == 2 }

      # Find the year for February
      feb_year = epw_file.data[feb_index].year
      # Determine if February's year is a leap year
      leap_year = false
      if (feb_year % 100) > 0
        leap_year = true if (feb_year % 4) == 0
      else
        leap_year = true if (feb_year % 400) == 0
      end
      # If the February is from a leap year determine if it contains a leap day
      if leap_year

        day = epw_file.data[feb_index].date.dayOfMonth
        inc = 0

        while epw_file.data[feb_index].date.dayOfMonth == day
          feb_index += 1
          inc       += 1
        end

        has_leap_day = epw_file.data[feb_index + (inc * 28)].date.dayOfMonth == 29
      end

      # If the February is from a leap year and there is no leap day then do not use the faulty OpenStudio Epw
      # .getTimeSeries method.  Otherwise, use the method.
      if has_leap_day || !leap_year
        db_temps_c   = epw_file.getTimeSeries('Dry Bulb Temperature').get.values
        rh_values    = epw_file.getTimeSeries('Relative Humidity').get.values
        atm_p_values = epw_file.getTimeSeries('Atmospheric Station Pressure').get.values
      else
        # Access the data directly instead of using the OpenStudio API to avoid the faulty OpenStudioEpw
        # .getTimeSeries method.

        # Open the weather file
        regex_csv = /[^,]+/
        regex_num = /[0-9]/
        f         = File.open(epw_file.path.to_s, 'r')
        i         = 0

        # Skip the header
        i += 1 until f.readline[0] =~ regex_num

        # Get all of the hourly weather data
        lines         = IO.readlines(f)[i..-1]

        # Get hourly weather data for a specific column
        db_temps_c    = lines.map { |line| Float(line.scan(regex_csv)[6]) }
        rh_values     = lines.map { |line| Float(line.scan(regex_csv)[8]) }
        atm_p_values  = lines.map { |line| Float(line.scan(regex_csv)[9]) }
      end

      db_temps_k = db_temps_c.map { |v| v + 273.15 }


      # coefficients for the calculation of pws (Reference: ASHRAE Handbook - Fundamentals > CHAPTER 1. PSYCHROMETRICS)
      c1 = -5.6745359E+03
      c2 = 6.3925247E+00
      c3 = -9.6778430E-03
      c4 = 6.2215701E-07
      c5 = 2.0747825E-09
      c6 = -9.4840240E-13
      c7 = 4.1635019E+00
      c8 = -5.8002206E+03
      c9 = 1.3914993E+00
      c10 = -4.8640239E-02
      c11 = 4.1764768E-05
      c12 = -1.4452093E-08
      c13 = 6.5459673E+00

      # calculate saturation pressure of water vapor (Pa)
      sp_values = []
      db_temps_k.each do |t|
        if t <= 273.15
          sp = (c1 / t) + c2 + (c3 * t) + (c4 * (t**2)) + (c5 * (t**3)) + (c6 * (t**4)) + (c7 * Math.log(t, Math.exp(1)))

        else
          sp = (c8 / t) + c9 + (c10 * t) + (c11 * (t**2)) + (c12 * (t**3)) + (c13 * Math.log(t, Math.exp(1)))
        end
        sp_values << (Math.exp(1)**sp)
      end

      # calculate partial pressure of water vapor (Pa)
      pp_values = sp_values.zip(rh_values).map { |sp, rh| sp * rh / 100.0 }

      # calculate total pressure (Pa)
      tp_values = pp_values.zip(atm_p_values).map { |pp, atm| pp + atm }

      # calculate humidity ratio
      hr_values = pp_values.zip(tp_values).map { |pp, tp| (0.621945 * pp) / (tp - pp) }

      # calculate dehumidification degree days based on humidity ratio values above the base
      hr_values_above_base = hr_values.map { |hr| hr > base_humidity_ratio ? hr : 0.0 }
      dehumidification_degree_days = hr_values_above_base.sum / 24.0

      return dehumidification_degree_days
    end

    # @!endgroup Information
  end
end
