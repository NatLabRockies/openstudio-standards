# Module to apply QAQC checks to a model
module OpenstudioStandards
  module QAQC
    # @!group Weather File

    # Check the weather file design days and climate zone
    #
    # @param category [String] category to bin this check into
    # @param options [Hash] Hash with epw file as a string,
    # with child objects, 'summer' and 'winter' for each design day (strings),
    # and 'climate_zone' for the climate zone number
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_weather_files(category, options, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'Weather Files')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', "Check weather file, design days, and climate zone against #{@utility_name} list of allowable options.")

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      begin
        # get weather file
        model_epw = nil
        if @model.getWeatherFile.url.is_initialized
          raw_epw = @model.getWeatherFile.url.get
          end_path_index = raw_epw.rindex('/')
          model_epw = raw_epw.slice!(end_path_index + 1, raw_epw.length) # everything right of last forward slash
        end

        # check design days (model must have one or more of the required summer and winter design days)
        # get design days names from model
        model_summer_dd_names = []
        model_winter_dd_names = []
        @model.getDesignDays.each do |design_day|
          if design_day.dayType == 'SummerDesignDay'
            model_summer_dd_names << design_day.name.to_s
          elsif design_day.dayType == 'WinterDesignDay'
            model_winter_dd_names << design_day.name.to_s
          else
            puts "unexpected day type of #{design_day.dayType} wont' be included in check"
          end
        end

        # find matching weather file from options, as well as design days and climate zone
        if options.key?(model_epw)
          required_summer_dd = options[model_epw]['summer']
          required_winter_dd = options[model_epw]['winter']
          valid_climate_zones = [options[model_epw]['climate_zone']]

          # check for intersection betwen model valid design days
          summer_intersection = (required_summer_dd & model_summer_dd_names)
          winter_intersection = (required_winter_dd & model_winter_dd_names)
          if summer_intersection.empty? && !required_summer_dd.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Didn't find any of the expected summer design days for #{model_epw}")
          end
          if winter_intersection.empty? && !required_winter_dd.empty?
            check_elems << OpenStudio::Attribute.new('flag', "Didn't find any of the expected winter design days for #{model_epw}")
          end

        else
          check_elems << OpenStudio::Attribute.new('flag', "#{model_epw} is not a an expected weather file.")
          check_elems << OpenStudio::Attribute.new('flag', "Model doesn't have expected epw file, as a result can't validate design days.")
          valid_climate_zones = options.map { |_lookup_epw, value| value['climate_zone'] }
        end

        # get ashrae climate zone from model
        model_climate_zone = nil
        @model.getClimateZones.climateZones.each do |climate_zone|
          if climate_zone.institution == 'ASHRAE'
            model_climate_zone = climate_zone.value
            next
          end
        end
        if model_climate_zone == ''
          check_elems << OpenStudio::Attribute.new('flag', "The model's ASHRAE climate zone has not been defined. Expected climate zone was #{valid_climate_zones.uniq.join(',')}.")
        elsif !valid_climate_zones.include?(model_climate_zone)
          check_elems << OpenStudio::Attribute.new('flag', "The model's ASHRAE climate zone was #{model_climate_zone}. Expected climate zone was #{valid_climate_zones.uniq.join(',')}.")
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end

    # checks the weather files matches the appropriate weather file for the Los Angeles zip code
    #
    # @param category [String] category to bin this check into
    # @param zip_code [String] Los Angeles zip code
    # @param name_only [Boolean] If true, only return the name of this check
    # @return [OpenStudio::Attribute] OpenStudio Attribute object containing check results
    def self.check_la_weather_files(category, zip_code, name_only: false)
      # summary of the check
      check_elems = OpenStudio::AttributeVector.new
      check_elems << OpenStudio::Attribute.new('name', 'LA Weather Files')
      check_elems << OpenStudio::Attribute.new('category', category)
      check_elems << OpenStudio::Attribute.new('description', 'Check that correct weather file was used for the selected zip code.')

      # stop here if only name is requested this is used to populate display name for arguments
      if name_only == true
        return check_elems.map(&:valueAsString)
      end

      begin
        # get weather file
        model_epw = nil
        if @model.getWeatherFile.url.is_initialized
          model_epw = @model.getWeatherFile.url.get
          model_epw = model_epw.gsub('file:', '')
          model_epw = model_epw.gsub('files/', '')
        end

        # Get the correct weather file based on the zip code
        zip_to_epw = {
          '90001' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90002' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90003' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90004' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90005' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90006' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90007' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90008' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90010' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90011' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90012' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90013' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90014' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90015' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90016' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90017' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90018' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90019' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90020' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90021' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90022' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90023' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90024' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90025' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90026' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90027' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90028' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90029' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90031' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90032' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90033' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90034' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90035' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90036' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90037' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90038' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90039' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90040' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90041' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90042' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90043' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90044' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90045' => 'USA_CA_Los.Angeles.Intl.AP.722950_TMY3.epw',
          '90046' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90047' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90048' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90049' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90056' => 'USA_CA_Los.Angeles.Intl.AP.722950_TMY3.epw',
          '90057' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90058' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90059' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90061' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90062' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90063' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90064' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90065' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90066' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90067' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90068' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90069' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90071' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90073' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90077' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90089' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90094' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90095' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90201' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90210' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90211' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90212' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '90222' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90230' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90232' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90240' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90245' => 'USA_CA_Los.Angeles.Intl.AP.722950_TMY3.epw',
          '90247' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90248' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90249' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90250' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90254' => 'USA_CA_Los.Angeles.Intl.AP.722950_TMY3.epw',
          '90255' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90260' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90262' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90263' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90265' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '90266' => 'USA_CA_Los.Angeles.Intl.AP.722950_TMY3.epw',
          '90270' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90272' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90274' => 'TORRANCE_722955_CZ2010.epw',
          '90275' => 'TORRANCE_722955_CZ2010.epw',
          '90277' => 'TORRANCE_722955_CZ2010.epw',
          '90278' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90280' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90290' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90291' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90292' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90293' => 'USA_CA_Los.Angeles.Intl.AP.722950_TMY3.epw',
          '90301' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90302' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90303' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90304' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90305' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90401' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90402' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90403' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90404' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90405' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '90501' => 'TORRANCE_722955_CZ2010.epw',
          '90502' => 'TORRANCE_722955_CZ2010.epw',
          '90503' => 'TORRANCE_722955_CZ2010.epw',
          '90504' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90505' => 'TORRANCE_722955_CZ2010.epw',
          '90506' => 'USA_CA_Hawthorne-Jack.Northrop.Field.722956_TMY3.epw',
          '90601' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90602' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90603' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90604' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90605' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90606' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90621' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90631' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90638' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90639' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90640' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90650' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90660' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90670' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '90680' => 'TORRANCE_722955_CZ2010.epw',
          '90710' => 'TORRANCE_722955_CZ2010.epw',
          '90717' => 'TORRANCE_722955_CZ2010.epw',
          '90720' => 'TORRANCE_722955_CZ2010.epw',
          '90731' => 'TORRANCE_722955_CZ2010.epw',
          '90732' => 'TORRANCE_722955_CZ2010.epw',
          '90740' => 'TORRANCE_722955_CZ2010.epw',
          '90742' => 'TORRANCE_722955_CZ2010.epw',
          '90743' => 'TORRANCE_722955_CZ2010.epw',
          '90744' => 'TORRANCE_722955_CZ2010.epw',
          '90745' => 'TORRANCE_722955_CZ2010.epw',
          '90746' => 'TORRANCE_722955_CZ2010.epw',
          '90755' => 'TORRANCE_722955_CZ2010.epw',
          '90802' => 'TORRANCE_722955_CZ2010.epw',
          '90803' => 'TORRANCE_722955_CZ2010.epw',
          '90804' => 'TORRANCE_722955_CZ2010.epw',
          '90806' => 'TORRANCE_722955_CZ2010.epw',
          '90807' => 'TORRANCE_722955_CZ2010.epw',
          '90810' => 'TORRANCE_722955_CZ2010.epw',
          '90813' => 'TORRANCE_722955_CZ2010.epw',
          '90814' => 'TORRANCE_722955_CZ2010.epw',
          '90815' => 'TORRANCE_722955_CZ2010.epw',
          '90840' => 'TORRANCE_722955_CZ2010.epw',
          '91001' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91006' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91007' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91008' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91010' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91011' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91016' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91020' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91024' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91030' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91040' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91042' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91101' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91103' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91104' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91105' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91106' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91107' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91108' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91123' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91201' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91202' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91203' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91204' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91205' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91206' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91207' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91208' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91214' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91301' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91302' => 'USA_CA_Santa.Monica.Muni.AP.722885_TMY3.epw',
          '91303' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91304' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91306' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91307' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91311' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91316' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91320' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91321' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91324' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91325' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91326' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91330' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91331' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91335' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91340' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91342' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91343' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91344' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91345' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91350' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91351' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91352' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91354' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91355' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91356' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91360' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91361' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91362' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91364' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91367' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91371' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91377' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91381' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91384' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91387' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91390' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91401' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91402' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91403' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91405' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91406' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91411' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91423' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91436' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '91501' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91502' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91504' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91505' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91506' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91521' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91522' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91523' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91601' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91602' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91604' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91605' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91606' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91607' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91608' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw',
          '91702' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91706' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91709' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91710' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91711' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91722' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91723' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91724' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91731' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91732' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91733' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91740' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91741' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91744' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91745' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91746' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91748' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91750' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91754' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91755' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91763' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91765' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91766' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91767' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91768' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91770' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91773' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91775' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91776' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91780' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91784' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91789' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91790' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91791' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91792' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91801' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '91803' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '92603' => 'TORRANCE_722955_CZ2010.epw',
          '92612' => 'TORRANCE_722955_CZ2010.epw',
          '92614' => 'TORRANCE_722955_CZ2010.epw',
          '92617' => 'TORRANCE_722955_CZ2010.epw',
          '92624' => 'TORRANCE_722955_CZ2010.epw',
          '92625' => 'TORRANCE_722955_CZ2010.epw',
          '92626' => 'TORRANCE_722955_CZ2010.epw',
          '92627' => 'TORRANCE_722955_CZ2010.epw',
          '92629' => 'TORRANCE_722955_CZ2010.epw',
          '92637' => 'TORRANCE_722955_CZ2010.epw',
          '92646' => 'TORRANCE_722955_CZ2010.epw',
          '92647' => 'TORRANCE_722955_CZ2010.epw',
          '92648' => 'TORRANCE_722955_CZ2010.epw',
          '92649' => 'TORRANCE_722955_CZ2010.epw',
          '92651' => 'TORRANCE_722955_CZ2010.epw',
          '92653' => 'TORRANCE_722955_CZ2010.epw',
          '92655' => 'TORRANCE_722955_CZ2010.epw',
          '92656' => 'TORRANCE_722955_CZ2010.epw',
          '92657' => 'TORRANCE_722955_CZ2010.epw',
          '92660' => 'TORRANCE_722955_CZ2010.epw',
          '92661' => 'TORRANCE_722955_CZ2010.epw',
          '92662' => 'TORRANCE_722955_CZ2010.epw',
          '92663' => 'TORRANCE_722955_CZ2010.epw',
          '92672' => 'TORRANCE_722955_CZ2010.epw',
          '92673' => 'TORRANCE_722955_CZ2010.epw',
          '92675' => 'TORRANCE_722955_CZ2010.epw',
          '92677' => 'TORRANCE_722955_CZ2010.epw',
          '92683' => 'TORRANCE_722955_CZ2010.epw',
          '92691' => 'TORRANCE_722955_CZ2010.epw',
          '92692' => 'TORRANCE_722955_CZ2010.epw',
          '92697' => 'TORRANCE_722955_CZ2010.epw',
          '92703' => 'TORRANCE_722955_CZ2010.epw',
          '92704' => 'TORRANCE_722955_CZ2010.epw',
          '92707' => 'TORRANCE_722955_CZ2010.epw',
          '92708' => 'TORRANCE_722955_CZ2010.epw',
          '92821' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '92823' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '92833' => 'LOS-ANGELES-DOWNTOWN_722874_CZ2010.epw',
          '92841' => 'TORRANCE_722955_CZ2010.epw',
          '92843' => 'TORRANCE_722955_CZ2010.epw',
          '92844' => 'TORRANCE_722955_CZ2010.epw',
          '92845' => 'TORRANCE_722955_CZ2010.epw',
          '93001' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93003' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93004' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93012' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93013' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93015' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93021' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93022' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93023' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93060' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93063' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93065' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93066' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93108' => 'USA_CA_Van.Nuys.AP.722886_TMY3.epw',
          '93510' => 'USA_CA_Burbank-Glendale-Pasadena.Bob.Hope.AP.722880_ TMY3.epw'
        }

        correct_epw = zip_to_epw[zip_code]
        if correct_epw.nil?
          check_elems << OpenStudio::Attribute.new('flag', "There is no correct weather file specified for the zip code #{zip_code}")
        end

        unless model_epw == correct_epw
          check_elems << OpenStudio::Attribute.new('flag', "The selected weather file #{model_epw} is incorrect for zip code #{zip_code}.  The correct weather file is #{correct_epw}.")
        end
      rescue StandardError => e
        # brief description of ruby error
        check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

        # backtrace of ruby error for diagnostic use
        if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
      end

      # add check_elms to new attribute
      check_elem = OpenStudio::Attribute.new('check', check_elems)

      return check_elem
    end
  end
end
