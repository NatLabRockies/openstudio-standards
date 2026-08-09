# frozen_string_literal: true

require 'openstudio'

module OpenStudioNECB
  # NECB 2025 8.4.4 (EUI path) archetype machinery: space->archetype mapping,
  # floor areas computed FROM the model (8.4.4.1.(3)), pro-rata distribution of
  # unmapped space functions (8.4.4.1.(4)), hard applicability guards
  # (8.4.4.1.(1) coverage, Table note HDD), the Table 8.4.4.2 CONFORMANCE CHECK,
  # and the Table 8.4.4.2 NORMALIZATION transform.
  #
  # Why check-then-normalize: the Table 8.4.4.1 EUI targets were derived
  # assuming the standardized Table 8.4.4.2 operating inputs, so comparing a
  # proposed simulated with arbitrary schedules/loads against them is
  # apples-to-oranges (and gameable). 8.4.4.2.(1) therefore REWRITES the
  # proposed's occupancy, receptacle, SWH loads and operating schedules to the
  # archetype defaults before the EUI-path run. When the model already matches
  # (the check), the as-specified run legitimately serves both compliance
  # paths and the second simulation is skipped.
  #
  # Scope (manifest: 8.4.4.2 partial), all audited:
  # - lighting POWER is the design being evaluated and is never touched.
  #   Lighting OPERATION schedules ARE normalized to the archetype letter
  #   (interpretation ADOPTED, project decision 2026-07-22): "operating
  #   schedules" is read broadly, the lettered sets include a lighting
  #   schedule, and controls credit is unaffected — NECB grants it through the
  #   4.3.2.10 POWER multipliers on installed LPD (8.4.3.4, modeller-side),
  #   which normalization never touches.
  # - outdoor air IS normalized (interpretation ADOPTED, same decision):
  #   8.4.3.6.(1)(a) "in accordance with Article 8.4.4.2" is read as the
  #   ventilation-standard rates applied AT the Table's occupant density —
  #   the only reading that gives (1)(a) meaning (ASHRAE 62.1-2016 Table
  #   6.2.2.1 rates per archetype, ARCHETYPE_OA_62_1).
  # - unmapped spaces keep their modeled loads: Table 8.4.4.2 applies "for the
  #   applicable building archetype", and unmapped space functions have none —
  #   only their AREA is distributed per 8.4.4.1.(4).
  #
  # "Archetype" here is the CODE's word: the Table 8.4.4.1 BUILDING ARCHETYPES
  # of the 8.4.4 EUI path (hence the file name eui_archetypes.rb). The project's
  # other sense — the 17 legacy NECB prototype buildings used as the validation
  # "fleet" — is a DIFFERENT thing entirely; see the glossary in docs/README.md.
  module Archetypes
    module_function

    VALUE_TOL = 0.01          # 1% on densities/powers/flows
    SCHEDULE_TOL = 0.005      # 0.5% absolute on hourly schedule values
    PEOPLE_PER_1000FT2_PER_M2_PER_PERSON = 92.90304 # 1000 ft2 in m2
    # ASHRAE 62.1-2016 Table 6.2.2.1 rates (retrieved via the codes server
    # ashrae_outdoor_air_rate 2026-07-22; the classroom row was served from its
    # fallback set but matches the published table). Applied at the Table
    # 8.4.4.2 occupant density per the adopted 8.4.3.6.(1)(a) reading.
    ARCHETYPE_OA_62_1 = {
      'School (K-12)' => { 'category' => 'classroom (age 9 plus)', 'rp_l_s_person' => 5.0, 'ra_l_s_m2' => 0.6 },
      'Multi-unit residential building' => { 'category' => 'dwelling unit', 'rp_l_s_person' => 2.5, 'ra_l_s_m2' => 0.3 },
      'Office' => { 'category' => 'office space', 'rp_l_s_person' => 2.5, 'ra_l_s_m2' => 0.3 }
    }.freeze

    # ---- mapping / areas ---------------------------------------------------

    # mapping: {archetype_name => :all | [space names]}. At most one archetype
    # may be :all (every counted space not claimed by an explicit list).
    # @param model [OpenStudio::Model::Model] the proposed model (areas computed from it)
    # @param mapping [Hash{String => Symbol, Array<String>}] archetype name =>
    #   :all (or 'all') or an explicit list of space names
    # @param audit [AuditLog]
    # @return [Hash] the resolved mapping —
    #   { archetypes: { archetype name => { spaces: [OpenStudio::Model::Space], area_m2: Float } },
    #     unmapped: { spaces: [OpenStudio::Model::Space], area_m2: Float },
    #     total_area_m2: Float }
    # @raise [ArgumentError] on unknown archetypes, unknown space names,
    #   double-mapped spaces, or more than one :all archetype
    def resolve!(model, mapping, audit:)
      table = Tiers.eui_data['archetype_eui_kwh_per_m2']
      unknown = mapping.keys.map(&:to_s) - table.keys
      raise(ArgumentError, "unknown 2025 EUI archetype(s) #{unknown.join('; ')} (#{table.keys.join('; ')})") unless unknown.empty?

      alls = mapping.select { |_, v| v == :all || v == 'all' }.keys
      raise(ArgumentError, "only one archetype may map :all (got #{alls.join(', ')})") if alls.size > 1

      counted = counted_spaces(model)
      by_name = counted.to_h { |s| [s.nameString, s] }
      claimed = {}
      resolved = {}
      mapping.each do |archetype, spec|
        next if spec == :all || spec == 'all'

        names = Array(spec).map(&:to_s)
        missing = names - by_name.keys
        unless missing.empty?
          raise(ArgumentError, "archetype '#{archetype}': space(s) not found or not counted toward floor area: " \
                               "#{missing.join('; ')} (counted spaces: #{by_name.keys.join('; ')})")
        end
        names.each do |n|
          raise(ArgumentError, "space '#{n}' mapped to both '#{claimed[n]}' and '#{archetype}'") if claimed.key?(n)

          claimed[n] = archetype.to_s
        end
        resolved[archetype.to_s] = names.map { |n| by_name[n] }
      end
      if alls.any?
        rest = counted.reject { |s| claimed.key?(s.nameString) }
        resolved[alls.first.to_s] = rest
        rest.each { |s| claimed[s.nameString] = alls.first.to_s }
      end

      unmapped = counted.reject { |s| claimed.key?(s.nameString) }
      out = { archetypes: resolved.transform_values { |spaces| { spaces: spaces, area_m2: area_of(spaces) } },
              unmapped: { spaces: unmapped, area_m2: area_of(unmapped) },
              total_area_m2: area_of(counted) }
      audit.decision(:eui, 'spaces mapped to Table 8.4.4.1 archetypes; areas computed from the model',
                     inputs: { areas_m2: out[:archetypes].transform_values { |v| v[:area_m2].round(1) },
                               unmapped_m2: out[:unmapped][:area_m2].round(1),
                               floor_area_basis: 'partofTotalFloorArea, non-plenum, x space multiplier (proxy for conditioned per 8.4.4.1.(3))' },
                     article: '8.4.4.1.(3)', ruling: 'D-04')
      out
    end

    # 8.4.4.1.(4): unmapped ("not associated") floor area distributed
    # proportionally among the listed archetypes so the BET areas sum to the
    # model's total. Over-assignment is impossible by construction (areas come
    # from disjoint space sets).
    # @param resolved [Hash] resolve! output
    # @param audit [AuditLog]
    # @return [Hash{String => Float}] archetype name => BET floor area in m2
    def bet_areas(resolved, audit:)
      base = resolved[:archetypes].transform_values { |v| v[:area_m2] }
      mapped = base.values.sum
      extra = resolved[:unmapped][:area_m2]
      if extra.positive? && mapped.positive?
        base = base.transform_values { |a| a + (extra * a / mapped) }
        audit.decision(:eui, 'unlisted space functions distributed proportionally among the listed archetypes',
                       inputs: { distributed_m2: extra.round(1) }, article: '8.4.4.1.(4)')
      end
      base
    end

    # Hard applicability guards. 8.4.4.1.(1) says the Subsection "shall only be
    # used" at >=90% coverage; the Table note bounds HDD < 9000. On the pure
    # :eui path these REFUSE (a verdict outside applicability is not a
    # determination); the supplement instead reports not-computed.
    # @param resolved [Hash] resolve! output
    # @param hdd [Numeric] heating degree-days below 18 degC
    # @param audit [AuditLog]
    # @return [void]
    # @raise [ArgumentError] when the 8.4.4 EUI path is not applicable
    def applicability!(resolved, hdd:, audit:)
      problems = applicability_problems(resolved, hdd: hdd, audit: audit)
      return if problems.empty?

      raise(ArgumentError, "the 8.4.4 EUI path is NOT applicable: #{problems.join('; ')}")
    end

    # Non-raising form of applicability!.
    # @param resolved [Hash] resolve! output
    # @param hdd [Numeric] heating degree-days below 18 degC
    # @param audit [AuditLog]
    # @return [Array<String>] human-readable problems (empty when applicable)
    def applicability_problems(resolved, hdd:, audit:)
      rules = Tiers.eui_data['applicability']
      problems = []
      mapped = resolved[:archetypes].values.sum { |v| v[:area_m2] }
      coverage = resolved[:total_area_m2].positive? ? mapped / resolved[:total_area_m2] : 0.0
      if coverage < rules['min_archetype_floor_fraction'] - 1e-6
        problems << format('only %.1f%% of floor area maps to listed archetypes (8.4.4.1.(1) requires >= %.0f%%)',
                           coverage * 100, rules['min_archetype_floor_fraction'] * 100)
        audit.warn(:eui, "archetype floor coverage BELOW the 8.4.4.1.(1) threshold (#{(coverage * 100).round(1)}%)",
                   article: '8.4.4.1.(1)', ruling: 'D-04')
      end
      if hdd && hdd >= rules['max_hdd']
        problems << "HDD #{hdd} >= #{rules['max_hdd']} (Table 8.4.4.1 note (1))"
        audit.warn(:eui, "HDD #{hdd} is outside the 8.4.4 applicability bound (< #{rules['max_hdd']})",
                   article: 'Table 8.4.4.1.', ruling: 'D-04')
      end
      problems
    end

    # ---- Table 8.4.4.2 defaults -------------------------------------------

    # The defaults table keys MURB once; both storey-height archetypes share it.
    def defaults_for(archetype)
      table = Tiers.eui_data['archetype_defaults_table_8_4_4_2']
      key = table.keys.find { |k| archetype.start_with?(k) } ||
            table.keys.find { |k| archetype.include?('residential') && k.include?('residential') }
      table.fetch(key) { raise(ArgumentError, "no Table 8.4.4.2 defaults for archetype '#{archetype}'") }
    end

    # A loads-catalog-shaped record carrying the Table 8.4.4.2 values, so the
    # loads gem's own application machinery (apply_people/apply_equipment/
    # apply_schedule_set/apply_thermostat) does the model work. Fractions are
    # the NECB standard set the catalog uses throughout.
    def synthetic_record(archetype)
      d = defaults_for(archetype)
      letter = d.fetch('schedule')
      oa = ARCHETYPE_OA_62_1.fetch(ARCHETYPE_OA_62_1.keys.find { |k| archetype.start_with?(k) } ||
                                    (archetype.include?('residential') ? 'Multi-unit residential building' : archetype))
      { 'necb_schedule_type' => letter,
        'lighting_schedule' => "NECB-#{letter}-Lighting",
        'oa_category_62_1' => oa['category'],
        'oa_l_s_per_person' => oa['rp_l_s_person'],
        'oa_l_s_per_m2' => oa['ra_l_s_m2'],
        'occupancy_per_area' => PEOPLE_PER_1000FT2_PER_M2_PER_PERSON / d.fetch('occupant_density_m2_per_person'),
        'occupancy_schedule' => "NECB-#{letter}-Occupancy",
        'occupancy_activity_schedule' => 'NECB-Activity',
        'electric_equipment_per_area' => d.fetch('receptacle_w_per_m2') / 10.7639104,
        'electric_equipment_fraction_latent' => 0.0,
        'electric_equipment_fraction_radiant' => 0.5,
        'electric_equipment_fraction_lost' => 0.0,
        'electric_equipment_schedule' => "NECB-#{letter}-Electric-Equipment",
        'heating_setpoint_schedule' => "NECB-#{letter}-Thermostat Setpoint-Heating",
        'cooling_setpoint_schedule' => "NECB-#{letter}-Thermostat Setpoint-Cooling",
        'service_water_heating_schedule' => "NECB-#{letter}-Service Water Heating",
        'swh_l_per_h_per_occupant' => d.fetch('swh_l_per_h_per_occupant'),
        'occupant_density_m2_per_person' => d.fetch('occupant_density_m2_per_person') }
    end

    # ---- conformance check -------------------------------------------------

    # Does the model ALREADY carry the Table 8.4.4.2 values, so one
    # as-specified annual run can lawfully serve both compliance paths?
    # Compares, per mapped space: occupant density, receptacle power, SWH peak
    # flow (values, VALUE_TOL) and the occupancy/equipment/setpoint schedule
    # PROFILES hourly over the year (SCHEDULE_TOL) against the archetype
    # letter's NECB schedules. Conservative: anything not comparable is a
    # mismatch (worst case is an unnecessary second run, never a wrong verdict).
    # @param model [OpenStudio::Model::Model] the proposed model
    # @param resolved [Hash] resolve! output
    # @param vintage [String] NECB vintage (schedule targets come from its data)
    # @param audit [AuditLog]
    # @return [Hash] { conformant: Boolean, mismatches: Array<String> }
    def conformance(model, resolved, vintage:, audit:)
      mismatches = []
      scratch = OpenStudio::Model::Model.new
      resolved[:archetypes].each do |archetype, info|
        record = synthetic_record(archetype)
        targets = target_schedules(scratch, record, vintage)
        info[:spaces].each do |space|
          check_space_values(space, archetype, record, mismatches)
          check_space_schedules(space, archetype, targets, mismatches)
        end
      end
      conformant = mismatches.empty?
      audit.decision(:eui,
                     conformant ? 'proposed already conforms to Table 8.4.4.2 — the as-specified annual run serves the EUI path' \
                                : "proposed does NOT conform to Table 8.4.4.2 (#{mismatches.size} mismatch(es))",
                     inputs: { mismatches: mismatches.first(20) }, article: '8.4.4.2.(1)')
      { conformant: conformant, mismatches: mismatches }
    end

    # ---- normalization -----------------------------------------------------

    # Rewrites the (already-cloned) model to Table 8.4.4.2 for every mapped
    # space: occupancy + receptacle loads and operating schedules via a cloned
    # space type per (original type x archetype), SWH flows per occupant, and
    # zone thermostats from the archetype letter. Lighting power, lighting
    # operation, OA and unmapped spaces are left as modeled (see module doc).
    # @param model [OpenStudio::Model::Model] an already-cloned model (rewritten in place)
    # @param resolved [Hash] resolve! output FOR THIS model (space objects must belong to it)
    # @param vintage [String] NECB vintage (schedule source)
    # @param audit [AuditLog]
    # @return [OpenStudio::Model::Model] the normalized model
    def normalize!(model, resolved, vintage:, audit:)
      apply = OpenStudioLoads::NECB::Apply
      clones = {}
      resolved[:archetypes].each do |archetype, info|
        record = synthetic_record(archetype)
        info[:spaces].each do |space|
          original = space.spaceType.empty? ? nil : space.spaceType.get
          key = [original&.nameString, archetype]
          clone = clones[key] ||= begin
            st = original ? original.clone(model).to_SpaceType.get : OpenStudio::Model::SpaceType.new(model)
            st.setName("#{original ? original.nameString : 'EUI'} [EUI #{archetype}]")
            st.people.each(&:remove)
            st.electricEquipment.each(&:remove)
            st.gasEquipment.each(&:remove)
            # a cloned space type still POINTS AT the original's schedule set —
            # wiring into it would mutate the original. Clone the original set
            # (not a bare fresh one): the archetype wiring overwrites the
            # occupancy/equipment entries, while LIGHTING and other schedules
            # keep inheriting as modeled — severing them fatals EnergyPlus on
            # schedule-less Lights and would silently change scope.
            fresh = if original && original.defaultScheduleSet.is_initialized
                      original.defaultScheduleSet.get.clone(model).to_DefaultScheduleSet.get
                    else
                      OpenStudio::Model::DefaultScheduleSet.new(model)
                    end
            fresh.setName("#{st.nameString} Schedule Set")
            st.setDefaultScheduleSet(fresh)
            apply.apply_people(st, record, audit)
            apply.apply_equipment(st, record, audit)
            apply.apply_schedule_set(model, st, record, vintage, audit)
            apply.apply_thermostat(model, st, record, vintage, audit)
            # lighting OPERATION follows the letter (adopted interpretation;
            # POWER untouched — the loads gem's wiring deliberately excludes
            # lighting, so it is wired here) and per-instance overrides on the
            # clone's Lights are cleared so the set governs.
            fresh.setLightingSchedule(OpenStudioLoads::Schedules.add(model, record['lighting_schedule'],
                                                                     vintage: vintage, audit: audit))
            st.lights.each(&:resetSchedule)
            st
          end
          space.setSpaceType(clone)
          space.lights.each(&:resetSchedule) # space-level instances inherit the set too
          space.setDesignSpecificationOutdoorAir(archetype_dsoa(model, archetype, record))
          normalize_swh!(model, space, record, vintage, audit)
        end
        audit.decision(:eui, "spaces normalized to Table 8.4.4.2 (#{archetype})",
                       inputs: { spaces: info[:spaces].size,
                                 occupant_density_m2_per_person: record['occupant_density_m2_per_person'],
                                 receptacle_w_per_m2: (record['electric_equipment_per_area'] * 10.7639104).round(2),
                                 schedule_letter: record['necb_schedule_type'] },
                       article: '8.4.4.2.(1)', ruling: 'D-05')
      end
      force_zone_thermostats!(model, resolved, audit)
      audit.info(:eui, 'lighting POWER (the design under evaluation) and unmapped spaces are left as modeled; ' \
                       'lighting OPERATION follows the archetype letter and outdoor air is set to the ASHRAE ' \
                       '62.1 rates at the Table 8.4.4.2 occupant density (adopted interpretations, 2026-07-22)',
                 article: '8.4.4.2.(1); 8.4.3.6.(1)(a)', ruling: 'D-05')
      model
    end

    # -- internals -----------------------------------------------------------

    def counted_spaces(model)
      model.getSpaces.sort_by(&:nameString).select do |s|
        next false unless s.partofTotalFloorArea

        type = s.spaceType.empty? ? '' : s.spaceType.get.nameString
        !type.downcase.include?('plenum') && !s.nameString.downcase.include?('plenum')
      end
    end

    def area_of(spaces)
      spaces.sum { |s| s.floorArea * s.multiplier }
    end

    def check_space_values(space, archetype, record, mismatches)
      area = space.floorArea
      return if area.zero?

      expect_people = 1.0 / record['occupant_density_m2_per_person']
      got_people = space.numberOfPeople / area
      unless within?(got_people, expect_people, VALUE_TOL)
        mismatches << "#{space.nameString} (#{archetype}): occupant density #{fmt(got_people)} people/m2, " \
                      "Table 8.4.4.2 requires #{fmt(expect_people)}"
      end

      expect_w = record['electric_equipment_per_area'] * 10.7639104
      got_w = space.electricEquipmentPowerPerFloorArea
      unless within?(got_w, expect_w, VALUE_TOL)
        mismatches << "#{space.nameString} (#{archetype}): receptacle #{fmt(got_w)} W/m2, requires #{fmt(expect_w)}"
      end

      expect_flow = swh_target_m3s(space, record)
      got_flow = space_swh_flow_m3s(space)
      unless within?(got_flow, expect_flow, VALUE_TOL)
        mismatches << "#{space.nameString} (#{archetype}): SWH peak flow #{fmt(got_flow, 9)} m3/s, requires #{fmt(expect_flow, 9)}"
      end

      check_outdoor_air(space, archetype, record, mismatches)
    end

    # Adopted 8.4.3.6.(1)(a) reading: DSOA must carry the 62.1 rates (Sum
    # method) at the Table density. Absent or differing DSOA is a mismatch.
    def check_outdoor_air(space, archetype, record, mismatches)
      dsoa = space.designSpecificationOutdoorAir
      if dsoa.empty?
        mismatches << "#{space.nameString} (#{archetype}): no DesignSpecificationOutdoorAir (62.1 rates at Table density required)"
        return
      end
      d = dsoa.get
      expect_pp = record['oa_l_s_per_person'] / 1000.0
      expect_pa = record['oa_l_s_per_m2'] / 1000.0
      unless d.outdoorAirMethod.casecmp('sum').zero? &&
             within?(d.outdoorAirFlowperPerson, expect_pp, VALUE_TOL) &&
             within?(d.outdoorAirFlowperFloorArea, expect_pa, VALUE_TOL)
        mismatches << "#{space.nameString} (#{archetype}): OA #{d.outdoorAirMethod} " \
                      "#{fmt(d.outdoorAirFlowperPerson, 6)}/person + #{fmt(d.outdoorAirFlowperFloorArea, 6)}/m2, " \
                      "requires Sum #{fmt(expect_pp, 6)} + #{fmt(expect_pa, 6)} (62.1 #{record['oa_category_62_1']})"
      end
    end

    def check_space_schedules(space, archetype, targets, mismatches)
      space_type = space.spaceType.empty? ? nil : space.spaceType.get
      { 'occupancy' => [space_type ? space_type.people : [], :numberofPeopleSchedule],
        'electric equipment' => [space_type ? space_type.electricEquipment : [], :schedule],
        'lighting' => [(space_type ? space_type.lights.to_a : []) + space.lights.to_a, :schedule] }
        .each do |label, (instances, getter)|
        target = targets[label]
        next if target.nil?

        instances.each do |inst|
          sched = inst.public_send(getter)
          # not set on the instance -> inherited via the default schedule set
          sched = inherited_schedule(inst, label) if sched.empty?
          verdict = schedules_equivalent?(sched, target)
          next if verdict == true

          mismatches << "#{space.nameString} (#{archetype}): #{label} schedule #{verdict}"
        end
      end
      check_zone_setpoints(space, archetype, targets, mismatches)
    end

    def check_zone_setpoints(space, archetype, targets, mismatches)
      zone = space.thermalZone
      return if zone.empty?

      thermostat = zone.get.thermostatSetpointDualSetpoint
      if thermostat.empty?
        mismatches << "#{space.nameString} (#{archetype}): zone has no thermostat (letter setpoint schedules required)"
        return
      end
      { 'heating setpoint' => thermostat.get.heatingSetpointTemperatureSchedule,
        'cooling setpoint' => thermostat.get.coolingSetpointTemperatureSchedule }.each do |label, sched|
        target = targets[label]
        next if target.nil?

        verdict = sched.empty? ? 'absent' : schedules_equivalent?(sched, target)
        next if verdict == true

        mismatches << "#{space.nameString} (#{archetype}): #{label} schedule #{verdict}"
      end
    end

    def inherited_schedule(instance, label)
      space_type = instance.spaceType
      return OpenStudio::OptionalSchedule.new if space_type.empty?

      set = space_type.get.defaultScheduleSet
      return OpenStudio::OptionalSchedule.new if set.empty?

      case label
      when 'occupancy' then set.get.numberofPeopleSchedule
      when 'electric equipment' then set.get.electricEquipmentSchedule
      when 'lighting' then set.get.lightingSchedule
      else OpenStudio::OptionalSchedule.new
      end
    end

    def target_schedules(scratch, record, vintage)
      quiet = OpenStudioNECB::AuditLog.new
      { 'occupancy' => OpenStudioLoads::Schedules.add(scratch, record['occupancy_schedule'], vintage: vintage, audit: quiet),
        'lighting' => OpenStudioLoads::Schedules.add(scratch, record['lighting_schedule'], vintage: vintage, audit: quiet),
        'electric equipment' => OpenStudioLoads::Schedules.add(scratch, record['electric_equipment_schedule'], vintage: vintage, audit: quiet),
        'heating setpoint' => OpenStudioLoads::Schedules.add(scratch, record['heating_setpoint_schedule'], vintage: vintage, audit: quiet),
        'cooling setpoint' => OpenStudioLoads::Schedules.add(scratch, record['cooling_setpoint_schedule'], vintage: vintage, audit: quiet),
        'SWH' => OpenStudioLoads::Schedules.add(scratch, record['service_water_heating_schedule'], vintage: vintage, audit: quiet) }
    end

    # Hourly profile comparison across the full year. true, or a short reason
    # string. Only ScheduleRulesets are comparable — anything else is a
    # (conservative) mismatch.
    def schedules_equivalent?(schedule, target)
      schedule = schedule.get if schedule.respond_to?(:get) && schedule.respond_to?(:is_initialized) && schedule.is_initialized
      return 'absent' if schedule.respond_to?(:is_initialized) && !schedule.is_initialized

      ruleset = schedule.to_ScheduleRuleset
      return "type #{schedule.iddObjectType.valueName} not comparable (only ScheduleRuleset)" if ruleset.empty?

      # Clone into the TARGET's model before expanding to days: the two models
      # can assume different calendar years (the fixture carries a
      # YearDescription), and a year mismatch shifts day-of-week rules so a
      # weekday profile gets compared against a weekend one.
      candidate = ruleset.get.clone(target.model).to_ScheduleRuleset.get
      a_days = year_days(candidate)
      b_days = year_days(target)
      a_days.zip(b_days).each_with_index do |(a, b), i|
        (1..24).each do |h|
          t = OpenStudio::Time.new(0, h, 0, 0)
          return format('differs on day %d hour %d (%.3f vs %.3f)', i + 1, h, a.getValue(t), b.getValue(t)) \
            if (a.getValue(t) - b.getValue(t)).abs > SCHEDULE_TOL
        end
      end
      true
    end

    def year_days(ruleset)
      y = ruleset.model.getYearDescription.assumedYear
      ruleset.getDaySchedules(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(1), 1, y),
                              OpenStudio::Date.new(OpenStudio::MonthOfYear.new(12), 31, y))
    end

    # One shared DSOA per archetype: 62.1 rates at the Table density (the
    # per-person term therefore rides the NORMALIZED occupancy).
    def archetype_dsoa(model, archetype, record)
      name = "EUI OA #{archetype} (62.1 #{record['oa_category_62_1']})"
      existing = model.getDesignSpecificationOutdoorAirs.find { |d| d.nameString == name }
      return existing if existing

      dsoa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
      dsoa.setName(name)
      dsoa.setOutdoorAirMethod('Sum')
      dsoa.setOutdoorAirFlowperPerson(record['oa_l_s_per_person'] / 1000.0)
      dsoa.setOutdoorAirFlowperFloorArea(record['oa_l_s_per_m2'] / 1000.0)
      dsoa
    end

    def swh_target_m3s(space, record)
      occupants = (space.floorArea / record['occupant_density_m2_per_person'])
      occupants * record['swh_l_per_h_per_occupant'] / 3_600_000.0 # L/h -> m3/s
    end

    def space_swh_flow_m3s(space)
      space.waterUseEquipment.sum { |e| e.waterUseEquipmentDefinition.peakFlowRate }
    end

    def normalize_swh!(model, space, record, vintage, audit)
      target = swh_target_m3s(space, record)
      equipment = space.waterUseEquipment
      if equipment.empty?
        return if target.zero?

        audit.warn(:eui, "space '#{space.nameString}' has NO water-use equipment — Table 8.4.4.2 SWH load " \
                         "(#{record['swh_l_per_h_per_occupant']} L/h/occupant) cannot be applied; the EUI " \
                         'targets assume it, so the proposed under-reports SWH energy',
                   article: '8.4.4.2.(1)')
        return
      end
      share = target / equipment.size
      quiet_sched = OpenStudioLoads::Schedules.add(model, record['service_water_heating_schedule'],
                                                   vintage: vintage, audit: audit)
      equipment.each do |e|
        # definitions may be shared across spaces — give this instance its own
        definition = e.waterUseEquipmentDefinition.clone(model).to_WaterUseEquipmentDefinition.get
        definition.setName("#{e.nameString} [EUI] Definition")
        definition.setPeakFlowRate(share)
        e.setWaterUseEquipmentDefinition(definition)
        e.setFlowRateFractionSchedule(quiet_sched)
      end
    end

    def force_zone_thermostats!(model, resolved, audit)
      space_to_arch = {}
      resolved[:archetypes].each { |a, info| info[:spaces].each { |s| space_to_arch[s.nameString] = a } }
      model.getThermalZones.sort_by(&:nameString).each do |zone|
        archs = zone.spaces.map { |s| space_to_arch[s.nameString] }.uniq
        next if archs.empty? || archs == [nil]

        if archs.size > 1 || archs.include?(nil)
          audit.warn(:eui, "zone '#{zone.nameString}' mixes archetypes/unmapped spaces (#{archs.compact.join(', ')}) " \
                           '— thermostat left as modeled',
                   article: '8.4.4.2.(1)')
          next
        end
        space = zone.spaces.find { |s| !s.spaceType.empty? }
        next if space.nil?

        name = "#{space.spaceType.get.nameString} Thermostat"
        thermostat = model.getThermostatSetpointDualSetpoints.find { |t| t.nameString == name }
        zone.setThermostatSetpointDualSetpoint(thermostat) if thermostat
      end
    end

    def within?(got, expect, tol)
      return got.abs < 1e-12 if expect.abs < 1e-12

      (got - expect).abs / expect.abs <= tol
    end

    def fmt(value, precision = 4) = format("%.#{precision}f", value)

    # ---- internals (not API) ----
    private_class_method :defaults_for, :synthetic_record, :counted_spaces, :area_of,
                         :check_space_values, :check_outdoor_air,
                         :check_space_schedules, :check_zone_setpoints,
                         :inherited_schedule, :target_schedules,
                         :schedules_equivalent?, :year_days, :archetype_dsoa,
                         :swh_target_m3s, :space_swh_flow_m3s, :normalize_swh!,
                         :force_zone_thermostats!, :within?, :fmt
  end
end
