require 'pathname'

module OpenstudioStandards
  module Weather
    class StatFile
      attr_accessor :text, :path, :valid, :lat, :lon, :elevation, :gmt,
                    :monthly_dry_bulb, :monthly_lagged_dry_bulb, :delta_dry_bulb, :mean_dry_bulb,
                    :hdd18, :cdd18, :hdd10, :cdd10,
                    :heating_design_info, :cooling_design_info, :extremes_design_info,
                    :climate_zone, :standard,
                    :summer_wet_months, :winter_dry_months, :autumn_months, :spring_months,
                    :typical_summer_wet_week, :typical_winter_dry_week, :typical_autumn_week, :typical_spring_week,
                    :monthly_undis_ground_temps_0p5m, :monthly_undis_ground_temps_4p0m

      def initialize(path)
        @text = ''
        @path = Pathname.new(path)
        @valid = false
        @lat = nil
        @lon = nil
        @gmt = nil
        @elevation = nil
        @hdd18 = nil
        @cdd18 = nil
        @hdd10 = nil
        @cdd10 = nil
        @monthly_dry_bulb = []
        @monthly_lagged_dry_bulb = []
        @delta_dry_bulb = nil
        @mean_dry_bulb = nil
        @heating_design_info = []
        @cooling_design_info  = []
        @extremes_design_info = []
        @climate_zone = []
        @standard = []
        @summer_wet_months = []
        @winter_dry_months = []
        @autumn_months = []
        @spring_months = []
        @typical_summer_wet_week = []
        @typical_winter_dry_week = []
        @typical_autumn_week = []
        @typical_spring_week = []
        @monthly_undis_ground_temps_0p5m = []
        @monthly_undis_ground_temps_4p0m = []
        init
      end

      # load a Stat file as an instance of OpenstudioStandards::Weather::StatFile
      #
      # @param filename [String] full path to Stat file
      def self.load(filename)
        raise "Stat file does not exist: #{filename}" unless File.file?(filename)

        f = OpenstudioStandards::Weather::StatFile.new(filename)
      end

      # Output for debugging stat routines.
      def output
        line = ''
        line << "#{@path} , "
        line << "#{@lat} ,"
        line << "#{@lon} ,"
        line << "#{@gmt} ,"
        line << "#{@elevation} ,"
        line << "#{@hdd18} ,"
        line << "#{@cdd18} ,"
        line << "#{@hdd10} ,"
        line << "#{@cdd10} ,"
        line << "#{monthly_dry_bulb} ,"
        line << "#{monthly_lagged_dry_bulb} ,"
        line << "#{delta_dry_bulb} ,"
        line << "#{mean_dry_bulb} ,"
        line << "#{@heating_design_info} ,"
        line << "#{@cooling_design_info}  ,"
        line << "#{@extremes_design_info} ,"
        line << "#{@climate_zone} ,"
        line << "#{@standard} ,"
        line << "#{@summer_wet_months} ,"
        line << "#{@winter_dry_months} ,"
        line << "#{@autumn_months} ,"
        line << "#{@spring_months} ,"
        line << "#{@typical_summer_wet_week} ,"
        line << "#{@typical_winter_dry_week} ,"
        line << "#{@typical_autumn_week} ,"
        line << "#{@typical_spring_week} ,"
        line << "#{@monthly_undis_ground_temps_0p5m} ,"
        line << "#{@monthly_undis_ground_temps_4p0m} ,"
        line << @valid.to_s
      end

      # returns the stat data as a JSON string
      #
      # @param options [Hash] options to pass to as_json
      # @return [String] JSON-formatted string
      def to_json(*options)
        as_json(*options).to_json(*options)
      end

      def valid?
        return @valid
      end

      # ground temps as monthly dry bulb tempreature lagged 3 months
      def monthly_lagged_dry_bulb_calc
        if @monthly_dry_bulb.empty?
          lagged_temperatures = []
        else
          lagged_temperatures = @monthly_dry_bulb.rotate(-3)
        end

        lagged_temperatures
      end

      # the mean of the mean monthly dry bulbs
      def mean_dry_bulb_calc
        if @monthly_dry_bulb.empty?
          mean = ''
        else
          sum = @monthly_dry_bulb.inject(:+)
          mean = sum / @monthly_dry_bulb.size
        end

        mean.to_f
      end

      # max - min of the mean monthly dry bulbs
      def delta_dry_bulb_calc
        if @monthly_dry_bulb.empty?
          delta_t = ''
        else
          delta_t = @monthly_dry_bulb.max - @monthly_dry_bulb.min
        end

        delta_t.to_f
      end

      private

      def as_json(options = {})
        {
          'path' => @path,
          'valid' => @valid,
          'lat' => @lat,
          'lon' => @lon,
          'gmt' => @gmt,
          'elevation' => @elevation,
          'hdd18' => @hdd18,
          'cdd18' => @cdd18,
          'hdd10' => @hdd10,
          'cdd10' => @cdd10,
          'monthly_dry_bulb' => @monthly_dry_bulb,
          'monthly_lagged_dry_bulb' => @monthly_lagged_dry_bulb,
          'delta_dry_bulb' => @delta_dry_bulb,
          'mean_dry_bulb' => @mean_dry_bulb,
          'heating_design_info' => @heating_design_info,
          'cooling_design_info' => @cooling_design_info,
          'extremes_design_info' => @extremes_design_info,
          'climate_zone' => @climate_zone,
          'standard' => @standard,
          'summer_wet_months' => @summer_wet_months,
          'winter_dry_months' => @winter_dry_months,
          'autumn_months' => @autumn_months,
          'spring_months' => @spring_months,
          'typical_summer_wet_week' => @typical_summer_wet_week,
          'typical_winter_dry_week' => @typical_winter_dry_week,
          'typical_autumn_week' => @typical_autumn_week,
          'typical_spring_week' => @typical_spring_week,
          'monthly_undis_ground_temps_0p5m' => @monthly_undis_ground_temps_0p5m,
          'monthly_undis_ground_temps_4p0m' => @monthly_undis_ground_temps_4p0m
        }
      end

      # initialize
      def init
        unless @path.exist?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Weather.StatFile', "Can't find #{@path}")
          raise
        end

        File.open(@path) do |f|
          @text = f.read.force_encoding('iso-8859-1').encode('UTF-8')
          parse
          @monthly_lagged_dry_bulb = monthly_lagged_dry_bulb_calc
          @mean_dry_bulb = mean_dry_bulb_calc
          @delta_dry_bulb = delta_dry_bulb_calc
        end
      end

      # helper function to parse cooling and heating degree days
      #
      # @param dd_info [Hash] :name, :regex, :container
      def parse_dd_info(dd_info)
        match_data = @text.match(dd_info[:regex])
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find degree day information for #{dd_info[:name]} in the .stat file.")
        else
          instance_variable_set("@#{dd_info[:container]}", match_data[1].to_f)
        end
      end

      # helper function to parse monthly design conditions
      #
      # @param temp_info [Hash] :name, :size, :regex, :container
      def parse_design_temp_info(temp_info)
        match_data = @text.match(temp_info[:regex])
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find design temperatures #{temp_info[:name]}. They may not be available in the .stat file.")
        else
          match_info_raw = match_data[1].strip.split(/\s+/)
          match_info_raw = match_info_raw.map(&:to_f)

          # check info size
          if match_info_raw.size != temp_info[:size]
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Expected to find #{temp_info[:size]} #{temp_info[:name]} but found #{match_info_raw.size}. Check data source.")
          end

          match_info_raw.each do |val|
            temp_info[:container] << val
          end
        end
      end

      # helper function to parse seasons
      #
      # @param season_info [Hash] :name, :container, :regex
      def parse_season_info(season_info)
        match_data = @text.match(season_info[:regex])
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find #{season_info[:name]}. Data source may not have that season, or it may not be available in the .stat file.")
        else
          if ['Summer', 'Winter'].include?(season_info[:name].split[0])
            instance_variable_set("@#{season_info[:container]}", match_data[2].to_s.strip)
          else
            instance_variable_set("@#{season_info[:container]}", match_data[1].to_s.strip)
          end
        end
      end

      def parse
        # parse lat, lon, gmt
        regex = /\{(N|S)\s*([0-9]*).\s*([0-9]*)'\}\s*\{(E|W)\s*([0-9]*).\s*([0-9]*)'\}\s*\{GMT\s*(.*)\s*Hours\}/
        match_data = @text.match(regex)
        if match_data.nil?
          regex = /\{(N|S)\s*([0-9]*).\s*([0-9]*)\.([0-9]*)'\}\s*\{(E|W)\s*([0-9]*).\s*([0-9]*)\.([0-9]*)'\}\s*\{GMT\s*(.*)\s*Hours\}/
          match_data = @text.match(regex)
        end

        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find lat/lon/gmt in .stat file.")
        else
          @lat = match_data[2].to_f + (match_data[3].to_f / 60.0)
          if match_data[1] == 'S'
            @lat = -@lat
          end

          @lon = match_data[5].to_f + (match_data[6].to_f / 60.0)
          if match_data[4] == 'W'
            @lon = -@lon
          end

          @gmt = match_data[7].to_f
        end

        # parse elevation
        regex = /Elevation --\s*(.*)m (above|below) sea level/
        match_data = @text.match(regex)
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find elevation in .stat file.")
        else
          @elevation = match_data[1].to_f
          if match_data[2] == 'below'
            @elevation = -@elevation
          end
        end

        # parse degree day info
        degree_day_info = [
          { dd_name: 'CDD 10', container: 'cdd10', regex: /-\s*(.*) annual \((standard|wthr file)\) cooling degree-days \(10.?C baseline\)/ },
          { dd_name: 'HDD 10', container: 'hdd10', regex: /-\s*(.*) annual \((wthr file)\) heating degree-days \(10.?C baseline\)/ },
          { dd_name: 'CDD 18', container: 'cdd18', regex: /-\s*(.*) annual \((wthr file)\) cooling degree-days \(18.*C baseline\)/ },
          { dd_name: 'HDD 18', container: 'hdd18', regex: /-\s*(.*) annual \((wthr file)\) heating degree-days \(18.*C baseline\)/ }
        ]
        degree_day_info.each { |dd_info| parse_dd_info(dd_info) }

        # parse design temperatures
        # TMYx stat file format is different than TMY3, cf #1948
        is_tmyx = @text.include?('Wind Shelter Factor')
        temperature_info = [
          { name: 'Heating Design Temperatures', regex: /Heating(\s*\d+.*)\n/, container: @heating_design_info, size: is_tmyx ? 16 : 15 },
          { name: 'Cooling Design Temperatures', regex: /Cooling(\s*\d+.*)\n/, container: @cooling_design_info, size: 32 },
          { name: 'Extreme Design Temperatures', regex: /\s*Extremes\s*(.*)\n/, container: @extremes_design_info, size: is_tmyx ? 15 : 16 },
          { name: 'Monthly Dry Bulb Temperatures', regex: /Daily Avg(.*)\n/, container: @monthly_dry_bulb, size: 12 }
        ]
        temperature_info.each { |temp_info| parse_design_temp_info(temp_info) }
        if is_tmyx
          @heating_design_info.pop # remove the last value, which is the Wind Shelter Factor
          # There is no WBmax in TMYx files, so add a nil
          @extremes_design_info.insert(3, nil)
        end

        # parse undisturbed ground temps at 0.5 and 4.0 m depth
        regex = /Monthly.*Calculated.*undisturbed*.*Ground.*Temperatures.*\n.*Jan.*Feb.*Mar.*Apr.*May.*Jun.*Jul.*Aug.*Sep.*Oct.*Nov.*Dec.*\n(.*)\n(.*)\n(.*)/
        match_data = @text.match(regex)
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find undisturbed ground temperatures in .stat file.")
        else
          # first match is undisturbed ground temperature at 0.5 m and 4.0 m depth
          monthly_undis_ground_temps_0p5m = match_data[1].strip.split(/\s+/)
          monthly_undis_ground_temps_0p5m.shift
          monthly_undis_ground_temps_0p5m.shift
          monthly_undis_ground_temps_4p0m = match_data[3].strip.split(/\s+/)
          monthly_undis_ground_temps_4p0m.shift
          monthly_undis_ground_temps_4p0m.shift
          # have to be 12 months
          if monthly_undis_ground_temps_0p5m.size == 12
            monthly_undis_ground_temps_0p5m.each { |temp| @monthly_undis_ground_temps_0p5m << temp.to_f }
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find undisturbed ground temps at 0.5m in the .stat file.")
          end
          if monthly_undis_ground_temps_4p0m.size == 12
            monthly_undis_ground_temps_4p0m.each { |temp| @monthly_undis_ground_temps_4p0m << temp.to_f }
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find undisturbed ground temps at 4.0m in the .stat file.")
          end
        end

        # parse 2004 climate zone and standard
        # regex = /Climate (\btype\b|\bZone\b) \"(.*?)\" \(ASHRAE Standards?(.*)\)\*?\*?/
        regex = /Climate (\btype\b|\bZone\b) \"(.*?)\" \(ASHRAE Standards?\s?(\d*-\d*)/
        match_data = @text.match(regex)
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Weather.StatFile', "Can't find climate zone")
          @climate_zone = 'NA'
        else
          @climate_zone = match_data[2].to_s.strip
          @standard = match_data[3].to_s.strip
        end

        # parse season months
        season_infos = [
          { name: 'Summer Wet Months', container: 'summer_wet_months', regex: /(Summer is |Wet Period=)(.*)/ },
          { name: 'Winter Dry Months', container: 'winter_dry_months', regex: /(Winter is |Dry Period=)(.*)/ },
          { name: 'Autumn Months', container: 'autumn_months', regex: /Autumn is (.*)/ },
          { name: 'Spring Months', container: 'spring_months', regex: /Spring is (.*)/ }
        ]
        season_infos.each { |season_info| parse_season_info(season_info) }

        # week periods
        regex = /Typical Week Period selected:(.*?)C/
        match_data = @text.scan(regex)
        if @text.include?('No discernible dry period')
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Weather.stat_file', "Can't find typical weather weeks in the .stat file because it has no discernible dry period .")
        elsif match_data.nil? || match_data.size < 2
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Weather.stat_file', "Can't find typical weather weeks in the .stat file.")
        else
          @typical_summer_wet_week = Date.parse("#{match_data[0][0].split(':')[0]} 2000")
          @typical_winter_dry_week = Date.parse("#{match_data[1][0].split(':')[0]} 2000")
          if match_data[2].nil?
            @typical_autumn_week = 'NA'
            @typical_spring_week = 'NA'
          else
            @typical_autumn_week = Date.parse("#{match_data[2][0].split(':')[0]} 2000")
            @typical_spring_week = Date.parse("#{match_data[3][0].split(':')[0]} 2000")
          end
        end

        regex = /Extreme Hot Week Period selected:(.*?)C/
        match_data = @text.match(regex)
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Weather.stat_file', "Can't find extreme hot weather week in the .stat file.")
        else
          @extreme_hot_week = Date.parse((match_data[1].split(':')[0]).to_s)
        end

        regex = /Extreme Cold Week Period selected:(.*?)C/
        match_data = @text.match(regex)
        if match_data.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Weather.stat_file', "Can't find extreme cold weather week in the .stat file.")
        else
          @extreme_cold_week = Date.parse((match_data[1].split(':')[0]).to_s)
        end

        # now we are valid
        @valid = true
      end
    end
  end
end
