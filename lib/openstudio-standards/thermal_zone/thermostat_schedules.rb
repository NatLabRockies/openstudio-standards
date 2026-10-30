module OpenstudioStandards
  # The ThermalZone module provides methods to set thermostats and get information about model thermal zones
  module ThermalZone
    # Path to the setpoint data used to build thermostat schedules
    THERMOSTAT_SETPOINTS_PATH = File.join(__dir__, 'data', 'thermostat_setpoints.json')

    # Setpoint fields a thermostat override may set
    THERMOSTAT_OVERRIDE_FIELDS = %i[
      heating_setpoint_c heating_setback_delta_c cooling_setpoint_c cooling_setback_delta_c
    ].freeze

    # Heating and cooling setpoints and setback deltas for one all-level space type.
    #
    # A building-type-qualified space type ('corridor - primary school') falls back to its
    # base type when it has no entry of its own.
    #
    # The data keys on the space type alone. Where a model needs different setpoints for a
    # space type -- warehouse storage held as an unheated bulk store rather than as the
    # storage room the stock data describes -- it says so through thermostat_overrides
    # rather than through anything encoded here.
    #
    # @param space_type_name [String] all-level space type name
    # @return [Hash, nil] setpoint record, or nil when the space type has no data
    def self.space_type_thermostat_setpoints(space_type_name)
      @thermostat_setpoints ||= JSON.parse(File.read(THERMOSTAT_SETPOINTS_PATH), symbolize_names: true)[:space_types]
      record = @thermostat_setpoints.find { |row| row[:space_type_name] == space_type_name }
      return record unless record.nil?
      return nil unless space_type_name.include?(' - ')

      base = space_type_name.split(' - ').first
      @thermostat_setpoints.find { |row| row[:space_type_name] == base }
    end

    # Apply runtime thermostat overrides to a space type's setpoint record.
    #
    # Entries are matched the same way schedule and load overrides are: by schedule set
    # name, all-level space type, ventilation space type, or the '*' wildcard, with a specific entry winning over
    # the wildcard. Fields are overridden individually, so an entry may raise a cooling
    # setpoint without restating the heating side.
    #
    # An override may name a space type the setpoint data has no record for, in which case
    # it has to supply both setpoints itself; a partial override of an unknown space type
    # cannot be built into a thermostat and is skipped with a warning.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @param space_type_name [String] all-level space type name
    # @param thermostat_overrides [Array<Hash>, nil] override entries
    # @return [Hash, nil] setpoint record, or nil when the space type has no setpoints
    def self.space_type_thermostat_setpoints_with_overrides(space_type, space_type_name, thermostat_overrides)
      record = OpenstudioStandards::ThermalZone.space_type_thermostat_setpoints(space_type_name)
      return record if thermostat_overrides.nil? || thermostat_overrides.empty?

      overrides = OpenstudioStandards::CreateTypical.resolve_overrides(thermostat_overrides, space_type,
                                                                      section_keys: [:thermostat],
                                                                      extra_names: [space_type_name])[:thermostat]
      return record if overrides.nil? || overrides.empty?

      # an entry that only speaks to continuous_operation is an operation override, read by
      # CreateTypical.space_type_apply_operation_overrides, and leaves the setpoints alone
      setpoint_overrides = overrides.select { |key, _| THERMOSTAT_OVERRIDE_FIELDS.include?(key) }
      return record if setpoint_overrides.empty?

      merged = (record || {}).merge(setpoint_overrides)
      if merged[:heating_setpoint_c].nil? || merged[:cooling_setpoint_c].nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone',
                           "Thermostat override for '#{space_type_name}' sets no setpoints and the space type has none of its own. Ignoring the override.")
        return record
      end

      # a setback the override did not speak to defaults to none rather than to the
      # setback of a setpoint that is no longer there
      merged[:heating_setback_delta_c] = merged[:heating_setback_delta_c].to_f
      merged[:cooling_setback_delta_c] = merged[:cooling_setback_delta_c].to_f
      merged
    end

    # Combine several setpoint records into the most restrictive of each field: the highest
    # heating setpoint and the lowest cooling setpoint, and the setbacks that keep the zone
    # closest to those setpoints when it is unoccupied.
    #
    # A zone holding more than one space type has to be conditioned for the tightest of
    # them, since one thermostat serves the whole zone.
    #
    # @param records [Array<Hash>] setpoint records
    # @return [Hash, nil] combined record, or nil when given nothing
    def self.most_restrictive_thermostat_setpoints(records)
      records = records.compact
      return nil if records.empty?
      return enforce_minimum_deadband(records.first) if records.size == 1

      heating = records.map { |record| record[:heating_setpoint_c].to_f }.max
      cooling = records.map { |record| record[:cooling_setpoint_c].to_f }.min
      # the setback temperature itself is what has to be most restrictive, not the delta
      heating_setback = records.map { |record| record[:heating_setpoint_c].to_f - record[:heating_setback_delta_c].to_f }.max
      cooling_setback = records.map { |record| record[:cooling_setpoint_c].to_f + record[:cooling_setback_delta_c].to_f }.min

      enforce_minimum_deadband({
        heating_setpoint_c: heating,
        heating_setback_delta_c: [heating - heating_setback, 0.0].max,
        cooling_setpoint_c: cooling,
        cooling_setback_delta_c: [cooling_setback - cooling, 0.0].max
      })
    end

    # The narrowest heating-to-cooling gap a thermostat record may carry into a schedule.
    # Set just under the 1.1 K the patient room and emergency room rows legitimately hold.
    MINIMUM_DEADBAND_K = 1.0

    # Widen a record whose heating and cooling setpoints leave less than the minimum
    # deadband, lowering the heating setpoint - the same side the ComStock setpoint
    # variability rules yield on.
    #
    # A zone asked to hold heating and cooling at the same temperature flips its terminal
    # between the two demands every HVAC iteration. On a hospital model that knife edge
    # cost an 80x slower sizing run, five of six sizing environments at the full 25-day
    # warmup budget, and every SimHVAC max-iteration event on the loop serving those zones.
    # The setpoint data no longer carries such a pair, but the taking of max-heating and
    # min-cooling across a mixed zone can manufacture one from two healthy records, and a
    # runtime thermostat_override can state one directly - this is the floor under both.
    # The heating setback temperature is preserved, so only the occupied setpoint moves.
    #
    # @param record [Hash] setpoint record
    # @return [Hash] the record itself when the deadband is respected, else a widened copy
    def self.enforce_minimum_deadband(record)
      heating = record[:heating_setpoint_c].to_f
      cooling = record[:cooling_setpoint_c].to_f
      return record if cooling - heating >= MINIMUM_DEADBAND_K

      lowered = cooling - MINIMUM_DEADBAND_K
      setback_temperature = heating - record[:heating_setback_delta_c].to_f
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone',
                         "Heating setpoint of #{heating.round(2)} C leaves less than #{MINIMUM_DEADBAND_K} K below the " \
                         "cooling setpoint of #{cooling.round(2)} C. Using #{lowered.round(2)} C for heating.")
      record.merge(heating_setpoint_c: lowered,
                   heating_setback_delta_c: [lowered - setback_temperature, 0.0].max)
    end

    # Build a thermostat setpoint schedule around a set of operating hours.
    #
    # Outside operating hours the schedule sits at the setback value, which is the setpoint
    # offset by the space type's setback delta -- below it for heating, above it for
    # cooling. A delta of 0 gives a constant schedule. Design days hold the setpoint all
    # day, since sizing should not see the setback.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String] schedule name
    # @param setpoint [Double] occupied setpoint, degrees C
    # @param setback_delta [Double] setback distance from the setpoint, degrees C
    # @param heating [Boolean] true for a heating setpoint schedule, false for cooling
    # @param hours [Hash] :wkdy_start, :wkdy_end, :wknd_start, :wknd_end in decimal hours
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.create_thermostat_schedule(model, name:, setpoint:, setback_delta:, heating:, hours:)
      setback = heating ? setpoint - setback_delta : setpoint + setback_delta

      day_pairs = lambda do |start_hour, end_hour|
        # a zero-length or full-day occupied period collapses to a constant profile
        return [[24.0, setpoint]] if start_hour <= 0.0 && end_hour >= 24.0
        return [[24.0, setback]] if end_hour <= start_hour

        pairs = []
        pairs << [start_hour, setback] if start_hour > 0.0
        pairs << [end_hour, setpoint]
        pairs << [24.0, setback] if end_hour < 24.0
        pairs
      end

      # create_complex_schedule splits the day-type field on '/', not '|', and prefixes the
      # rule name with the ruleset's own -- so 'Sat|Sun' silently matches nothing, leaving a
      # rule that applies to no day and a weekday profile running all seven.
      options = {
        'name' => name,
        'winter_design_day' => [[24.0, setpoint]],
        'summer_design_day' => [[24.0, setpoint]],
        'default_day' => ['Weekday'] + day_pairs.call(hours[:wkdy_start], hours[:wkdy_end]),
        'rules' => [['Weekend', '1/1-12/31', 'Sat/Sun'] + day_pairs.call(hours[:wknd_start], hours[:wknd_end])]
      }

      schedule = OpenstudioStandards::Schedules.create_complex_schedule(model, options)
      limits = OpenstudioStandards::Schedules.create_schedule_type_limits(model, standard_schedule_type_limit: 'Temperature')
      schedule.setScheduleTypeLimits(limits)
      schedule
    end

    # Operating hours to build a space type's thermostat schedule around.
    #
    # Explicit hours win, so a caller that knows the building's operating hours -- as
    # create_typical_building_from_model does -- gets thermostats that match them. Without
    # them the space type's own parametric occupancy schedule supplies st_std and et_std,
    # which is the same start and end the occupancy profile is drawn around, so the
    # thermostat follows occupancy rather than a prototype's fixed hours.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @param explicit [Hash] :wkdy_start, :wkdy_end, :wknd_start, :wknd_end, any may be nil
    # @return [Hash] :wkdy_start, :wkdy_end, :wknd_start, :wknd_end in decimal hours
    def self.thermostat_operating_hours(space_type, explicit = {})
      hours = { wkdy_start: 8.0, wkdy_end: 18.0, wknd_start: 8.0, wknd_end: 18.0 }

      occupancy = space_type_occupancy_standard_times(space_type)
      hours = hours.merge(occupancy) unless occupancy.nil?

      explicit.each { |key, value| hours[key] = value.to_f unless value.nil? }
      hours
    end

    # Standard start and end times from a space type's parametric occupancy schedule.
    #
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @return [Hash, nil] :wkdy_start, :wkdy_end, :wknd_start, :wknd_end, or nil when the
    #   space type has no schedule set or its set names no occupancy schedule
    def self.space_type_occupancy_standard_times(space_type)
      return nil unless space_type.additionalProperties.getFeatureAsString('schedule_set').is_initialized

      schedule_set_name = space_type.additionalProperties.getFeatureAsString('schedule_set').get
      @parametric_sets ||= JSON.parse(
        File.read(File.join(__dir__, '..', 'schedules', 'data', 'default_parametric_schedule_set.json')),
        symbolize_names: true
      )
      set = @parametric_sets.find { |row| row[:schedule_set_name] == schedule_set_name }
      return nil if set.nil?

      occupancy_name = set[:occupancy_schedule]
      return nil if occupancy_name.nil? || occupancy_name.to_s.empty? || occupancy_name.to_s == 'None'

      @occupancy_schedules ||= begin
        parsed = JSON.parse(
          File.read(File.join(__dir__, '..', 'schedules', 'data', 'default_occupancy_schedules.json')),
          symbolize_names: true
        )
        parsed.is_a?(Hash) ? parsed[:schedules] : parsed
      end
      rows = @occupancy_schedules.select { |row| row[:name] == occupancy_name }
      return nil if rows.empty?

      weekday = rows.find { |row| row[:day_types].to_s.include?('Default') } || rows.first
      weekend = rows.find { |row| row[:day_types].to_s =~ /Sat|Sun/ } || weekday
      return nil if weekday[:st_std].nil? || weekday[:et_std].nil?

      {
        wkdy_start: weekday[:st_std].to_f,
        wkdy_end: weekday[:et_std].to_f,
        wknd_start: (weekend[:st_std] || weekday[:st_std]).to_f,
        wknd_end: (weekend[:et_std] || weekday[:et_std]).to_f
      }
    end

    # The widest occupied window across a set of operating hours.
    #
    # A zone whose space types keep different hours has to hold its occupied setpoints for
    # all of them, so the combined window opens with the earliest start and closes with the
    # latest end.
    #
    # @param hours [Array<Hash>] :wkdy_start, :wkdy_end, :wknd_start, :wknd_end entries
    # @return [Hash, nil] combined hours, or nil when given nothing
    def self.widest_operating_hours(hours)
      hours = hours.compact
      return nil if hours.empty?
      return hours.first if hours.size == 1

      {
        wkdy_start: hours.map { |entry| entry[:wkdy_start] }.min,
        wkdy_end: hours.map { |entry| entry[:wkdy_end] }.max,
        wknd_start: hours.map { |entry| entry[:wknd_start] }.min,
        wknd_end: hours.map { |entry| entry[:wknd_end] }.max
      }
    end

    # The most restrictive of a set of setpoint schedules: the one that holds the highest
    # heating setpoint, or the lowest cooling setpoint.
    #
    # @param schedules [Array<OpenStudio::Model::Schedule, nil>] candidate schedules
    # @param heating [Boolean] true to compare heating schedules, false for cooling
    # @return [OpenStudio::Model::Schedule, nil] the winner, or nil when given nothing
    def self.most_restrictive_thermostat_schedule(schedules, heating:)
      schedules = schedules.compact
      return nil if schedules.empty?
      return schedules.first if schedules.size == 1

      extreme = lambda do |schedule|
        values = OpenstudioStandards::Schedules.schedule_get_min_max(schedule)
        value = heating ? values['max'] : values['min']
        # a schedule whose values cannot be read must not win the comparison
        value.nil? ? (heating ? -Float::INFINITY : Float::INFINITY) : value
      end

      heating ? schedules.max_by(&extreme) : schedules.min_by(&extreme)
    end

    # A setpoint schedule for one set of setpoints and hours, built once per model.
    #
    # Thermostats are per zone but their schedules need not be: two zones asking for the
    # same setpoints over the same hours get the same schedule object. Without this, a
    # 183-zone hospital built 366 ScheduleRulesets where a few dozen would do, and since
    # the schedule helpers scan the model by name, the cost grew with the square of the
    # object count -- that building alone took 24 times longer to construct than it had
    # when schedules were shared, and dragged sizing and hard sizing along with it.
    #
    # Sharing is how the prototype path has always worked; per-zone duplication was the
    # anomaly. A ScheduleRuleset is a shared resource, so a thermostat referencing one is
    # no different from a thermostat referencing a named prototype schedule.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param cache [Hash] per-call store of schedules already built
    # @param setpoint [Double] occupied setpoint, degrees C
    # @param setback_delta [Double] setback distance from the setpoint, degrees C
    # @param heating [Boolean] true for a heating setpoint schedule, false for cooling
    # @param hours [Hash] :wkdy_start, :wkdy_end, :wknd_start, :wknd_end in decimal hours
    # @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
    def self.thermostat_schedule_for(model, cache, setpoint:, setback_delta:, heating:, hours:)
      # the name states what the schedule is, so it doubles as the cache key
      name = format('%s Setp %.2fC setback %.2fC %g-%g wknd %g-%g',
                    heating ? 'Htg' : 'Clg', setpoint.to_f, setback_delta.to_f,
                    hours[:wkdy_start], hours[:wkdy_end], hours[:wknd_start], hours[:wknd_end])

      # a Model has no handle of its own; its Building is the stable per-model identity
      cache[[model.getBuilding.handle.to_s, name]] ||= OpenstudioStandards::ThermalZone.create_thermostat_schedule(
        model, name: name, setpoint: setpoint, setback_delta: setback_delta, heating: heating, hours: hours
      )
    end

    # The named heating and cooling setpoint schedules for a space type the setpoint data
    # does not cover, from the prototype thermostat schedule lookup.
    #
    # @param std [Standard] Standard object, for model_add_schedule
    # @param thermostat_data [Array<Hash>] parsed thermostat_schedule_lookup rows
    # @param space_type [OpenStudio::Model::SpaceType] OpenStudio SpaceType object
    # @param space_type_name [String] standards space type name
    # @return [Array<OpenStudio::Model::Schedule, nil>] heating and cooling schedules
    def self.space_type_named_thermostat_schedules(std, thermostat_data, space_type, space_type_name)
      space_type_data = thermostat_data.select { |row| row[:space_type] == space_type_name }

      # Fall back to the unqualified space type. This data is keyed on the level-1 names
      # only, so a building-type-qualified space type such as 'corridor - primary school'
      # matches nothing and the zone ends up with a thermostat carrying no schedules,
      # which is an EnergyPlus fatal downstream. The qualified variants are refinements
      # of their base type, so the base thermostat schedule is the right default.
      if space_type_data.empty? && space_type_name.include?(' - ')
        base_space_type_name = space_type_name.split(' - ').first
        space_type_data = thermostat_data.select { |row| row[:space_type] == base_space_type_name }
        unless space_type_data.empty?
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone',
                             "No thermostat schedule data for '#{space_type_name}', using '#{base_space_type_name}'.")
        end
      end

      if space_type_data.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone',
                           "No thermostat schedule data for space type '#{space_type_name}'. The zone will be left without setpoint schedules.")
        return [nil, nil]
      end

      # get unique possible heating and cooling setpoint schedules
      heating_names = space_type_data.map { |row| row[:heating_setpoint_schedule] }.compact.uniq
      cooling_names = space_type_data.map { |row| row[:cooling_setpoint_schedule] }.compact.uniq

      if (heating_names.size < 2) && (cooling_names.size < 2)
        heating_name = heating_names[0]
        cooling_name = cooling_names[0]
      elsif space_type.standardsBuildingType.is_initialized
        # select down to building type; the data uses standards lookup names, e.g. 'Office' for 'MediumOffice'
        lookup_building_type = std.model_get_lookup_name(space_type.standardsBuildingType.get)
        building_type_data = space_type_data.select { |row| row[:standards_building_type] == lookup_building_type }
        if building_type_data.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone', "No thermostat schedule data is available for space type '#{space_type.name}' with standards space type #{space_type_name} and standards building type #{space_type.standardsBuildingType.get}. Using a default schedule for this space type.")
          building_type_data = [space_type_data[0]]
        end
        heating_name = building_type_data[0][:heating_setpoint_schedule]
        cooling_name = building_type_data[0][:cooling_setpoint_schedule]
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone', "Multiple thermostat schedules are available for space type '#{space_type.name} with standards space type #{space_type_name} depending on building type, but building type is not specified. Using a default schedule for this space type.")
        heating_name = space_type_data[0][:heating_setpoint_schedule]
        cooling_name = space_type_data[0][:cooling_setpoint_schedule]
      end

      model = space_type.model
      [named_schedule(std, model, heating_name), named_schedule(std, model, cooling_name)]
    end

    # A named schedule from the standards data, or nil when the standards have no such
    # schedule. model_add_schedule answers a missing name with the always-on fractional
    # schedule, which as a setpoint schedule would hold the zone at 1 C -- and, being the
    # lowest cooling setpoint in the model, would win any most-restrictive comparison it
    # took part in.
    #
    # @param std [Standard] Standard object
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param name [String, nil] schedule name
    # @return [OpenStudio::Model::Schedule, nil] the schedule, or nil when it is unknown
    def self.named_schedule(std, model, name)
      return nil if name.nil?

      schedule = std.model_add_schedule(model, name)
      return nil if schedule.nil? || !schedule.respond_to?(:name)
      return schedule if schedule.name.get.to_s == name

      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone',
                         "The standards have no thermostat schedule named '#{name}'. Ignoring it rather than using the schedule returned in its place.")
      nil
    end

    # Adds thermostats to thermal zones based on the standards space types they hold.
    #
    # Each zone gets its own thermostat and its own pair of setpoint schedules. Where a zone
    # holds more than one space type the schedules are built from the most restrictive
    # setpoints among them -- the highest heating setpoint and the lowest cooling setpoint,
    # over the widest occupied window -- since one thermostat serves the whole zone.
    #
    # Setpoints come from the space type setpoint data, adjusted by any thermostat
    # overrides, and the schedules are built around the operating hours given, falling back
    # to the space type's parametric occupancy start and end times. A space type the
    # setpoint data does not cover falls back to the prototype named schedule lookup; those
    # named schedules are compared against each other, and against anything built from
    # setpoints, on the same most-restrictive basis.
    #
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] OpenStudio ThermalZone objects
    # @param wkdy_op_hrs_start_time [Double] weekday operating hours start, decimal hours
    # @param wkdy_op_hrs_duration [Double] weekday operating hours duration, decimal hours
    # @param wknd_op_hrs_start_time [Double] weekend operating hours start, decimal hours
    # @param wknd_op_hrs_duration [Double] weekend operating hours duration, decimal hours
    # @param thermostat_overrides [Array<Hash>, nil] runtime setpoint overrides. Each entry
    #   is keyed by `space_type` (matched against the schedule set name or the standards
    #   space type) or `"*"`, with a `thermostat` hash of setpoint fields that override the
    #   space type's own at field granularity.
    # @return [Boolean] returns true if successful, false if not
    def self.thermal_zones_set_thermostat_schedules(thermal_zones,
                                                    wkdy_op_hrs_start_time: nil,
                                                    wkdy_op_hrs_duration: nil,
                                                    wknd_op_hrs_start_time: nil,
                                                    wknd_op_hrs_duration: nil,
                                                    thermostat_overrides: nil)
      explicit_hours = {
        wkdy_start: wkdy_op_hrs_start_time,
        wkdy_end: (wkdy_op_hrs_start_time && wkdy_op_hrs_duration) ? wkdy_op_hrs_start_time.to_f + wkdy_op_hrs_duration.to_f : nil,
        wknd_start: wknd_op_hrs_start_time,
        wknd_end: (wknd_op_hrs_start_time && wknd_op_hrs_duration) ? wknd_op_hrs_start_time.to_f + wknd_op_hrs_duration.to_f : nil
      }
      # load and return thermostat mapping data
      thermostat_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/../prototypes/common/data/thermostat_schedule_lookup.json"), symbolize_names: true)

      # std call to access model_add_schedule
      # @todo refactor once schedule data is separate
      std = Standard.build('90.1-2013')

      # setpoint schedules shared between zones that ask for the same thing
      schedule_cache = {}

      # space types with people or lighting that resolved to no thermostat at all: the zone
      # is built unconditioned, which is a data gap rather than a decision, and is said once
      unconditioned_space_types = []

      thermal_zones.each do |thermal_zone|
        # skip plenums
        if OpenstudioStandards::ThermalZone.thermal_zone_plenum?(thermal_zone)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone', "Thermal Zone '#{thermal_zone.name}' is a plenum. Not adding thermostat schedules.")
          next
        end

        # get space types
        thermal_zone_space_types = []
        thermal_zone.spaces.each do |space|
          thermal_zone_space_types << space.spaceType.get if space.spaceType.is_initialized
        end
        thermal_zone_space_types = thermal_zone_space_types.uniq { |space_type| space_type.handle.to_s }
        if thermal_zone_space_types.empty?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "Thermal zone #{thermal_zone.name} has no space types. Not adding thermostat schedules.")
          next
        end

        # check if additional properties set, and if not add it
        unless thermal_zone_space_types[0].additionalProperties.hasFeature('standards_space_type')
          OpenstudioStandards::SpaceType.set_standards_space_type_additional_properties(thermal_zone.model)
        end

        model = thermal_zone.model
        setpoint_records = []
        hours_options = []
        named_schedules = []

        thermal_zone_space_types.each do |space_type|
          # get the standards space type
          space_type_name = space_type.additionalProperties.getFeatureAsString('standards_space_type').get

          # Build the thermostat from setpoint data where the space type has it, so the
          # schedule follows the model's operating hours instead of a prototype's.
          setpoints = OpenstudioStandards::ThermalZone.space_type_thermostat_setpoints_with_overrides(space_type, space_type_name, thermostat_overrides)
          if setpoints.nil?
            named_schedules << OpenstudioStandards::ThermalZone.space_type_named_thermostat_schedules(std, thermostat_data, space_type, space_type_name)
            next
          end

          setpoint_records << setpoints
          hours_options << OpenstudioStandards::ThermalZone.thermostat_operating_hours(space_type, explicit_hours)
        end

        heating_schedule = nil
        cooling_schedule = nil
        unless setpoint_records.empty?
          setpoints = OpenstudioStandards::ThermalZone.most_restrictive_thermostat_setpoints(setpoint_records)
          hours = OpenstudioStandards::ThermalZone.widest_operating_hours(hours_options)
          if setpoint_records.size > 1
            OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.ThermalZone',
                               "Thermal zone #{thermal_zone.name} holds #{setpoint_records.size} space types; using setpoints of #{setpoints[:heating_setpoint_c].round(2)} C heating and #{setpoints[:cooling_setpoint_c].round(2)} C cooling.")
          end
          heating_schedule = OpenstudioStandards::ThermalZone.thermostat_schedule_for(
            model, schedule_cache, heating: true, hours: hours,
                   setpoint: setpoints[:heating_setpoint_c], setback_delta: setpoints[:heating_setback_delta_c]
          )
          cooling_schedule = OpenstudioStandards::ThermalZone.thermostat_schedule_for(
            model, schedule_cache, heating: false, hours: hours,
                   setpoint: setpoints[:cooling_setpoint_c], setback_delta: setpoints[:cooling_setback_delta_c]
          )
        end

        # fold in the named schedules on the same most restrictive basis
        heating_schedule = OpenstudioStandards::ThermalZone.most_restrictive_thermostat_schedule(
          named_schedules.map(&:first) << heating_schedule, heating: true
        )
        cooling_schedule = OpenstudioStandards::ThermalZone.most_restrictive_thermostat_schedule(
          named_schedules.map(&:last) << cooling_schedule, heating: false
        )

        if heating_schedule.nil? && cooling_schedule.nil?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.ThermalZone', "Unable to find valid thermostat options for thermal zone #{thermal_zone.name} depending on space types.")
          loaded = thermal_zone.spaces.any? { |space| space.numberOfPeople > 0.0 || space.lightingPower > 0.0 }
          unconditioned_space_types.concat(thermal_zone_space_types.map { |space_type| space_type.name.to_s }) if loaded
          next
        end

        thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
        thermostat.setName("#{thermal_zone.name} Thermostat")
        thermostat.setHeatingSetpointTemperatureSchedule(heating_schedule) unless heating_schedule.nil?
        thermostat.setCoolingSetpointTemperatureSchedule(cooling_schedule) unless cooling_schedule.nil?
        thermal_zone.setThermostatSetpointDualSetpoint(thermostat)
      end

      # A gym floor built without a thermostat because 'playing area' had no setpoint record
      # went through a validation run unconditioned, with its people, lights and
      # outdoor air requirement still counted. Name the gap once, at warning level.
      unless unconditioned_space_types.empty?
        names = unconditioned_space_types.uniq.sort
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ThermalZone',
                           "#{names.size} space type(s) with people or lighting resolved to no thermostat setpoint data and their zones are built unconditioned: #{names.join(', ')}. Add a record to thermostat_setpoints.json or a thermostat_overrides entry with both setpoints.")
      end

      return true
    end

    # Adds thermostat schedules with a 0F heating setpoint and 120F cooling setpoint.
    # These numbers are outside of the threshold that is considered heated or cooled by thermal_zone_heated? and thermal_zone_cooled?
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Boolean] returns true if successful, false if not
    def self.thermal_zone_set_unconditioned_thermostat(thermal_zone)
      # Heated to 0F (below thermal_zone_heated?(thermal_zone)  threshold)
      htg_t_f = 0.0
      htg_t_c = OpenStudio.convert(htg_t_f, 'F', 'C').get
      htg_stpt_sch = OpenStudio::Model::ScheduleRuleset.new(thermal_zone.model)
      htg_stpt_sch.setName('Unconditioned Minimal Heating')
      htg_stpt_sch.defaultDaySchedule.setName('Unconditioned Minimal Heating Default')
      htg_stpt_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), htg_t_c)

      # Cooled to 120F (above thermal_zone_cooled?(thermal_zone)  threshold)
      clg_t_f = 120.0
      clg_t_c = OpenStudio.convert(clg_t_f, 'F', 'C').get
      clg_stpt_sch = OpenStudio::Model::ScheduleRuleset.new(thermal_zone.model)
      clg_stpt_sch.setName('Unconditioned Minimal Cooling')
      clg_stpt_sch.defaultDaySchedule.setName('Unconditioned Minimal Cooling Default')
      clg_stpt_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), clg_t_c)

      # Thermostat
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(thermal_zone.model)
      thermostat.setName("#{thermal_zone.name} Unconditioned Thermostat")
      thermostat.setHeatingSetpointTemperatureSchedule(htg_stpt_sch)
      thermostat.setCoolingSetpointTemperatureSchedule(clg_stpt_sch)
      thermal_zone.setThermostatSetpointDualSetpoint(thermostat)

      return true
    end
  end
end
