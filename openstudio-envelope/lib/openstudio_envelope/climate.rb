require 'json'

module OpenStudioEnvelope
  # HDD18 resolution for envelope rules, mirroring legacy get_necb_hdd18
  # (necb_2011.rb:196): an explicit value wins; else the nearest NECB Table C-1
  # city (haversine on the weather file's coordinates, 500 km tolerance); else
  # the .stat file's annual (wthr file) heating degree-days at the 18 C baseline.
  module Climate
    module_function

    TABLE_C1_PATH = File.expand_path('data/necb/table_c1.json', __dir__)
    TOLERANCE_KM = 500.0

    def table_c1
      @table_c1 ||= JSON.parse(File.read(TABLE_C1_PATH))['table']
    end

    # @return [Numeric, nil] HDD18; nil (with an audit warning) when unresolvable
    def hdd18(model, hdd: nil, audit: nil)
      if hdd
        audit&.info(:climate, 'HDD supplied explicitly', value: hdd)
        return hdd
      end

      weather = model.weatherFile
      unless weather.is_initialized && weather.get.path.is_initialized
        audit&.warn(:climate, 'no weather file on model — HDD unresolvable (pass hdd: explicitly)')
        return nil
      end

      from_city = nearest_city_hdd(weather.get, audit)
      return from_city if from_city

      from_stat = stat_hdd18(weather.get.path.get.to_s, audit)
      return from_stat if from_stat

      audit&.warn(:climate, 'HDD unresolvable: no Table C-1 city within tolerance and no parsable .stat file')
      nil
    end

    # Nearest NECB Table C-1 city by haversine distance (legacy convention).
    def nearest_city_hdd(weather_file, audit)
      lat = weather_file.latitude
      lon = weather_file.longitude
      best = table_c1.min_by { |row| haversine_km([lat, lon], row['lat_long']) }
      distance = haversine_km([lat, lon], best['lat_long'])
      if distance > TOLERANCE_KM
        audit&.info(:climate, 'nearest Table C-1 city beyond tolerance — falling back to .stat HDD',
                    inputs: { nearest: "#{best['city']}, #{best['province']}", distance_km: distance.round(1) })
        return nil
      end

      audit&.decision(:climate, 'HDD from nearest NECB Table C-1 city',
                      inputs: { city: "#{best['city']}, #{best['province']}", distance_km: distance.round(1) },
                      value: best['degree_days_below_18_c'],
                      article: 'NECB Table C-1 (legacy get_necb_hdd18 convention)')
      best['degree_days_below_18_c']
    end

    # Annual (wthr file) HDD at the 18 C baseline from the .stat beside the EPW.
    def stat_hdd18(epw_path, audit)
      stat_path = epw_path.sub(/\.epw\z/i, '.stat')
      return nil unless File.exist?(stat_path)

      text = File.read(stat_path, encoding: 'ISO-8859-1').encode('UTF-8', invalid: :replace, undef: :replace)
      match = text.match(/-\s*(\d+)\s*annual\s*\(wthr file\)\s*heating degree-days\s*\(18.*?C baseline\)/)
      return nil if match.nil?

      value = match[1].to_i
      audit&.decision(:climate, 'HDD from .stat file (annual wthr-file, 18 C baseline)',
                      inputs: { stat: File.basename(stat_path) }, value: value)
      value
    end

    def haversine_km(a, b)
      rad = Math::PI / 180
      dlat = (b[0] - a[0]) * rad
      dlon = (b[1] - a[1]) * rad
      h = Math.sin(dlat / 2)**2 + Math.cos(a[0] * rad) * Math.cos(b[0] * rad) * Math.sin(dlon / 2)**2
      6371.0 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h))
    end
  end
end
