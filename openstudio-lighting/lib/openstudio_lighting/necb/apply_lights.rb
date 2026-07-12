module OpenStudioLighting
  module NECB
    # Interior lighting — port of legacy apply_standard_lights (NECB2011 base) with
    # the NECB2020-lineage overrides: set_lighting_per_area WITHOUT the 2011 0.9
    # occupancy-sensor derate (2015+ models sensing via the lighting SCHEDULE), the
    # NECB2015 apply_lighting_schedule sensor-synthesis, and the NECB2017 LED
    # atrium equations.
    #
    # LEGACY DEFECTS fixed here (both in the never-exercised atrium/LED path —
    # no archetype has an atrium): set_lighting_per_area_led_lighting references
    # an undefined `space_height` (NameError), and
    # get_max_space_height_for_space_type calls `select(&:surfaceType == 'Wall')`
    # which is `select(&false)` (TypeError). The gem computes the height correctly
    # and uses it.
    module ApplyLights
      module_function

      # Apply NECB interior lighting to every tagged space type.
      # @param lights_type ['NECB_Default', 'LED']
      def apply_lights(model, vintage: '2020', lights_type: 'NECB_Default', lights_scale: 1.0, audit: nil)
        audit ||= AuditLog.new
        lights_type = 'NECB_Default' if lights_type.nil? || lights_type == 'none'
        lights_scale = 1.0 if lights_scale.nil? || lights_scale == 'none' || lights_scale == 'NECB_Default'
        lights_scale = lights_scale.to_s.strip.to_f if lights_scale.is_a?(String)
        applied = 0

        model.getSpaceTypes.sort_by(&:nameString).each do |space_type|
          applied += 1 if apply_to_space_type(model, space_type, vintage, lights_type, lights_scale, audit)
        end
        audit.decision(:lighting, "interior lighting applied (#{lights_type}, scale #{lights_scale})",
                       inputs: { space_types_applied: applied, vintage: vintage },
                       article: '4.2.1.4.; 4.2.1.5.; 4.2.1.6.')
        emit_article_coverage(vintage, audit)
        audit
      end

      def apply_to_space_type(model, space_type, vintage, lights_type, lights_scale, audit)
        name = space_type.nameString
        return false if name.downcase.include?('plenum') ||
                        (space_type.standardsSpaceType.is_initialized && space_type.standardsSpaceType.get.downcase.include?('plenum'))

        building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil
        standards_type = space_type.standardsSpaceType.is_initialized ? space_type.standardsSpaceType.get : nil
        record = OpenStudioLoads::NECB::SpaceTypes.find(building_type: building_type,
                                                        space_type: standards_type,
                                                        vintage: OpenStudioLoads::NECB.data_vintage(vintage))
        return false if record.nil? || OpenStudioLoads::NECB::SpaceTypes.undefined?(record)

        lpd = record['lighting_per_area'].to_f
        per_person = record['lighting_per_person'].to_f
        return false if lpd.zero? && per_person.zero?

        instance = single_lights_instance(space_type, lights_type)
        definition = instance.lightsDefinition
        applied_lpd_w_ft2 = nil

        unless lpd.zero?
          if lights_type == 'LED'
            led = NECB.led_record(building_type: building_type, space_type: standards_type)
            raise(ArgumentError, "no LED lighting data for ['#{building_type}', '#{standards_type}']") if led.nil?

            applied_lpd_w_ft2 = led_lpd_w_ft2(space_type, standards_type, led, vintage, audit) * lights_scale
            definition.setWattsperSpaceFloorArea(OpenStudio.convert(applied_lpd_w_ft2, 'W/ft^2', 'W/m^2').get)
            set_fraction(definition, :setReturnAirFraction, led['lighting_fraction_to_return_air'])
            set_fraction(definition, :setFractionRadiant, led['lighting_fraction_radiant'])
            set_fraction(definition, :setFractionVisible, led['lighting_fraction_visible'])
          else
            applied_lpd_w_ft2 = lpd * lights_scale
            definition.setWattsperSpaceFloorArea(OpenStudio.convert(applied_lpd_w_ft2, 'W/ft^2', 'W/m^2').get)
            set_fraction(definition, :setReturnAirFraction, record['lighting_fraction_to_return_air'])
            set_fraction(definition, :setFractionRadiant, record['lighting_fraction_radiant'])
            set_fraction(definition, :setFractionVisible, record['lighting_fraction_visible'])
          end
        end
        definition.setWattsperPerson(per_person) unless per_person.zero?

        add_additional_lights(space_type, record)
        wire_lighting_schedule(model, space_type, record, vintage, audit)

        audit.info(:lighting, 'lights set', target: name,
                   inputs: { lpd_w_per_ft2: applied_lpd_w_ft2&.round(4), type: lights_type },
                   article: building_type == 'Space Function' ? '4.2.1.6.' : '4.2.1.5.')
        true
      end

      # LED LPD with the atrium height rule (W/ft2 in, W/ft2 out; equations are SI
      # W/m2 = intercept + slope x height, converted x0.092903 as legacy does).
      def led_lpd_w_ft2(space_type, standards_type, led, vintage, audit)
        lpd = led['lighting_per_area'].to_f
        return lpd unless standards_type.to_s.include?('Atrium')

        height = max_space_height(space_type)
        equations = NECB.rules(vintage)['atrium_led']
        equation = height < 12.0 ? equations['below_12m'] : equations['at_or_above_12m']
        atrium_lpd = (equation['intercept'] + equation['slope'] * height) * 0.092903
        audit.info(:lighting, 'LED atrium LPD from height equation (legacy defect fixed: undefined space_height)',
                   target: space_type.nameString,
                   inputs: { height_m: height.round(2), intercept: equation['intercept'], slope: equation['slope'] },
                   value: "#{atrium_lpd.round(4)} W/ft2", article: '4.2.1.6. (atrium)')
        atrium_lpd
      end

      # Max wall-vertex height over the space type's spaces (correct version of the
      # legacy method whose select(&:surfaceType == 'Wall') is select(&false)).
      def max_space_height(space_type)
        height = 0.0
        space_type.spaces.sort_by(&:nameString).each do |space|
          space.surfaces.select { |s| s.surfaceType == 'Wall' }.each do |wall|
            top = wall.vertices.map(&:z).max
            height = top if top && top > height
          end
        end
        height
      end

      def add_additional_lights(space_type, record)
        additional = record['additional_lighting_per_area'].to_f
        return if additional.zero?
        return if space_type.lights.any? { |l| l.nameString.include?('Additional') }

        definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
        definition.setName("#{space_type.nameString} Additional Lights Definition")
        definition.setWattsperSpaceFloorArea(OpenStudio.convert(additional, 'W/ft^2', 'W/m^2').get)
        set_fraction(definition, :setReturnAirFraction, record['lighting_fraction_to_return_air'])
        set_fraction(definition, :setFractionRadiant, record['lighting_fraction_radiant'])
        set_fraction(definition, :setFractionVisible, record['lighting_fraction_visible'])
        lights = OpenStudio::Model::Lights.new(definition)
        lights.setName("#{space_type.nameString} Additional Lights")
        lights.setSpaceType(space_type)
      end

      # NECB2015-lineage apply_lighting_schedule: plain schedule at/below the 8.6
      # W/m2 threshold; above it, synthesize the occupancy-sensor ruleset —
      # hour-by-hour, when occupancy < rel_absence_occ the lighting value is
      # multiplied by (1 - rel_absence_occ x occ_sense - personal_control).
      def wire_lighting_schedule(model, space_type, record, vintage, audit)
        schedule_set = space_type.defaultScheduleSet.is_initialized ? space_type.defaultScheduleSet.get : nil
        if schedule_set.nil?
          schedule_set = OpenStudio::Model::DefaultScheduleSet.new(model)
          schedule_set.setName("#{space_type.nameString} Schedule Set")
          space_type.setDefaultScheduleSet(schedule_set)
        end

        data_vintage = OpenStudioLoads::NECB.data_vintage(vintage)
        lpd = record['lighting_per_area'].to_f
        threshold = NECB.rules(vintage)['sensor_schedule_lpd_threshold_w_per_ft2'].to_f
        lighting_name = record['lighting_schedule']
        return if lighting_name.nil?

        if lpd <= threshold
          schedule_set.setLightingSchedule(OpenStudioLoads::Schedules.add(model, lighting_name, vintage: data_vintage, audit: audit))
          return
        end

        occupancy_name = record['occupancy_schedule'].to_s
        rel_absence = record['rel_absence_occ'].to_f
        personal = record['personal_control'].to_f
        occ_sense = record['occ_sense'].to_f
        schedules = OpenStudioLoads::NECB.table(data_vintage, 'schedules')
        occupancy_rows = schedules.select { |r| r['name'] == occupancy_name }
        lighting_rows = schedules.select { |r| r['name'] == lighting_name }
        if occupancy_rows.empty? || lighting_rows.empty?
          audit.warn(:lighting, "sensor-schedule synthesis needs both '#{occupancy_name}' and '#{lighting_name}' — " \
                                'falling back to the plain lighting schedule', target: space_type.nameString)
          schedule_set.setLightingSchedule(OpenStudioLoads::Schedules.add(model, lighting_name, vintage: data_vintage, audit: audit))
          return
        end

        ruleset_name = "#{occupancy_name}-#{lighting_name}-#{rel_absence}-#{personal}-#{occ_sense}-Light Ruleset"
        existing = model.getSchedules.sort_by(&:nameString).find { |s| s.nameString == ruleset_name }
        if existing
          schedule_set.setLightingSchedule(existing)
          return
        end

        ruleset = synthesize_sensor_ruleset(model, ruleset_name, occupancy_rows, lighting_rows,
                                            rel_absence, personal, occ_sense)
        schedule_set.setLightingSchedule(ruleset)
        audit.info(:lighting, 'occupancy-sensor lighting schedule synthesized (LPD > 8.6 W/m2)',
                   target: space_type.nameString,
                   inputs: { rel_absence_occ: rel_absence, personal_control: personal, occ_sense: occ_sense,
                             occ_control_factor: (1 - (rel_absence * occ_sense) - personal).round(4) },
                   article: '4.2.2.2.; 4.3.2.10. (8.4.4.5.(3) via schedule modulation)')
      end

      def synthesize_sensor_ruleset(model, name, occupancy_rows, lighting_rows, rel_absence, personal, occ_sense)
        require 'date'
        ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
        ruleset.setName(name)
        occ_control = 1 - (rel_absence * occ_sense) - personal

        occupancy_rows.each do |occupancy_row|
          day_types = occupancy_row['day_types'].to_s
          lighting_row = lighting_rows.find { |r| r['day_types'] == occupancy_row['day_types'] }
          next if lighting_row.nil?

          values = occupancy_row['values'].each_with_index.map do |occ_value, hour|
            light_value = lighting_row['values'][hour].to_f
            occ_value.to_f < rel_absence ? light_value * occ_control : light_value
          end

          if day_types.include?('Default')
            day = ruleset.defaultDaySchedule
            day.setName("#{name.sub(' Ruleset', '')} Default")
            add_values(day, values)
          end
          if OpenStudioLoads::Schedules::DAY_TOKENS.any? { |t| day_types.include?(t) }
            rule = OpenStudio::Model::ScheduleRule.new(ruleset)
            day = rule.daySchedule
            day.setName("#{name.sub(' Ruleset', '')}-#{day_types}-Light Day")
            add_values(day, values)
            start_date = Date.parse(occupancy_row['start_date'])
            end_date = Date.parse(occupancy_row['end_date'])
            rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(start_date.month), start_date.day))
            rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(end_date.month), end_date.day))
            if day_types.include?('Wknd')
              rule.setApplySaturday(true)
              rule.setApplySunday(true)
            end
            %w[Monday Tuesday Wednesday Thursday Friday].each { |d| rule.send("setApply#{d}", true) } if day_types.include?('Wkdy')
            { 'Mon' => 'Monday', 'Tue' => 'Tuesday', 'Wed' => 'Wednesday', 'Thu' => 'Thursday',
              'Fri' => 'Friday', 'Sat' => 'Saturday', 'Sun' => 'Sunday' }.each do |token, method|
              rule.send("setApply#{method}", true) if day_types.include?(token)
            end
          end
          if day_types.include?('WntrDsn')
            day = OpenStudio::Model::ScheduleDay.new(model)
            ruleset.setWinterDesignDaySchedule(day)
            add_values(ruleset.winterDesignDaySchedule, values)
          end
          if day_types.include?('SmrDsn')
            day = OpenStudio::Model::ScheduleDay.new(model)
            ruleset.setSummerDesignDaySchedule(day)
            add_values(ruleset.summerDesignDaySchedule, values)
          end
        end
        ruleset
      end

      def add_values(day_schedule, values)
        24.times do |i|
          next if values[i] == values[i + 1]

          day_schedule.addValue(OpenStudio::Time.new(0, i + 1, 0, 0), values[i].to_f)
        end
      end

      def single_lights_instance(space_type, lights_type)
        instances = space_type.lights.sort.reject { |l| l.nameString.include?('Additional') }
        if instances.empty?
          definition = OpenStudio::Model::LightsDefinition.new(space_type.model)
          suffix = lights_type == 'LED' ? ' - LED lighting' : ''
          definition.setName("#{space_type.nameString} Lights Definition#{suffix}")
          lights = OpenStudio::Model::Lights.new(definition)
          lights.setName("#{space_type.nameString} Lights")
          lights.setSpaceType(space_type)
          lights
        else
          instances.drop(1).each(&:remove)
          instances.first
        end
      end

      def set_fraction(definition, setter, value)
        v = value.to_f
        definition.send(setter, v) unless v.zero?
      end

      def emit_article_coverage(vintage, audit)
        coverage = NECB.rules(vintage)['article_coverage']
        return if coverage.nil?

        cited = Hash.new(0)
        audit.entries.each { |e| e[:article].to_s.scan(/\d+\.\d+(?:\.\d+)*\./) { |a| cited[a] += 1 } }
        coverage['articles'].each do |article|
          applied = cited.select { |a, _| a.start_with?(article['article'].to_s.sub(/\.\z/, '').sub(/\(\d+\).*/, '')) }.values.sum
          inputs = { status: article['status'], decisions_citing: applied }
          if %w[implemented satisfied_by_clone host_scope].include?(article['status'])
            audit.info(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}#{article['how'] ? ": #{article['how']}" : ''}",
                       inputs: inputs, article: article['article'])
          else
            audit.warn(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}" \
                                  "#{article['how'] ? ". Applied: #{article['how']}" : ''}" \
                                  "#{article['gaps'] ? ". Gaps: #{article['gaps']}" : ''}",
                       inputs: inputs, article: article['article'])
          end
        end
      end
    end

    def self.apply_lights(model, **kwargs)
      ApplyLights.apply_lights(model, **kwargs)
    end
  end
end
