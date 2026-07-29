require 'json'

module OpenStudioHVAC
  # NECB performance-path helpers: reference HVAC selection (Table 8.4.4.7.-A/-B) and,
  # in later phases, the proposed->reference transform and vintage efficiency application.
  # All rule content lives in data/necb/reference_rules_<vintage>.json (vendored, with
  # article-level provenance); this code is a rules interpreter, not a rules store.
  module NECB
    RULES_DIR = File.expand_path('../data/necb', __dir__)

    def self.rules(vintage)
      @rules ||= {}
      @rules[vintage.to_s] ||= begin
        path = File.join(RULES_DIR, "reference_rules_#{vintage}.json")
        raise(ArgumentError, "no NECB reference rules for vintage '#{vintage}' (expected #{path})") unless File.exist?(path)

        JSON.parse(File.read(path))
      end
    end

    # One reference-system assignment for a group of zones.
    Assignment = Struct.new(:zones, :category, :reference_system, :catalog_name, :config,
                            :energy_type, :action, :articles, keyword_init: true)

    # Select the NECB reference HVAC system for every zone group of a characterized model.
    # Pure logic: no model access — everything comes from the facts hash (see
    # OpenStudioHVAC.characterize) and the building info.
    #
    # @param facts [Hash] OpenStudioHVAC.characterize output
    # @param building [Hash] :storeys (above-ground count), :zone_types
    #   ({zone name => space-type description string}), optional :kitchen_hood_zones,
    #   :refrigerated_zones (Arrays of zone names for conditions the model cannot express)
    # @param vintage [String] e.g. '2020'
    # @param audit [AuditLog, nil]
    # @return [Array<Assignment>]
    def self.select_reference_systems(facts:, building:, vintage: '2020', audit: nil)
      ruleset = rules(vintage)
      selection = ruleset.fetch('selection')
      definitions = ruleset.fetch('system_definitions')

      facts.fetch(:zone_groups).map do |group|
        next unless group[:heated] || group[:cooled] # unconditioned: no reference system

        category = category_for(group, building, selection, audit)
        assignment = assign(group, category, building, selection, audit)
        finalize(assignment, group, definitions, selection, facts, audit)
      end.compact
    end

    # ---- category election: majority space-type keyword match over the group's zones ----

    def self.category_for(group, building, selection, audit)
      votes = Hash.new(0)
      group[:zones].each do |zone_name|
        type = (building[:zone_types] || {})[zone_name].to_s.downcase
        row = selection['categories'].find do |cat|
          cat['keywords'].any? { |kw| type.include?(kw.downcase) }
        end
        votes[row ? row['category'] : nil] += 1
      end
      category, = votes.max_by { |cat, count| [count, cat.nil? ? 0 : 1] }
      if votes.keys.compact.size > 1
        audit&.warn(:selection, '8.4.4.7.(1) assigns systems PER THERMAL BLOCK, but this zone group mixes '                                 "categories #{votes.keys.compact.join(' / ')} — majority (#{category}) applied "                                 'to the whole group', target: group[:air_loop] || group[:zones].first,
                    article: '8.4.4.7.(1)', ruling: 'D-22')
      end
      if category.nil?
        category = selection['default_category']
        audit&.warn(:selection, 'space type not listed in Table 8.4.4.7.-A — closest-corresponding category assumed',
                    target: group[:air_loop] || group[:zones].first,
                    inputs: { zone_types: group[:zones].map { |z| (building[:zone_types] || {})[z] }.compact.uniq },
                    value: category, article: '8.4.4.7.(3)')
      end
      category
    end

    # ---- rule application per category ----

    def self.assign(group, category, building, selection, audit)
      cat = selection['categories'].find { |c| c['category'] == category }
      articles = [selection['article']]
      storeys = building[:storeys].to_i

      cat['rules'].each do |rule|
        return residential_assignment(group, category, selection, articles, audit) if rule['special'] == 'residential'
        next if rule['max_storeys'] && storeys > rule['max_storeys']
        next if rule['min_storeys'] && storeys < rule['min_storeys']
        next unless condition_met?(rule, group, building, audit)

        if rule['min_cooling_kw_exclusive']
          kw = group[:design_cooling_kw]
          if kw.nil?
            audit&.warn(:selection, 'cooling-capacity threshold rule needs a sized model — smaller-system branch assumed',
                        target: group[:air_loop] || group[:zones].first, article: rule['article'])
            next
          end
          next unless kw > rule['min_cooling_kw_exclusive']
        end

        articles << rule['article'] if rule['article']
        return Assignment.new(zones: group[:zones], category: category,
                              reference_system: rule['reference_system'],
                              action: :build, articles: articles.compact)
      end

      # no rule matched (e.g. storey band gap) — fall back to the last, most general rule
      fallback = cat['rules'].reject { |r| r['special'] }.last
      Assignment.new(zones: group[:zones], category: category,
                     reference_system: fallback['reference_system'],
                     action: :build, articles: articles.compact)
    end

    def self.condition_met?(rule, group, building, _audit)
      case rule['condition']
      when 'kitchen_hood' then (building[:kitchen_hood_zones] || []).intersect?(group[:zones])
      when 'refrigerated' then (building[:refrigerated_zones] || []).intersect?(group[:zones])
      else true
      end
    end

    def self.residential_assignment(group, category, selection, articles, audit)
      res = selection['special_rules']['residential']
      articles = articles + [res['article']]
      # D-34 (A1, phylroy 2026-07-27): follow legacy — a residential block whose
      # proposed system includes a heat pump takes the 8.4.4.7.(4) ASHP redirect,
      # NOT the Table -A "(or heat pumps)" identical-to-proposed parenthetical.
      # (Legacy's necb_reference_hp flag builds the reference-hp variant for every
      # family, residential included; it has no copy branch at all — L-11.) The
      # System-1 assignment below is flipped to 'hp' by finalize's override.
      # D-37 narrows this to REDIRECTING heat pumps: a residential water-loop HP
      # stays on the Table -A residential rules (8.4.4.13.(1)) — its 'wshp'
      # family lands in the compatible-cooling copy branch.
      if heat_pump_redirects?(group)
        audit&.decision(:selection, 'residential with heat pump -> ASHP reference redirect (A1/D-34: follow legacy)',
                        target: group[:zones].join(','), article: '8.4.4.7.(4)', ruling: 'D-34')
        return Assignment.new(zones: group[:zones], category: category, reference_system: 1,
                              action: :build, articles: articles + ['8.4.4.7.(4)'])
      end
      if group[:heated] && !group[:cooled]
        audit&.decision(:selection, 'residential heated-only -> System 1',
                        target: group[:zones].join(','), article: res['article'])
        Assignment.new(zones: group[:zones], category: category, reference_system: 1,
                       action: :build, articles: articles)
      elsif group[:cooled] && residential_compatible_cooling?(group)
        audit&.decision(:selection, 'residential with compatible cooling -> reference identical to proposed',
                        target: group[:zones].join(','), article: res['article'])
        Assignment.new(zones: group[:zones], category: category, reference_system: nil,
                       action: :copy_proposed, articles: articles)
      else
        audit&.decision(:selection, 'residential otherwise -> through-the-wall systems',
                        target: group[:zones].join(','), article: res['article'])
        Assignment.new(zones: group[:zones], category: category, reference_system: 1,
                       action: :through_the_wall, articles: articles)
      end
    end

    # D-37 (A2 ruled, phylroy 2026-07-28): the printed 8.4.4.13 split, with the
    # boundary from Note A-8.4.4.13 — a water-LOOP heat pump (internal loop;
    # aux boiler and/or cooling tower explicitly allowed) KEEPS its Table -A
    # selection per sentence (1); air-, water- and ground-SOURCE heat pumps
    # redirect to the ASHP reference per sentence (2). A detected heat pump
    # with no source evidence keeps the redirect (pre-D-37 behavior — the
    # conservative reading when the source loop is unclassifiable).
    def self.heat_pump_redirects?(group)
      return false unless group[:heat_pump]

      sources = group[:heat_pump_sources] || []
      return true if sources.empty?

      sources.any? { |s| s != :water_loop }
    end

    # 'air-cooled unitary, packaged terminal or room air conditioner, or fan coils'
    # (the "(or heat pumps)" parenthetical is superseded by the 8.4.4.7.(4)
    # redirect per D-34 — REDIRECTING heat-pump groups never reach this check;
    # water-loop HPs do per D-37 and 'wshp' is in the allowlist)
    def self.residential_compatible_cooling?(group)
      return true if %i[zonal_heat_cool packaged_single_zone].include?(group[:family_guess])

      %w[psz mau_ptac zone_terminal fan_coils wshp vrf].include?(group[:family])
    end

    # ---- finalize: heat-pump override, energy type, catalog name ----

    def self.finalize(assignment, group, definitions, selection, facts, audit)
      return assignment if assignment.action == :copy_proposed

      hp_rule = selection['special_rules']['heat_pump']
      if heat_pump_redirects?(group) && hp_rule['applies_to_systems'].include?(assignment.reference_system)
        audit&.decision(:selection, 'proposed heat pump -> reference is an air-source heat pump (Table 8.4.4.13)',
                        target: group[:zones].join(','),
                        inputs: { selected_system: assignment.reference_system,
                                  heat_pump_sources: group[:heat_pump_sources] },
                        value: 'hp', article: hp_rule['article'], ruling: 'D-37')
        assignment.reference_system = 'hp'
        assignment.articles << hp_rule['article']
      elsif group[:heat_pump] && !heat_pump_redirects?(group)
        audit&.decision(:selection, 'water-loop heat pump — Table 8.4.4.7.-A selection retained (no ASHP redirect)',
                        target: group[:zones].join(','),
                        inputs: { selected_system: assignment.reference_system },
                        article: '8.4.4.13.(1); Note A-8.4.4.13', ruling: 'D-37')
      end

      assignment.energy_type = reference_energy_type(group, selection, facts, audit)
      definition = definitions.fetch(assignment.reference_system.to_s)
      variant = definition.fetch(assignment.energy_type)
      assignment.catalog_name = variant.fetch('name')
      assignment.config = variant['config']

      # D-39 (A4 ruled conditional, phylroy 2026-07-28): Table 8.4.4.7.-B lists
      # System 5's heating as "None", but 8.4.4.1.(5) requires the presence or
      # absence of heating per thermal block to be IDENTICAL to the proposed.
      # Reconciliation: the table's "None" governs the default composition
      # (cooling-only TPFC when the proposed block is unheated); sentence (5)
      # overrides presence when the proposed block IS heated (the existing
      # two-pipe changeover heating is kept — no system invented).
      if assignment.reference_system == 5
        if group[:heated]
          audit&.decision(:selection, 'System 5 reference keeps its heating — proposed block is heated, 8.4.4.1.(5) presence override of the Table -B "None" heating column',
                          target: group[:zones].join(','),
                          article: '8.4.4.1.(5); Table 8.4.4.7.-B', ruling: 'D-39')
        else
          assignment.config = (assignment.config || {}).merge(
            'heating' => 'none', 'needs_boiler' => false, 'mau_heating_coil_type' => 'None'
          )
          audit&.decision(:selection, 'System 5 reference built COOLING-ONLY — Table 8.4.4.7.-B heating "None" honoured (proposed block is unheated)',
                          target: group[:zones].join(','),
                          article: 'Table 8.4.4.7.-B; 8.4.4.1.(5)', ruling: 'D-39')
        end
      end

      # 8.4.4.6.(2)/8.4.5.6.(2): purchased cooling is represented by an air-cooled
      # electric chiller.
      if facts.dig(:purchased_energy, :cooling) || group[:cooling_energy_types].include?('Purchased')
        pc = selection['special_rules']['purchased_cooling']
        assignment.config = (assignment.config || {}).merge('chw_source' => pc['chiller_source'])
        assignment.articles << pc['article']
        audit&.decision(:selection, 'purchased cooling energy -> represented by air-cooled electric chiller',
                        target: group[:zones].join(','), article: pc['article'])
      end

      audit&.decision(:selection, 'reference system selected',
                      target: group[:air_loop] || group[:zones].join(','),
                      inputs: { category: assignment.category, energy_type: assignment.energy_type,
                                heated: group[:heated], cooled: group[:cooled],
                                cooling_kw: group[:design_cooling_kw] },
                      value: "System #{assignment.reference_system} -> '#{assignment.catalog_name}'",
                      article: assignment.articles.compact.uniq.join('; '))
      assignment
    end

    # ==================== the proposed -> reference HVAC transform ====================

    ReferenceResult = Struct.new(:model, :assignments, :audit, keyword_init: true)

    # Generate the NECB reference HVAC for a proposed model (any OSM). The proposed
    # model is untouched: the reference is built on a clone.
    #
    # Pipeline (all article-tagged in the audit): characterize the proposed HVAC ->
    # select reference systems per Table 8.4.4.7.-A -> replace each zone group's HVAC
    # with the mapped catalog system (energy type follows proposed) -> apply the
    # reference modeling rules (8.4.4.8 oversizing caps, 8.4.4.18 fan specs, 8.4.4.13
    # heat-pump operating limits) -> apply vintage minimum efficiencies.
    #
    # Sizing: the gem never runs simulations. Capacity-threshold selection rules and
    # the proposed-oversizing comparison use sized values when present and warn when
    # not; run your sizing pass on the proposed model first for full fidelity, and on
    # the returned reference model before applying downstream (efficiencies re-apply
    # cleanly via NECB.apply_efficiencies after sizing).
    #
    # @param model [OpenStudio::Model::Model] the proposed model
    # @param vintage [String]
    # @param building [Hash, nil] overrides for :storeys, :zone_types,
    #   :kitchen_hood_zones, :refrigerated_zones (defaults derived from the model)
    # @param audit [AuditLog, nil]
    # @return [ReferenceResult] model (clone), assignments, audit
    def self.reference_hvac(model, vintage: '2020', building: nil, audit: nil)
      audit ||= AuditLog.new
      reference = clone_model(model)

      facts = Classify.characterize(reference, audit: audit)
      info = building_info(reference, building, audit)
      assignments = select_reference_systems(facts: facts, building: info,
                                             vintage: vintage, audit: audit)

      ruleset = rules(vintage)
      zones_by_name = reference.getThermalZones.to_h { |z| [z.nameString, z] }
      # 8.4.3.2.(1): operating schedules identical in both buildings — capture
      # each zone's PROPOSED air-system availability schedule now, while the
      # clone still carries the proposed HVAC (D-14; feeds the reference fan
      # operation AND the 5.2.10.1 continuous/non-continuous classification).
      proposed_availability = {}
      reference.getAirLoopHVACs.each do |loop_|
        loop_.thermalZones.each { |z| proposed_availability[z.nameString] = loop_.availabilitySchedule }
      end
      # T7 (8.4.4.15.(1)): OA identity rests on cloned DesignSpecification:OutdoorAir;
      # a hard-set proposed minimum-OA controller value would silently diverge.
      reference.getControllerOutdoorAirs.each do |c|
        next unless c.minimumOutdoorAirFlowRate.is_initialized

        audit.warn(:build, "proposed OA controller '#{c.nameString}' carries a HARD-SET minimum OA "                            "(#{(c.minimumOutdoorAirFlowRate.get * 1000).round(0)} L/s) — the rebuilt reference "                            'autosizes OA from the space DSOA; verify 8.4.4.15.(1) identity',
                   article: '8.4.4.15.(1)', ruling: 'D-22')
      end
      # T8 (Table 8.4.4.7.-B note (1)): humidifiers on replaced loops vanish with
      # the loop; the reference would silently lose humidification.
      humidifiers = reference.getHumidifierSteamElectrics.size + reference.getHumidifierSteamGass.size
      if humidifiers.positive?
        audit.warn(:build, "proposed model has #{humidifiers} humidifier(s) — reference humidification with the "                            'same energy source is NOT rebuilt (Table 8.4.4.7.-B note (1)) — modeller attention',
                   article: '8.4.4.7.', ruling: 'D-22')
      end
      # D-28 (LargeOffice end-use isolation): Note (3) to Table 8.4.4.7.-B
      # scopes a MULTIZONE reference system to the thermal blocks of ALL
      # storeys — one system at <=4 above-ground storeys, per-facade splits
      # (inside the builder's zone_groups) above. The proposed archetypes
      # partition their zones per STOREY, and building one reference system
      # per selection group leaked that partition into the reference: the
      # 12-storey LargeOffice got 3 storey-groups x (4 facades + internal)
      # = 17 systems instead of ~6, multiplying fans and dodging the
      # per-loop 5.2.10.1/5.2.2.7 flow thresholds. Merge same-catalog
      # multizone (sys 2/5/6) build assignments; single-zone families
      # (1/3/4/hp) keep their selection grouping.
      merged = []
      assignments.each do |a|
        key = a.action == :build && [2, 5, 6].include?(a.reference_system) ? [a.catalog_name, a.config] : nil
        existing = key && merged.find { |m| m.first == key }
        if existing
          existing.last.zones.concat(a.zones - existing.last.zones)
          existing.last.articles.concat(a.articles)
        else
          merged << [key, a]
        end
      end
      if merged.size < assignments.size
        audit.decision(:build, 'multizone selection groups merged into whole-building systems',
                       inputs: { selection_groups: assignments.size, merged_groups: merged.size },
                       value: 'one multizone system spans the thermal blocks of all storeys; facade/internal/underground split applied inside the builder',
                       article: 'Table 8.4.4.7.-B Note (3)', ruling: 'D-28')
      end
      assignments = merged.map(&:last)

      assignments.each do |assignment|
        if assignment.action == :copy_proposed
          audit.info(:build, 'proposed system retained in reference (residential rule)',
                     target: assignment.zones.join(','),
                     article: assignment.articles.compact.join('; '))
          next
        end

        zones = assignment.zones.map { |n| zones_by_name.fetch(n) }
        result = OpenStudioHVAC.replace_system(reference, assignment.catalog_name, zones,
                                               config: assignment.config)
        audit.decision(:build, 'reference system built', target: assignment.zones.join(','),
                       inputs: { system: assignment.reference_system, action: assignment.action },
                       value: assignment.catalog_name,
                       article: assignment.articles.compact.uniq.join('; '))
        apply_fan_rules(result.air_loops, assignment.reference_system, ruleset, audit)
        apply_zone_fan_rules(zones, assignment.reference_system, ruleset, audit)
        apply_heat_pump_limits(result.air_loops, ruleset, audit) if assignment.reference_system == 'hp'
        apply_economizers(result.air_loops, assignment.reference_system, vintage, audit)
        apply_operating_schedules(result.air_loops, proposed_availability, audit)
        audit_terminal_secondary_split(zones, assignment.reference_system, vintage, audit)
      end

      purge_orphaned_ems(reference, audit)
      apply_oversizing_caps(model, reference, ruleset, audit)
      Efficiency.apply(reference, vintage: vintage, audit: audit)
      emit_article_coverage(ruleset, audit)

      ReferenceResult.new(model: reference, assignments: assignments, audit: audit)
    end

    # 8.4.4.9.(3) / 8.4.4.10.(7) (2025: 8.4.5.9.(3)/8.4.5.10.(7)) — the
    # terminal/secondary capacity split, D-50. Reference systems 1, 2 and 5 put
    # heating and/or cooling in BOTH a zone terminal (PTAC / four- or two-pipe
    # fan coil) and a make-up-air secondary system, so the sentences bind. The
    # builder realizes them through Sizing:Zone dedicated-outdoor-air accounting
    # with a neutral supply-air strategy: the terminal's design load excludes the
    # ventilation air, and the combined pair still meets the design-day peak
    # because both are sized on the same design day. Systems 3, 4 and 6 mix
    # outdoor air into the supply stream instead of feeding it to the zone
    # separately, so EnergyPlus has no equivalent accounting for them — declared,
    # not silently assumed.
    def self.audit_terminal_secondary_split(zones, reference_system, vintage, audit)
      prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
      article = "#{prefix}.9.(3); #{prefix}.10.(7)"
      accounted = zones.count { |z| z.sizingZone.accountforDedicatedOutdoorAirSystem }
      if accounted.positive?
        audit.decision(:rules, 'terminal/secondary capacity split accounted at zone sizing',
                       target: zones.map(&:nameString).join(','),
                       inputs: { zones: accounted, reference_system: reference_system,
                                 strategy: 'NeutralSupplyAir' },
                       value: 'terminal sized on the space load alone; the make-up-air unit carries the ' \
                              'ventilation load at system level',
                       article: article, ruling: 'D-50')
        return
      end
      return unless [3, 4, 6, 'hp'].include?(reference_system)

      audit.info(:rules, "system #{reference_system} mixes outdoor air into the supply stream, so the " \
                         'terminal/secondary split is approximated by ordinary mixed-air zone sizing ' \
                         '(baseboards take the residual space load the air system does not meet)',
                 target: zones.map(&:nameString).join(','),
                 inputs: { zones: zones.size, reference_system: reference_system },
                 article: article, ruling: 'D-50')
    end

    # T10 (audit 2026-07-25): 8.4.4.18.(3) fan spec (640 Pa / 40% combined)
    # covers HVAC systems 1-5 — including their ZONE-equipment supply fans
    # (fan coils, PTAC/PTHP OnOff fans), which previously kept SDK defaults.
    def self.apply_zone_fan_rules(zones, reference_system, ruleset, audit)
      return if reference_system == 6

      spec = ruleset.dig('fans', 'systems_1_3_4_5', 'supply') || {}
      pressure = spec['pressure_rise_pa'] || 640.0
      eff = spec['total_efficiency'] || 0.40
      touched = 0
      zones.each do |zone|
        zone.equipment.each do |eq|
          [eq.to_ZoneHVACFourPipeFanCoil, eq.to_ZoneHVACPackagedTerminalAirConditioner,
           eq.to_ZoneHVACPackagedTerminalHeatPump].each do |opt|
            next if opt.empty?

            fan = opt.get.supplyAirFan
            [fan.to_FanOnOff, fan.to_FanConstantVolume, fan.to_FanVariableVolume].each do |f|
              next if f.empty?

              f.get.setPressureRise(pressure)
              f.get.setFanTotalEfficiency(eff)
              touched += 1
            end
          end
        end
      end
      return if touched.zero?

      audit.decision(:build, 'zone-equipment supply fans set to the systems 1-5 spec',
                     inputs: { fans: touched, pressure_pa: pressure, total_efficiency: eff },
                     value: "#{touched} zone fan(s) at #{pressure} Pa / #{(eff * 100).round}%",
                     article: '8.4.4.18.(3)', ruling: 'D-22')
    end

    # T3 (audit 2026-07-25): 8.4.4.12 economizers apply only where Article
    # 5.2.2.7 applies to the proposed system — mechanical cooling AND (sized
    # supply > 1500 L/s OR cooling capacity > 20 kW); dwelling-only/hotel
    # systems exempt (approximated: System 1 already exempt per D-20; zone
    # types are not re-derivable here). POST-SIZING pass, umbrella-called
    # alongside apply_energy_recovery: strips economizers from loops below
    # the trigger, loudly.
    def self.apply_economizer_thresholds(model, audit: nil)
      audit ||= AuditLog.new
      model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        oa = air_loop.airLoopHVACOutdoorAirSystem
        next if oa.empty?

        ctrl = oa.get.getControllerOutdoorAir
        next if ctrl.getEconomizerControlType == 'NoEconomizer'

        supply = optional_flow(air_loop.designSupplyAirFlowRate) || optional_flow(air_loop.autosizedDesignSupplyAirFlowRate)
        # Coils.supply_components descends into AirLoopHVACUnitarySystem containers:
        # a staged reference system's DX capacity lives on the TOP stage inside the
        # unitary, invisible to a plain supplyComponents scan.
        components = Coils.supply_components(air_loop)
        cooling_w = components.sum do |c|
          single = c.to_CoilCoolingDXSingleSpeed
          unless single.empty?
            next optional_flow(single.get.ratedTotalCoolingCapacity) ||
                 optional_flow(single.get.autosizedRatedTotalCoolingCapacity) || 0.0
          end
          staged = c.to_CoilCoolingDXMultiSpeed
          next 0.0 if staged.empty?

          top = staged.get.stages.last
          next 0.0 if top.nil?

          optional_flow(top.grossRatedTotalCoolingCapacity) ||
            optional_flow(top.autosizedGrossRatedTotalCoolingCapacity) || 0.0
        end
        chw = components.any? { |c| c.to_CoilCoolingWater.is_initialized }
        if supply.nil?
          audit.warn(:rules, "#{air_loop.nameString}: supply flow not sized — 5.2.2.7 economizer trigger "                              'not evaluated (economizer retained)', article: '5.2.2.7.(1)', ruling: 'D-22')
          next
        end
        # chilled-water systems (sys 2/5/6) are large by construction; the kW
        # branch is only decidable for DX. Trigger: >1500 L/s or >20 kW.
        triggered = supply * 1000.0 > 1500.0 || cooling_w > 20_000.0 || (chw && supply * 1000.0 > 1500.0)
        if triggered
          audit.decision(:rules, 'economizer retained (5.2.2.7 trigger met)',
                         target: air_loop.nameString,
                         inputs: { supply_l_s: (supply * 1000).round(0), cooling_kw: (cooling_w / 1000.0).round(1) },
                         value: ctrl.getEconomizerControlType, article: '8.4.4.12.; 5.2.2.7.(1)', ruling: 'D-22')
        else
          ctrl.setEconomizerControlType('NoEconomizer')
          audit.decision(:rules, 'economizer REMOVED — below the 5.2.2.7 trigger (<=1500 L/s and <=20 kW)',
                         target: air_loop.nameString,
                         inputs: { supply_l_s: (supply * 1000).round(0), cooling_kw: (cooling_w / 1000.0).round(1) },
                         value: 'NoEconomizer', article: '8.4.4.12.; 5.2.2.7.(1)', ruling: 'D-22')
        end
      end
      audit
    end

    # D-16: proposed-model EMS artifacts (optimum-start programs etc.) whose
    # referenced objects were removed with the proposed HVAC would reach
    # EnergyPlus as unresolvable {UUID} tokens and FATAL the reference sizing
    # run (found by the archetype breadth sweep: legacy sys_4 archetypes).
    # Programs with dangling handle references are removed along with their
    # calling managers; actuators whose targets are gone likewise. Every
    # removal is audited — the reference's controls come from the reference
    # ruleset, never from proposed EMS overrides.
    def self.purge_orphaned_ems(model, audit)
      uuid_re = /\{[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}\}/
      dangling = lambda do |text|
        text.to_s.scan(uuid_re).any? { |u| model.getModelObject(OpenStudio.toUUID(u)).empty? }
      end
      removed = []
      model.getEnergyManagementSystemPrograms.each do |prog|
        next unless prog.lines.any? { |ln| dangling.call(ln) }

        removed << "program #{prog.nameString}"
        model.getEnergyManagementSystemProgramCallingManagers.each do |mgr|
          mgr.programs.each_with_index do |p, i|
            mgr.eraseProgram(i) if p.handle == prog.handle
          end
          next unless mgr.programs.empty?

          removed << "calling manager #{mgr.nameString}"
          mgr.remove
        end
        prog.remove
      end
      model.getEnergyManagementSystemActuators.each do |act|
        next unless act.actuatedComponent.empty?

        removed << "actuator #{act.nameString}"
        act.remove
      end
      return if removed.empty?

      audit.warn(:build, 'proposed EMS artifacts with DANGLING references removed from the reference ' \
                         "(#{removed.size}): #{removed.first(6).join('; ')}#{removed.size > 6 ? ' …' : ''} — " \
                         'reference controls come from the reference ruleset, not proposed EMS overrides',
                 article: '8.4.4.1.', ruling: 'D-16')
    end

    # D-14: reference air systems inherit the proposed's operating schedule
    # (8.4.3.2.(1) — operating schedules identical in both buildings). One
    # schedule among the loop's zones -> applied; none (proposed had no air
    # system there, e.g. baseboards) -> builder default retained with an info
    # note; several -> the schedule serving the most zones wins, with a loud
    # warning. Schedules survive replace_system (removing a loop never deletes
    # shared schedules).
    # A staged system's fan lives INSIDE its AirLoopHVACUnitarySystem, where the
    # loop's availability schedule does not reach it — the unitary carries its
    # own. Left at the always-on default, a staged reference fan runs 8760 h no
    # matter what 8.4.3.2.(1) says the system's hours are: measured at 2.7x the
    # proposed's fan energy on the Warehouse, against 0.98x for the same
    # building before staging. So the unitary inherits the SAME schedule the
    # loop just got. (Only the availability: the fan OPERATING MODE stays
    # continuous, as a constant-volume system's does, and EnergyPlus rejects a
    # mode schedule containing zeros for that field outright.)
    def self.apply_unitary_operating_schedule(loop_, chosen)
      loop_.supplyComponents.each do |comp|
        unitary = comp.to_AirLoopHVACUnitarySystem
        next if unitary.empty?

        unitary.get.setAvailabilitySchedule(chosen)
      end
    end

    def self.apply_operating_schedules(air_loops, proposed_availability, audit)
      air_loops.each do |loop_|
        schedules = loop_.thermalZones.filter_map { |z| proposed_availability[z.nameString] }
        if schedules.empty?
          loop_.setNightCycleControlType('CycleOnAny') # T5: harmless with Always On, correct once scheduled
          audit.info(:build, 'no proposed air-system operating schedule to inherit — builder default retained',
                     target: loop_.nameString, article: '8.4.3.2.(1)', ruling: 'D-14')
          next
        end
        tally = schedules.group_by(&:nameString)
        chosen = tally.max_by { |_, v| v.size }[1].first
        loop_.setAvailabilitySchedule(chosen)
        # T5 (audit 2026-07-25, legacy parity): night-cycle pickup during the
        # off-schedule hours, and the motorized-OA-damper behaviour — minimum
        # OA follows the operating schedule so the reference does not
        # ventilate 24/7 through a scheduled-off system.
        loop_.setNightCycleControlType('CycleOnAny')
        oa = loop_.airLoopHVACOutdoorAirSystem
        oa.get.getControllerOutdoorAir.setMinimumOutdoorAirSchedule(chosen) if oa.is_initialized
        apply_unitary_operating_schedule(loop_, chosen)
        if tally.size > 1
          audit.warn(:build, "zones carried #{tally.size} DIFFERENT proposed operating schedules — " \
                             "'#{chosen.nameString}' (most zones) applied to the whole reference loop",
                     target: loop_.nameString, article: '8.4.3.2.(1)', ruling: 'D-14')
        else
          audit.decision(:build, 'reference system operates on the proposed operating schedule',
                         target: loop_.nameString, inputs: { schedule: chosen.nameString },
                         value: chosen.nameString, article: '8.4.3.2.(1)', ruling: 'D-14')
        end
      end
    end

    # Completeness accounting: every article of the reference subsection is written to
    # the audit with its handling status and how many decisions cited it this run —
    # unimplemented or partially-implemented articles surface as warnings, so a missed
    # requirement is visible in every log rather than discovered by review.
    def self.emit_article_coverage(ruleset, audit)
      coverage = ruleset['article_coverage']
      return if coverage.nil?

      cited = Hash.new(0)
      audit.entries.each do |entry|
        entry[:article].to_s.scan(/8\.4\.\d+\.\d+\./) { |a| cited[a] += 1 }
      end

      coverage['articles'].each do |art|
        applied = cited.select { |a, _| a.start_with?(art['article']) }.values.sum
        inputs = { status: art['status'], decisions_citing: applied }
        inputs[:gap_owner] = art['gap_owner'] if art['gap_owner']
        if %w[implemented satisfied_by_clone host_scope].include?(art['status'])
          audit.info(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}#{art['how'] ? ": #{art['how']}" : ''}",
                     inputs: inputs, article: art['article'])
        elsif art['gap_owner'] == 'modeller' # scope note, not a warning (D-09)
          audit.info(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}, modeller scope" \
                                "#{art['how'] ? ". Applied: #{art['how']}" : ''}" \
                                "#{art['gaps'] ? ". Modeller's responsibility: #{art['gaps']}" : ''}",
                     inputs: inputs, article: art['article'])
        else # partial / not_implemented
          audit.warn(:coverage, "#{art['title']} — #{art['status'].tr('_', ' ')}" \
                                "#{art['how'] ? ". Applied: #{art['how']}" : ''}" \
                                "#{art['gaps'] ? ". Gaps: #{art['gaps']}" : ''}",
                     inputs: inputs, article: art['article'])
        end
      end
    end

    def self.clone_model(model)
      clone = model.clone
      clone.respond_to?(:to_Model) ? clone.to_Model : clone
    end

    # Building info defaults derived from the model, overridable by the caller.
    def self.building_info(model, overrides, audit)
      info = { storeys: Costing::Geometry.above_ground_storeys(model),
               zone_types: zone_space_types(model) }
      info.merge!(overrides.transform_keys(&:to_sym)) if overrides
      audit.info(:characterize, 'building info for selection',
                 inputs: { storeys: info[:storeys],
                           typed_zones: info[:zone_types].count { |_, v| !v.to_s.empty? } })
      info
    end

    def self.zone_space_types(model)
      model.getThermalZones.to_h do |zone|
        type = zone.spaces.filter_map do |space|
          st = space.spaceType
          next nil unless st.is_initialized

          st.get.standardsSpaceType.is_initialized ? st.get.standardsSpaceType.get : st.get.nameString
        end.first.to_s.sub(/\ASpace Function\s*/i, '')
        [zone.nameString, type]
      end
    end

    # 8.4.4.12 (2025: 8.4.5.12): reference cooling-with-outside-air. Table -12
    # routes systems 1/3/4/6 and all heat-pump systems to 5.2.2.8 (air
    # economizer: up to 100% outdoor air, differential reversion) and systems
    # 2/5 to 5.2.2.9 (WATER-side economizer — hydronic, not modeled: loud gap).
    def self.apply_economizers(air_loops, reference_system, vintage, audit)
      prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
      if [2, 5].include?(reference_system)
        audit.warn(:build, 'system 2/5 reference cooling-with-outside-air is the 5.2.2.9 WATER economizer — ' \
                           'hydronic economizers are not modeled (gap)', article: "#{prefix}.12.")
        return
      end
      # D-20: NO economizer on System 1 (100%-outdoor-air makeup air). An air
      # economizer cannot increase OA above a system that is already all
      # outdoor air, and its winter signal (outdoor enthalpy < return) LOCKS
      # OUT the 5.2.10.1 energy-recovery wheel through the HX economizer
      # lockout — disabling mandated heat recovery for the entire heating
      # season (found by the MURB fixed-point audit: the reference MAU heated
      # -20 C air unassisted all January; legacy correctly uses NoEconomizer).
      if reference_system == 1
        audit.info(:build, 'System 1 (100% OA makeup air): economizer not applicable — an all-outdoor-air ' \
                           'system cannot economize, and the economizer signal would lock out the 5.2.10.1 ' \
                           'energy-recovery wheel all winter', article: "#{prefix}.12.", ruling: 'D-20')
        return
      end

      Array(air_loops).each do |air_loop|
        oa_system = air_loop.airLoopHVACOutdoorAirSystem
        next if oa_system.empty?

        has_cooling = Coils.supply_components(air_loop).any? do |component|
          component.iddObjectType.valueName =~ /Coil_Cooling|CoilSystem_Cooling/
        end
        next unless has_cooling

        controller = oa_system.get.getControllerOutdoorAir
        controller.setEconomizerControlType('DifferentialEnthalpy')
        audit.decision(:build, 'air economizer applied (5.2.2.8: up to 100% outdoor air, differential-enthalpy reversion)',
                       target: air_loop.nameString,
                       article: "#{prefix}.12. (Table -12 -> 5.2.2.8)", ruling: 'D-20')
      end
    end

    # 8.4.4.18.(3): systems 1/3/4/5 -> supply fan 640 Pa @ 40% combined efficiency, no
    # return fan. 8.4.4.18.(4): system 6 -> supply 1000 Pa @ 55%, return 250 Pa @ 30%.
    def self.apply_fan_rules(air_loops, reference_system, ruleset, audit)
      fans = ruleset.fetch('fans')
      spec = reference_system == 6 ? fans['system_6'] : fans['systems_1_3_4_5']
      Array(air_loops).each do |air_loop|
        Coils.supply_components(air_loop).each do |comp|
          fan = comp.to_FanConstantVolume.is_initialized ? comp.to_FanConstantVolume.get : nil
          fan ||= comp.to_FanVariableVolume.is_initialized ? comp.to_FanVariableVolume.get : nil
          next if fan.nil?

          is_return = fan.nameString =~ /return/i
          pa = is_return ? spec['return_pa'] : spec['supply_pa']
          eff = is_return ? spec['return_efficiency'] : spec['supply_efficiency']
          next if pa.nil? # sys 1/3/4/5 has no return-fan spec

          fan.setPressureRise(pa)
          set_fan_total_efficiency(fan, eff)
          audit.decision(:rules, "#{is_return ? 'return' : 'supply'} fan set to reference spec",
                         target: fan.nameString,
                         value: "#{pa} Pa @ #{(eff * 100).round}% combined fan-motor efficiency",
                         article: fans['article'])
        end
      end
    end

    def self.set_fan_total_efficiency(fan, efficiency)
      if fan.respond_to?(:setFanTotalEfficiency)
        fan.setFanTotalEfficiency(efficiency)
      else
        fan.setFanEfficiency(efficiency)
      end
    end

    # 8.4.4.13.(2)(d): the reference heat pump shall not operate in heating mode below -10degC.
    def self.apply_heat_pump_limits(air_loops, ruleset, audit)
      cutoff = ruleset.fetch('heat_pump_reference')['heating_cutoff_oat_c']
      Array(air_loops).each do |air_loop|
        Coils.supply_components(air_loop).each do |comp|
          staged = comp.to_CoilHeatingDXMultiSpeed
          next unless comp.to_CoilHeatingDXSingleSpeed.is_initialized || staged.is_initialized

          coil = staged.is_initialized ? staged.get : comp.to_CoilHeatingDXSingleSpeed.get
          coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(cutoff)
          audit.decision(:rules, 'heat pump heating cutoff set', target: coil.nameString,
                         value: "compressor off below #{cutoff} degC",
                         article: ruleset.fetch('heat_pump_reference')['article'])
        end
      end
    end

    # 8.4.4.19 (2020) / 8.4.5.19 (2025): where Subsection 5.2.10 applies, the
    # reference system shall be modeled with energy recovery, used to preheat
    # the outside air — via NECB 2020/2025 Tables 5.2.10.1.-A/-B: the
    # airflow-threshold trigger, evaluated POST-SIZING (it needs the sized
    # supply and minimum-OA flows), called by the umbrella after the reference
    # sizing run. Replaces the NECB 2011 150 kW exhaust-heat-content trigger
    # previously implemented here — wrong vintage, and divergent exactly where
    # it matters: a small high-%OA system is "R (required at all flow rates)"
    # under 2020 while the 2011 formula waves it through (permissive).
    # Idempotent: loops already carrying an HX are skipped.
    def self.apply_energy_recovery(model, vintage: '2020', hdd:, audit: nil)
      audit ||= AuditLog.new
      rule = NECB.rules(vintage)['energy_recovery']
      return audit if rule.nil?

      model.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        oa_system = air_loop.airLoopHVACOutdoorAirSystem
        next if oa_system.empty? # no OA intake: 5.2.10 does not apply
        next if oa_system.get.oaComponents.any? { |c| c.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized }

        supply = optional_flow(air_loop.designSupplyAirFlowRate) ||
                 optional_flow(air_loop.autosizedDesignSupplyAirFlowRate)
        ctrl = oa_system.get.getControllerOutdoorAir
        min_oa = optional_flow(ctrl.minimumOutdoorAirFlowRate) ||
                 optional_flow(ctrl.autosizedMinimumOutdoorAirFlowRate)
        if supply.nil? || min_oa.nil? || supply.zero?
          audit.warn(:rules, '5.2.10.1 energy-recovery trigger needs SIZED supply/OA flows — not evaluated ' \
                             '(run sizing first)', target: air_loop.nameString, article: rule['trigger_article'],
                     ruling: 'D-06')
          next
        end

        supply_l_s = supply * 1000.0
        oa_pct = 100.0 * min_oa / supply
        hours = annual_availability_hours(air_loop)
        if hours.nil?
          audit.warn(:rules, 'fan availability hours not computable — conservatively classified CONTINUOUS',
                     target: air_loop.nameString, article: rule['trigger_article'], ruling: 'D-06')
        end
        mode = hours.nil? || hours >= rule['continuous_hours_per_year'] ? 'continuous' : 'non_continuous'
        required, threshold_desc = erv_threshold_verdict(rule, mode, hdd, oa_pct, supply_l_s)
        inputs = { supply_l_s: supply_l_s.round, min_oa_l_s: (min_oa * 1000).round,
                   oa_pct: oa_pct.round(1), operation: mode, annual_hours: hours&.round,
                   hdd: hdd, threshold: threshold_desc }
        if required
          erv = add_energy_recovery(air_loop, oa_system.get, rule)
          audit.decision(:rules, 'energy recovery added to reference system (Table 5.2.10.1 threshold met)',
                         target: air_loop.nameString, inputs: inputs,
                         value: "rotary HX @ #{(rule['effectiveness'] * 100).round}% sensible+latent effectiveness " \
                                "(= #{(rule['effectiveness'] * 100).round}% ENTHALPY effectiveness by identity, " \
                                "the 5.2.10.1.(4) minimum) with 5.2.10.1.(6) overshoot control (#{erv.nameString})",
                         article: "#{rule['article']}; #{rule['trigger_article']}; 5.2.10.1.(4); 5.2.10.1.(6)",
                         ruling: 'D-06 D-15')
        else
          audit.decision(:rules, 'energy recovery not required (below the Table 5.2.10.1 threshold)',
                         target: air_loop.nameString, inputs: inputs, article: rule['trigger_article'],
                         ruling: 'D-06')
        end
      end
      audit
    end

    # Table row by HDD, band by %OA. Cells: 'R' = required at all flow rates,
    # 'NR' = never, numeric = required at/above that supply flow (L/s).
    # Below the smallest band (<10% OA) is outside the Tables entirely -> NR.
    def self.erv_threshold_verdict(rule, mode, hdd, oa_pct, supply_l_s)
      bands = rule['oa_bands_pct']
      return [false, 'below 10% OA (outside Tables 5.2.10.1.-A/-B)'] if oa_pct < bands.first

      row = rule['thresholds_l_s'][mode].find { |r| hdd < r['hdd_max'] }
      cell = row['bands'][bands.rindex { |b| oa_pct >= b }]
      case cell
      when 'R' then [true, 'R (required at all flow rates)']
      when 'NR' then [false, 'NR (not required at any flow rate)']
      else [supply_l_s >= cell, ">= #{cell} L/s"]
      end
    end

    # Annual fan-availability hours from the air loop's availability schedule
    # (>= 8000 h/yr = continuously operating per the Table notes). Constant
    # schedules (incl. the SDK's Always On) count directly; rulesets are summed
    # hourly across the year; anything else is not computable (nil).
    def self.annual_availability_hours(air_loop)
      schedule = air_loop.availabilitySchedule
      constant = schedule.to_ScheduleConstant
      return constant.get.value.positive? ? 8760 : 0 if constant.is_initialized

      ruleset = schedule.to_ScheduleRuleset
      return nil unless ruleset.is_initialized

      y = air_loop.model.getYearDescription.assumedYear
      days = ruleset.get.getDaySchedules(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(1), 1, y),
                                         OpenStudio::Date.new(OpenStudio::MonthOfYear.new(12), 31, y))
      days.sum { |d| (1..24).count { |h| d.getValue(OpenStudio::Time.new(0, h, 0, 0)).positive? } }
    end

    def self.optional_flow(value)
      return value unless value.respond_to?(:is_initialized)

      value.is_initialized ? value.get : nil
    end

    # Legacy air_loop_hvac_apply_energy_recovery_ventilator recipe: rotary HX, 50%
    # effectiveness at all conditions, economizer lockout, ExhaustOnly frost control,
    # -23.3 degC threshold, and an OA-pretreat setpoint manager on the HX outlet.
    def self.add_energy_recovery(air_loop, oa_system, rule)
      model = air_loop.model
      hx = rule['hx']
      erv = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
      erv.setName("#{air_loop.nameString} ERV")
      erv.setHeatExchangerType(hx['type'])
      erv.setEconomizerLockout(hx['economizer_lockout'])
      erv.setSupplyAirOutletTemperatureControl(true)
      erv.setFrostControlType(hx['frost_control'])
      eff = rule['effectiveness']
      erv.setSensibleEffectivenessat100HeatingAirFlow(eff)
      erv.setLatentEffectivenessat100HeatingAirFlow(eff)
      erv.setSensibleEffectivenessat100CoolingAirFlow(eff)
      erv.setLatentEffectivenessat100CoolingAirFlow(eff)
      if erv.respond_to?(:setSensibleEffectivenessat75HeatingAirFlow)
        erv.setSensibleEffectivenessat75HeatingAirFlow(eff)
        erv.setLatentEffectivenessat75HeatingAirFlow(eff)
        erv.setSensibleEffectivenessat75CoolingAirFlow(eff)
        erv.setLatentEffectivenessat75CoolingAirFlow(eff)
      end
      erv.setThresholdTemperature(hx['threshold_temperature_c'])
      erv.setInitialDefrostTimeFraction(hx['initial_defrost_time_fraction'])
      erv.setRateofDefrostTimeFractionIncrease(hx['rate_of_defrost_increase'])
      erv.addToNode(oa_system.outboardOANode.get)

      # T6 (audit 2026-07-25): the wheel is not free — PNNL-20405 surrogate
      # for rotary-HX fan/motor parasitics (legacy parity), computed from the
      # sized min OA; and the OA controller must bypass the wheel when OA
      # exceeds minimum (economizer-compatible behaviour on mixed systems).
      ctrl = oa_system.getControllerOutdoorAir
      oa_flow = ctrl.minimumOutdoorAirFlowRate.is_initialized ? ctrl.minimumOutdoorAirFlowRate.get : nil
      oa_flow ||= ctrl.autosizedMinimumOutdoorAirFlowRate.is_initialized ? ctrl.autosizedMinimumOutdoorAirFlowRate.get : nil
      if oa_flow
        erv.setNominalElectricPower((oa_flow * 212.5 / 0.5) + (oa_flow * 0.9 * 162.5 / 0.5) + 50.0)
      end
      ctrl.setHeatRecoveryBypassControlType('BypassWhenOAFlowGreaterThanMinimum')

      spm = OpenStudio::Model::SetpointManagerOutdoorAirPretreat.new(model)
      spm.setMinimumSetpointTemperature(-99.0)
      spm.setMaximumSetpointTemperature(99.0)
      spm.setMinimumSetpointHumidityRatio(0.00001)
      spm.setMaximumSetpointHumidityRatio(1.0)
      mixed_air_node = oa_system.mixedAirModelObject.get.to_Node.get
      spm.setReferenceSetpointNode(mixed_air_node)
      spm.setMixedAirStreamNode(mixed_air_node)
      spm.setOutdoorAirStreamNode(oa_system.outboardOANode.get)
      spm.setReturnAirStreamNode(oa_system.returnAirModelObject.get.to_Node.get)
      spm.addToNode(erv.primaryAirOutletModelObject.get.to_Node.get)
      erv
    end

    # 8.4.4.8: reference oversizing = the lesser of the proposed oversizing and the cap
    # (30% heating / 10% cooling), applied via the model-wide sizing factors.
    def self.apply_oversizing_caps(proposed, reference, ruleset, audit)
      caps = ruleset.fetch('oversizing')
      sizing = proposed.getSizingParameters
      heat_prop = sizing.heatingSizingFactor
      cool_prop = sizing.coolingSizingFactor
      heat_ref = [heat_prop, 1.0 + caps['heating_max_fraction']].min
      cool_ref = [cool_prop, 1.0 + caps['cooling_max_fraction']].min
      ref_sizing = reference.getSizingParameters
      ref_sizing.setHeatingSizingFactor(heat_ref)
      ref_sizing.setCoolingSizingFactor(cool_ref)
      # T1 (audit 2026-07-25): zone-level sizing factors OVERRIDE the global
      # Sizing:Parameters in EnergyPlus, so the builders' generic 1.3/1.1 zone
      # stamps silently defeated this cap. Reset the GENERIC zone factors so
      # the capped globals govern; PRESERVE any non-generic factor (the HP
      # zone cooling factor 1.0 required by 8.4.4.13.(2)(b) "without
      # oversizing").
      cleared = 0
      reference.getSizingZones.each do |sz|
        if (sz.zoneHeatingSizingFactor.get - 1.3).abs < 1e-9
          sz.resetZoneHeatingSizingFactor
          cleared += 1
        end
        if (sz.zoneCoolingSizingFactor.get - 1.1).abs < 1e-9
          sz.resetZoneCoolingSizingFactor
          cleared += 1
        end
      rescue StandardError
        next # OptionalDouble empty on some SDK versions — nothing stamped, nothing to clear
      end
      audit.decision(:rules, 'equipment oversizing capped',
                     inputs: { proposed_heating: heat_prop, proposed_cooling: cool_prop,
                               generic_zone_factors_cleared: cleared },
                     value: "heating sizing factor #{heat_ref.round(3)} = min(proposed #{heat_prop.round(3)}, cap #{(1.0 + caps['heating_max_fraction']).round(2)}); " \
                            "cooling #{cool_ref.round(3)} = min(proposed #{cool_prop.round(3)}, cap #{(1.0 + caps['cooling_max_fraction']).round(2)})",
                     article: caps['article'], ruling: 'D-22')
    end

    # 8.4.4.9.(4)/8.4.4.10.(3): reference energy type follows the proposed system;
    # 8.4.4.6.(1): purchased heating is represented by a gas-fired boiler.
    def self.reference_energy_type(group, selection, facts, audit)
      fuels = group[:heating_energy_types]
      if fuels.include?('Purchased') || facts.dig(:purchased_energy, :heating)
        audit&.decision(:selection, 'purchased heating energy -> represented by gas-fired modulating boiler',
                        target: group[:zones].join(','),
                        article: selection['special_rules']['purchased_heating']['article'])
        return 'gas'
      end
      return 'gas' if fuels.any? { |f| f =~ /gas|oil|propane/i }
      return 'electric' if fuels.include?('Electricity')

      audit&.warn(:selection, 'no proposed heating energy type detected — electric reference assumed',
                  target: group[:zones].join(','), article: '8.4.4.9.(4)')
      'electric'
    end
  end
end
