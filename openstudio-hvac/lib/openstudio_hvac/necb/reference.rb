require 'json'

module OpenStudioHVAC
  # NECB performance-path helpers: reference HVAC selection (Table 8.4.4.7.-A/-B) and,
  # in later phases, the proposed->reference transform and vintage efficiency application.
  # All rule content lives in data/necb/reference_rules_<vintage>.json (vendored, with
  # article-level provenance); this code is a rules interpreter, not a rules store.
  module NECB
    RULES_DIR = File.expand_path('../data/necb', __dir__)

    # Load (and memoize) the vendored NECB reference ruleset for a vintage.
    # @param vintage [String] NECB vintage ('2020' or '2025')
    # @return [Hash] parsed data/necb/reference_rules_<vintage>.json
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
    def self.select_reference_systems(facts:, building:, vintage: '2020', audit: nil, proposed_annual: nil)
      ruleset = rules(vintage)
      selection = ruleset.fetch('selection')
      definitions = ruleset.fetch('system_definitions')
      hp_rules = ruleset.fetch('heat_pump_reference')

      facts.fetch(:zone_groups).map do |group|
        next unless group[:heated] || group[:cooled] # unconditioned: no reference system

        category = category_for(group, building, selection, audit)
        assignment = assign(group, category, building, selection, audit)
        finalize(assignment, group, definitions, selection, facts, audit,
                 hp_rules: hp_rules, proposed_annual: proposed_annual)
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
      audit_museum_row(group, building, category, audit)
      category
    end

    # D-45: a museum space can read as two Table 8.4.4.7.-A rows — Assembly Area
    # lists "exhibit space", Historical Collections Area lists "archival
    # library, museum and gallery archives". The ruling reads the latter as the
    # ARCHIVES of museums and galleries (the row is a COLLECTIONS row, and
    # System 2's close control suits stored collections), so a museum's public
    # exhibition gallery is an exhibit space -> Assembly Area, while its
    # archives and restoration/conservation rooms -> Historical Collections.
    # Recorded whenever a museum space is elected so the reader sees which row
    # was taken and why, rather than having to infer it from the system number.
    def self.audit_museum_row(group, building, category, audit)
      return if audit.nil?

      types = group[:zones].filter_map { |z| (building[:zone_types] || {})[z] }
                           .select { |t| t.to_s.downcase.include?('museum') }.uniq
      return if types.empty?

      audit.info(:selection, "museum space classified as #{category} — the Table 8.4.4.7.-A collections row " \
                             'covers museum and gallery ARCHIVES; a public exhibition gallery is an exhibit ' \
                             'space and takes the assembly row',
                 target: group[:air_loop] || group[:zones].first,
                 inputs: { space_types: types, category: category },
                 article: '8.4.4.7.(1)', ruling: 'D-45')
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

    def self.condition_met?(rule, group, building, audit)
      case rule['condition']
      when 'kitchen_hood'
        # A hood is a condition the MODEL cannot express — only the
        # building[:kitchen_hood_zones] override can assert it. Electing the
        # unhooded row without the override ever being provided is an
        # ASSUMPTION the audit must state, not a silent default: the hooded
        # row selects System 4 instead of 3 (Table -A Supermarket/Food row).
        unless building.key?(:kitchen_hood_zones)
          audit&.warn(:selection, 'no kitchen_hood_zones override provided — food-preparation spaces in this ' \
                                  'block are ASSUMED to have no kitchen hood or vented appliance (the hooded ' \
                                  'row would select System 4); pass building: {kitchen_hood_zones: [...]} if ' \
                                  'any space has one',
                      target: group[:zones].join(','), article: 'Table 8.4.4.7.-A (Supermarket/Food Service)')
        end
        (building[:kitchen_hood_zones] || []).intersect?(group[:zones])
      when 'refrigerated'
        unless building.key?(:refrigerated_zones)
          audit&.warn(:selection, 'no refrigerated_zones override provided — warehouse spaces in this block ' \
                                  'are ASSUMED non-refrigerated (a refrigerated space would select System 5 ' \
                                  'instead of 4); pass building: {refrigerated_zones: [...]} if any space is',
                      target: group[:zones].join(','), article: 'Table 8.4.4.7.-A (Warehouse Area)')
        end
        (building[:refrigerated_zones] || []).intersect?(group[:zones])
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
                        target: group[:zones].join(','),
                        inputs: { zonal_units: group[:zonal_units], loop_dx_cooling: group[:loop_dx_cooling],
                                  family: group[:family] || group[:family_guess] },
                        article: res['article'], ruling: 'D-58')
        Assignment.new(zones: group[:zones], category: category, reference_system: nil,
                       action: :copy_proposed, articles: articles)
      else
        audit&.decision(:selection, 'residential otherwise -> through-the-wall systems',
                        target: group[:zones].join(','),
                        inputs: { zonal_units: group[:zonal_units], loop_dx_cooling: group[:loop_dx_cooling],
                                  family: group[:family] || group[:family_guess] },
                        article: res['article'], ruling: 'D-58')
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
    # water-loop HPs do per D-37 and 'wshp' is in the allowlist).
    #
    # D-58: the test is FACT-based, not name-based. The 97-system matrix showed
    # three ways the old family-string allowlist got Table -A wrong:
    #  * legacy pipe names put family STRINGS into :family_guess, which the old
    #    symbol test never matched — the fleet hotels' 53-zone MAU+PTAC guest
    #    blocks (zc>ptac, verbatim "packaged terminal air conditioner" in the
    #    parenthetical) were getting through-the-wall instead of the copy the
    #    printed table requires;
    #  * a scrubbed-name (foreign) MAU + fan-coil/PTAC building lost the copy
    #    because the structural guess reads the AIR LOOP only;
    #  * DOAS + fan-coil composites cool their zones with fan coils but carry a
    #    'doas'/'composite' family.
    # The facts: zones cooled by packaged-terminal/room units or fan coils
    # (:zonal_units), or by the loop's own DX on a no-reheat constant-volume
    # single-package shape (:loop_dx_cooling).
    COMPATIBLE_RESIDENTIAL_FAMILIES = %w[psz mau_ptac zone_terminal fan_coils wshp vrf].freeze
    COMPATIBLE_ZONAL_UNITS = %i[ptac pthp fan_coil vrf_terminal wshp].freeze

    def self.residential_compatible_cooling?(group)
      return true if %i[zonal_heat_cool packaged_single_zone].include?(group[:family_guess])
      return true if COMPATIBLE_RESIDENTIAL_FAMILIES.include?(group[:family].to_s) ||
                     COMPATIBLE_RESIDENTIAL_FAMILIES.include?(group[:family_guess].to_s)
      return true if (group[:zonal_units] || []).any? { |u| COMPATIBLE_ZONAL_UNITS.include?(u) }

      !group[:air_loop].nil? && group[:loop_dx_cooling] == true &&
        %i[none cv].include?(group[:terminal_type])
    end

    # ---- finalize: heat-pump override, energy type, catalog name ----

    def self.finalize(assignment, group, definitions, selection, facts, audit,
                      hp_rules: nil, proposed_annual: nil)
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

      assignment.energy_type = nil
      if assignment.reference_system == 'hp'
        assignment.energy_type = heat_pump_aux_energy_type(group, facts, hp_rules, proposed_annual, audit)
      end
      assignment.energy_type ||= reference_energy_type(group, selection, facts, audit)
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
    def self.reference_hvac(model, vintage: '2020', building: nil, audit: nil, proposed_annual: nil)
      audit ||= AuditLog.new
      reference = clone_model(model)

      facts = Classify.characterize(reference, audit: audit)
      info = building_info(reference, building, audit)
      assignments = select_reference_systems(facts: facts, building: info,
                                             vintage: vintage, audit: audit,
                                             proposed_annual: proposed_annual)

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
      # 8.4.4.15.(2) (D-54): the proposed's demand-control-ventilation strategy must be
      # reproduced in the reference, but the loops that carry it are about to be torn
      # down. Index it per zone off the characterization, which ran while the clone
      # still held the proposed HVAC.
      proposed_dcv = {}
      facts.fetch(:zone_groups).each do |group|
        next if group[:air_loop].nil?

        group[:zones].each do |zone_name|
          proposed_dcv[zone_name] = { dcv: group[:dcv], method: group[:system_outdoor_air_method],
                                      air_loop: group[:air_loop] }
        end
      end
      # T7 (8.4.4.15.(1)): OA identity rests on cloned DesignSpecification:OutdoorAir;
      # a hard-set proposed minimum-OA controller value would silently diverge.
      reference.getControllerOutdoorAirs.each do |c|
        next unless c.minimumOutdoorAirFlowRate.is_initialized

        audit.warn(:build, "proposed OA controller '#{c.nameString}' carries a HARD-SET minimum OA "                            "(#{(c.minimumOutdoorAirFlowRate.get * 1000).round(0)} L/s) — the rebuilt reference "                            'autosizes OA from the space DSOA; verify 8.4.4.15.(1) identity',
                   article: '8.4.4.15.(1)', ruling: 'D-22')
      end
      # Table 8.4.4.7.-B note (1) (D-55): record every proposed thermal block's
      # humidification and its energy source BEFORE the teardown destroys the loops
      # that carry it — the rebuild happens once the reference loops exist.
      proposed_humidification = capture_humidification(reference, audit)
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
        apply_economizers(reference, result.air_loops, assignment.reference_system, vintage, ruleset, audit)
        apply_dcv(result.air_loops, zones, proposed_dcv, vintage, audit)
        apply_operating_schedules(result.air_loops, proposed_availability, audit)
        audit_terminal_secondary_split(zones, assignment.reference_system, vintage, audit)
      end

      rebuild_humidification(reference, proposed_humidification, ruleset, vintage, audit)
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
    # alongside apply_energy_recovery (necb/energy_recovery.rb): strips
    # economizers from loops below
    # the trigger, loudly.
    # @param model [OpenStudio::Model::Model] sized reference model (modified in place)
    # @param audit [AuditLog, nil] audit to append to (a new one is created if nil)
    # @return [AuditLog] the audit carrying every keep/strip decision
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
      OpenStudioAudit::Coverage.emit(ruleset['article_coverage'], audit)
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

    # NECB standardsSpaceType per thermal zone (majority space type of the zone).
    # @param model [OpenStudio::Model::Model]
    # @return [Hash{String => String}] zone name => NECB space type ('' when untagged)
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
    # 2/5 to 5.2.2.9 (WATER-side economizer, built since D-56).
    def self.apply_economizers(model, air_loops, reference_system, vintage, ruleset, audit)
      prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
      if [2, 5].include?(reference_system)
        apply_water_economizer(model, reference_system, vintage, ruleset, audit)
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

    # ============ 5.2.2.9 water-side economizer, reference systems 2/5 (D-56) ============
    #
    # Table -12 sends reference systems 2 and 5 — the fan-coil systems, whose Table
    # 8.4.4.7.-B row prescribes a WATER-COOLED water chiller — to 5.2.2.9 rather than
    # to the air economizer of 5.2.2.8. 5.2.2.9 has two sentences, and WHICH ONE binds
    # follows from the heat-rejection equipment:
    #
    #   (1) chilling the distribution fluid by direct or indirect EVAPORATION ->
    #       capable of 100% of the cooling load at outdoor WET-BULB <= 7 C;
    #   (2) chilling it by SENSIBLE heat transfer -> at outdoor DRY-BULB <= 10 C.
    #
    # The reference plant rejects heat through a CoolingTowerSingleSpeed, which is an
    # evaporative device, so the economizer chills the chilled water by INDIRECT
    # evaporation and sentence (1) governs. Sentence (2) would bind a dry-cooler
    # arrangement, which the reference never builds — declared, not silently ignored.
    #
    # Realized as a plate heat exchanger between the condenser loop (source) and the
    # chilled-water loop (load), plus the tower setpoint reset WITHOUT WHICH the
    # economizer is inert: the builder pins the condenser loop at its 29 C design exit
    # temperature, and a tower held at 29 C can never deliver water colder than the
    # chilled-water return.
    def self.apply_water_economizer(model, reference_system, vintage, ruleset, audit)
      prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
      article = "#{prefix}.12. (Table -12 -> 5.2.2.9)"
      spec = ruleset.fetch('water_economizer')
      loops = chilled_water_loops(model)
      if loops.empty?
        audit.warn(:build, "reference system #{reference_system} routes to the 5.2.2.9 water economizer but the " \
                           'reference has NO chilled-water loop with a chiller — no economizer built',
                   article: article, ruling: 'D-56')
        return
      end

      loops.each { |chw| build_water_economizer(chw, reference_system, spec, article, audit) }
    end

    def self.chilled_water_loops(model)
      model.getPlantLoops.select do |plant_loop|
        plant_loop.supplyComponents(OpenStudio::Model::ChillerElectricEIR.iddObjectType).any?
      end
    end

    # The condenser loop is the one the chilled-water loop's water-cooled chillers
    # reject into (their secondary plant loop).
    def self.condenser_loop_for(chw)
      chw.supplyComponents(OpenStudio::Model::ChillerElectricEIR.iddObjectType)
         .filter_map { |c| c.to_ChillerElectricEIR.get.secondaryPlantLoop }
         .find(&:is_initialized)&.get
    end

    def self.build_water_economizer(chw, reference_system, spec, article, audit)
      if chw.supplyComponents(OpenStudio::Model::HeatExchangerFluidToFluid.iddObjectType).any?
        audit.info(:build, 'water-side economizer already present on this chilled-water loop — plant shared with ' \
                           'another reference system group', target: chw.nameString,
                   article: article, ruling: 'D-56')
        return
      end
      cw = condenser_loop_for(chw)
      if cw.nil?
        audit.warn(:build, "reference system #{reference_system} routes to the 5.2.2.9 water economizer, but this " \
                           'chilled-water loop rejects heat with NO condenser loop (air-cooled or purchased ' \
                           'cooling) — there is no evaporatively-cooled fluid to economize with, so none is built',
                   target: chw.nameString, article: article, ruling: 'D-56')
        return
      end

      hx = OpenStudio::Model::HeatExchangerFluidToFluid.new(chw.model)
      hx.setName('Water-Side Economizer HX')
      hx.setHeatExchangeModelType(spec['heat_exchanger_model_type'])
      hx.setHeatTransferMeteringEndUseType(spec['metering_end_use'])
      # Capability, not a guess: sizing factor 1.0 on autosized UA and both design
      # flows sizes the exchanger to the loop's FULL design cooling load, which is
      # what "capable of ... 100% of the cooling load" asks for. Never hard-sized
      # (L-23) — the reference sizing run and the D-43 capacity iteration still govern.
      hx.autosizeHeatExchangerUFactorTimesAreaValue
      hx.autosizeLoopSupplySideDesignFlowRate
      hx.autosizeLoopDemandSideDesignFlowRate
      hx.setSizingFactor(spec['sizing_factor'])
      hx.setControlType(spec['control_type'])
      unless chw.addSupplyBranchForComponent(hx) && cw.addDemandBranchForComponent(hx)
        hx.remove
        audit.warn(:build, 'the SDK REFUSED the water-side economizer topology on this plant — no economizer built',
                   target: chw.nameString, article: article, ruling: 'D-56')
        return
      end

      setpoint_c = chw.sizingPlant.designLoopExitTemperature
      OpenStudio::Model::SetpointManagerScheduled.new(
        chw.model, Schedules.constant_ruleset(chw.model, 'WSE HX Setpoint', setpoint_c)
      ).addToNode(hx.supplyOutletModelObject.get.to_Node.get)

      reset = reset_condenser_setpoint(cw, spec, audit, setpoint_c)
      audit.decision(:build, 'water-side economizer built (5.2.2.9: indirect evaporation, capable of 100% of the ' \
                             'cooling load at outdoor wet-bulb 7 C or lower)',
                     target: chw.nameString,
                     inputs: { reference_system: reference_system, source_loop: cw.nameString,
                               control: spec['control_type'], setpoint_c: setpoint_c,
                               sizing_factor: spec['sizing_factor'],
                               capability_wet_bulb_c: spec['capability_wet_bulb_c'],
                               condenser_setpoint_reset: reset },
                     value: 'HeatExchangerFluidToFluid between the condenser and chilled-water loops, sized for ' \
                            'the full design cooling load',
                     article: article, ruling: 'D-56')
      audit.info(:build, 'the 5.2.2.9.(2) sensible-transfer criterion (outdoor dry-bulb 10 C or lower) does not ' \
                         'apply: the reference rejects heat through an evaporative cooling tower, so the ' \
                         'economizer chills the distribution fluid by indirect evaporation and sentence (1) binds',
                 target: chw.nameString,
                 inputs: { capability_dry_bulb_c: spec['capability_dry_bulb_c'] },
                 article: article, ruling: 'D-56')
    end

    # Without this the economizer cannot operate at all: the tower is pinned at the
    # condenser loop's 29 C design exit temperature by plant_loops.rb, so the source
    # fluid is never colder than the chilled-water return. Reset it to follow the
    # outdoor WET BULB (the quantity an evaporative tower actually tracks) plus the
    # tower's own design approach, floored at the chilled-water setpoint — colder than
    # that buys no free cooling for a loop held at 7 C — and capped at the original
    # design exit temperature so nothing gets warmer than the builder intended.
    def self.reset_condenser_setpoint(cw, spec, audit, minimum)
      maximum = cw.sizingPlant.designLoopExitTemperature
      # designApproachTemperature is an OptionalDouble — unwrap, never pass it through.
      approach = cw.supplyComponents(OpenStudio::Model::CoolingTowerSingleSpeed.iddObjectType)
                   .filter_map { |t| optional_flow(t.to_CoolingTowerSingleSpeed.get.designApproachTemperature) }
                   .first || spec['condenser_reset_fallback_approach_k']
      cw.supplyOutletNode.setpointManagers.each(&:remove)
      manager = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(cw.model)
      manager.setName("#{cw.nameString} Economizer Reset")
      manager.setReferenceTemperatureType(spec['condenser_reset_reference'])
      manager.setOffsetTemperatureDifference(approach)
      manager.setMinimumSetpointTemperature(minimum)
      manager.setMaximumSetpointTemperature(maximum)
      manager.addToNode(cw.supplyOutletNode)
      reset = { reference: spec['condenser_reset_reference'], approach_k: approach,
                minimum_c: minimum, maximum_c: maximum }
      audit.decision(:build, 'condenser loop setpoint reset to follow the outdoor wet-bulb so the tower can make ' \
                             'the cold water the economizer needs',
                     target: cw.nameString, inputs: reset,
                     value: "#{spec['condenser_reset_reference']} + #{approach} K approach, " \
                            "clamped to #{minimum}-#{maximum} C",
                     article: '5.2.2.9.', ruling: 'D-56')
      reset
    end

    # ==================== Table 8.4.4.7.-B note (1): humidification (D-55) ====================
    #
    # "Where present, humidification systems in the reference building shall use the
    # same energy source as the corresponding humidification system in the proposed
    # building." Humidification was previously COUNTED before the teardown and merely
    # warned about — which warned even about humidifiers that go on to survive
    # untouched on :copy_proposed loops, and let the ones on replaced loops be
    # destroyed as a side effect of `air_loop.remove` rather than deliberately.
    #
    # Now: capture per thermal block before the teardown, rebuild on the serving
    # reference loop afterwards, on the same energy source, WITH a control that
    # actually operates it. An uncontrolled humidifier is silently inert in
    # EnergyPlus, so a rebuild without a working setpoint would be worse than the
    # warning it replaces.

    # HumidifierSteamGas is Humidifier:Steam:Gas, which EnergyPlus burns as natural
    # gas (the object carries no fuel-type field); HumidifierSteamElectric is
    # resistance steam. Those are the only two humidifier classes the SDK offers on
    # an air loop, so the energy source is always determinable for an attributable
    # humidifier — the undeterminable case is one we cannot attribute to a block.
    def self.humidifier_kind(component)
      return :gas if component.respond_to?(:to_HumidifierSteamGas) && component.to_HumidifierSteamGas.is_initialized
      return :electric if component.respond_to?(:to_HumidifierSteamElectric) && component.to_HumidifierSteamElectric.is_initialized

      nil
    end

    def self.air_loop_humidifier(air_loop)
      Coils.supply_components(air_loop).find { |component| humidifier_kind(component) }
    end

    # Record, per zone, the humidification of the proposed loop serving it, plus the
    # material needed to rebuild a working control: the proposed's own scheduled
    # minimum-humidity setpoint, if it used one. (A ZoneControlHumidistat lives on the
    # THERMAL ZONE, which the teardown does not touch, so it needs no capture.)
    def self.capture_humidification(reference, audit)
      captured = {}
      attributed = []
      reference.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        component = air_loop_humidifier(air_loop)
        next if component.nil?

        attributed << component.handle.to_s
        record = { kind: humidifier_kind(component), air_loop: air_loop.nameString,
                   name: component.nameString,
                   scheduled_setpoint: scheduled_humidity_setpoint(air_loop) }
        air_loop.thermalZones.each { |zone| captured[zone.nameString] = record }
        audit.info(:build, 'proposed humidification recorded for the reference rebuild',
                   target: air_loop.nameString,
                   inputs: { energy_source: humidifier_energy_source(record[:kind]),
                             zones: air_loop.thermalZones.size,
                             scheduled_setpoint: !record[:scheduled_setpoint].nil? },
                   value: component.nameString,
                   article: 'Table 8.4.4.7.-B Note (1)', ruling: 'D-55')
      end

      orphans = (reference.getHumidifierSteamElectrics + reference.getHumidifierSteamGass)
                .reject { |h| attributed.include?(h.handle.to_s) }
      unless orphans.empty?
        audit.warn(:build, "#{orphans.size} proposed humidifier(s) sit on NO air loop serving a thermal block " \
                           "(#{orphans.map(&:nameString).sort.join(', ')}) — the reference humidification they " \
                           'correspond to CANNOT be determined and is not rebuilt',
                   article: 'Table 8.4.4.7.-B Note (1)', ruling: 'D-55')
      end
      captured
    end

    def self.humidifier_energy_source(kind)
      kind == :gas ? 'NaturalGas' : 'Electricity'
    end

    # A scheduled minimum-humidity-ratio setpoint on the proposed loop is the only
    # humidity control that does NOT survive the teardown (it lives on a loop node);
    # keep the SCHEDULE so the rebuilt control uses the proposed's own setpoint.
    def self.scheduled_humidity_setpoint(air_loop)
      manager = air_loop.model.getSetpointManagerScheduleds.find do |spm|
        spm.controlVariable == 'MinimumHumidityRatio' &&
          spm.setpointNode.is_initialized && spm.setpointNode.get.airLoopHVAC.is_initialized &&
          spm.setpointNode.get.airLoopHVAC.get.handle == air_loop.handle
      end
      manager&.schedule
    end

    # Rebuild humidification on the reference loops, after they exist.
    def self.rebuild_humidification(reference, captured, ruleset, vintage, audit)
      return if captured.empty?

      spec = ruleset.fetch('humidification')
      article = "#{vintage.to_s == '2025' ? 'Table 8.4.5.7.-B' : 'Table 8.4.4.7.-B'} Note (1)"
      served = []
      reference.getAirLoopHVACs.sort_by(&:nameString).each do |air_loop|
        records = air_loop.thermalZones.filter_map { |zone| captured[zone.nameString] }
        next if records.empty?

        served |= records.map { |r| r[:air_loop] }
        if air_loop_humidifier(air_loop)
          audit.info(:build, 'proposed humidification retained on this reference loop — the loop was not replaced',
                     target: air_loop.nameString, article: article, ruling: 'D-55')
          next
        end
        build_reference_humidifier(air_loop, records, spec, article, audit)
      end

      missed = captured.values.map { |r| r[:air_loop] }.uniq - served
      return if missed.empty?

      audit.warn(:build, "the proposed humidification on #{missed.sort.join(', ')} has NO reference loop to carry " \
                         'it — the thermal blocks it served are unconditioned or zonally served in the reference, ' \
                         'so it is not rebuilt',
                 article: article, ruling: 'D-55')
    end

    def self.build_reference_humidifier(air_loop, records, spec, article, audit)
      kind = elect_humidifier_kind(air_loop, records, article, audit)
      source = humidifier_energy_source(kind)
      humidifier = if kind == :gas
                     OpenStudio::Model::HumidifierSteamGas.new(air_loop.model)
                   else
                     OpenStudio::Model::HumidifierSteamElectric.new(air_loop.model)
                   end
      humidifier.setName("#{air_loop.nameString} #{source} Steam Humidifier")
      # Never hard-size reference equipment (L-23): capacity follows the sizing run.
      humidifier.autosizeRatedCapacity if spec['autosize']
      humidifier.autosizeRatedPower if spec['autosize'] && humidifier.respond_to?(:autosizeRatedPower)
      unless humidifier.addToNode(air_loop.supplyOutletNode)
        humidifier.remove
        audit.warn(:build, 'the SDK REFUSED the reference humidifier on this supply path — humidification is NOT ' \
                           'rebuilt on this loop', target: air_loop.nameString, article: article, ruling: 'D-55')
        return
      end

      control = attach_humidity_control(air_loop, humidifier, records, spec)
      if control.nil?
        humidifier.remove
        audit.warn(:build, 'the proposed humidification on this thermal block has NO determinable humidity ' \
                           'control (no zone humidistat survives and the proposed used no scheduled minimum-humidity ' \
                           'setpoint) — an uncontrolled humidifier is INERT, so none is rebuilt',
                   target: air_loop.nameString, article: article, ruling: 'D-55')
        return
      end

      audit.decision(:build, 'reference humidification rebuilt on the proposed energy source',
                     target: air_loop.nameString,
                     inputs: { energy_source: source, proposed_systems: records.map { |r| r[:air_loop] }.uniq,
                               control: control, capacity: 'autosized' },
                     value: humidifier.nameString, article: article, ruling: 'D-55')
    end

    # Note (1) binds the SOURCE; where a reference system merges blocks whose proposed
    # humidifiers disagree, the majority source is taken and the divergence is shouted.
    def self.elect_humidifier_kind(air_loop, records, article, audit)
      votes = records.group_by { |r| r[:kind] }.transform_values(&:size)
      elected, = votes.max_by { |kind, count| [count, kind == :gas ? 1 : 0] }
      return elected if votes.size == 1

      audit.warn(:build, 'the proposed thermal blocks merged onto this reference system used DIFFERENT ' \
                         "humidification energy sources (#{votes.keys.map { |k| humidifier_energy_source(k) }.sort.join(', ')}) " \
                         "— note (1) is satisfied for the majority source (#{humidifier_energy_source(elected)}) only",
                 target: air_loop.nameString, article: article, ruling: 'D-55')
      elected
    end

    # The control has to come from the PROPOSED (8.4.3.2 identity), not be invented:
    # either a zone humidistat that survived the teardown on the zone, or the
    # proposed loop's own scheduled minimum-humidity setpoint.
    def self.attach_humidity_control(air_loop, humidifier, records, spec)
      node = humidifier.outletModelObject.get.to_Node.get
      zone = air_loop.thermalZones.sort_by(&:nameString).find { |z| z.zoneControlHumidistat.is_initialized }
      if zone
        manager = OpenStudio::Model::SetpointManagerSingleZoneHumidityMinimum.new(air_loop.model)
        manager.setName("#{air_loop.nameString} Min Humidity Setpoint Manager")
        manager.setControlZone(zone)
        manager.addToNode(node)
        return "#{spec['control']} on #{zone.nameString}'s humidistat"
      end

      schedule = records.filter_map { |r| r[:scheduled_setpoint] }.first
      return nil if schedule.nil?

      manager = OpenStudio::Model::SetpointManagerScheduled.new(air_loop.model, schedule)
      manager.setName("#{air_loop.nameString} Min Humidity Setpoint Manager")
      manager.setControlVariable('MinimumHumidityRatio')
      manager.addToNode(node)
      "#{spec['fallback_control']} on the proposed's schedule '#{schedule.nameString}'"
    end

    # 8.4.4.15.(2) (2025: 8.4.5.15.(2)), D-54 — "where demand control ventilation
    # strategies required by Article 5.2.3.4. are implemented in the proposed
    # building, the reference building shall be modeled with those same
    # strategies". The reference OA controller is rebuilt from scratch
    # (build_oa_system) with the gem's ZoneSum convention and DCV off, so the
    # proposed's strategy has to be copied back onto it.
    #
    # The strategy is the DCV FLAG plus, where it is itself a demand-control
    # method, the system outdoor-air method: CO2-based DCV rides
    # IndoorAirQualityProcedure and occupancy-proportional DCV rides the
    # ProportionalControl* methods, so copying only the flag would silently
    # substitute occupancy-based control for the proposed's strategy. The
    # PEAK-rate methods (ZoneSum, Standard 62.1 Ventilation Rate Procedure) are
    # NOT copied: those determine the peak ventilation rate, which is sentence
    # (1)'s subject, and the reference realizes (1) through the cloned
    # DesignSpecification:OutdoorAir under ZoneSum.
    # ==================== 8.4.4.15: demand-controlled ventilation follows the proposed ====================
    DCV_METHODS = %w[IndoorAirQualityProcedure IndoorAirQualityProcedureGenericContaminant
                     IndoorAirQualityProcedureCombined ProportionalControlBasedOnOccupancySchedule
                     ProportionalControlBasedOnDesignOccupancy ProportionalControlBasedOnDesignOARate].freeze

    def self.apply_dcv(air_loops, zones, proposed_dcv, vintage, audit)
      prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
      article = "#{prefix}.15.(2)"
      sources = zones.map(&:nameString).filter_map { |name| proposed_dcv[name] }
      enabled = sources.select { |s| s[:dcv] }

      Array(air_loops).each do |air_loop|
        oa_system = air_loop.airLoopHVACOutdoorAirSystem
        next if oa_system.empty?

        mech = oa_system.get.getControllerOutdoorAir.controllerMechanicalVentilation
        if enabled.empty?
          audit.info(:rules, 'no demand-controlled ventilation on the proposed systems serving these thermal ' \
                             'blocks — none modeled in the reference',
                     target: air_loop.nameString,
                     inputs: { proposed_loops: sources.map { |s| s[:air_loop] }.uniq },
                     article: article, ruling: 'D-54')
          next
        end

        mech.setDemandControlledVentilation(true)
        methods = enabled.filter_map { |s| s[:method] }.uniq
        copied = methods & DCV_METHODS
        mech.setSystemOutdoorAirMethod(copied.first) if copied.size == 1
        audit.decision(:rules, 'proposed demand-controlled ventilation strategy copied to the reference system',
                       target: air_loop.nameString,
                       inputs: { proposed_loops: enabled.map { |s| s[:air_loop] }.uniq,
                                 proposed_system_outdoor_air_method: methods,
                                 blocks_with_dcv: "#{enabled.size} of #{sources.size}" },
                       value: "demand-controlled ventilation on, system outdoor air method " \
                              "#{mech.systemOutdoorAirMethod}",
                       article: article, ruling: 'D-54')
        audit_dcv_caveats(air_loop, mech, sources, enabled, copied, article, audit)
      end
    end

    # Everything about the copy that a reader must not have to infer: a partly-DCV
    # merged system, an ambiguous set of demand-control methods, and a CO2-based
    # strategy whose contaminant balance did not survive into the reference.
    def self.audit_dcv_caveats(air_loop, mech, sources, enabled, copied, article, audit)
      if enabled.size < sources.size
        audit.warn(:rules, "only #{enabled.size} of #{sources.size} proposed thermal blocks served by this " \
                           'reference system carry demand-controlled ventilation — the reference system is a ' \
                           'single controller, so the strategy is applied to ALL of its blocks',
                   target: air_loop.nameString, article: article, ruling: 'D-54')
      end
      if copied.size > 1
        audit.warn(:rules, "the proposed thermal blocks use DIFFERENT demand-control methods (#{copied.join(', ')}) " \
                           "— the reference keeps #{mech.systemOutdoorAirMethod} and the other strategies are NOT reproduced",
                   target: air_loop.nameString, article: article, ruling: 'D-54')
      end
      return unless mech.systemOutdoorAirMethod.start_with?('IndoorAirQualityProcedure')

      # getZoneAirContaminantBalance CREATES the unique object when absent — probe
      # the optional accessor so a diagnostic never mutates the reference model.
      balance = mech.model.getOptionalZoneAirContaminantBalance
      return if balance.is_initialized && balance.get.carbonDioxideConcentration

      audit.warn(:rules, 'CO2-based demand-controlled ventilation copied, but the reference model has NO carbon ' \
                         'dioxide concentration balance — the strategy will NOT operate in EnergyPlus',
                 target: air_loop.nameString, article: article, ruling: 'D-54')
    end

    # ==================== 8.4.4.18: reference fan specifications ====================
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

    # ==================== 8.4.4.13.(2)(d): heat-pump heating cutoff ====================
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

    # Unwrap an SDK optional numeric (flow, capacity, ...) to a value or nil.
    # @param value [OpenStudio::OptionalDouble, Numeric, nil] SDK optional or plain numeric
    # @return [Numeric, nil] the contained value, or nil when uninitialized
    def self.optional_flow(value)
      return value unless value.respond_to?(:is_initialized)

      value.is_initialized ? value.get : nil
    end

    # ==================== 8.4.4.8: oversizing caps + D-52 (2)(b) ====================
    # The builders' GENERIC per-zone sizing factors. These sentinels MUST match
    # the zone_heating/zone_cooling_sizing_factor values the sizing blocks in
    # data/sizing.json stamp on generic systems (1.3/1.1) and on the HP builds
    # (cooling 1.0, required "without oversizing" by 8.4.4.13.(2)(b)) — if
    # sizing.json changes, change these WITH it, or the 8.4.4.8 cap below
    # silently stops clearing the zone stamps (zone factors override the
    # global Sizing:Parameters).
    GENERIC_ZONE_HEATING_FACTOR = 1.3
    GENERIC_ZONE_COOLING_FACTOR = 1.1
    HP_ZONE_COOLING_FACTOR = 1.0

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
      hp_pinned = 0
      reference.getSizingZones.each do |sz|
        if (sz.zoneHeatingSizingFactor.get - GENERIC_ZONE_HEATING_FACTOR).abs < 1e-9
          sz.resetZoneHeatingSizingFactor
          cleared += 1
        end
        if (sz.zoneCoolingSizingFactor.get - GENERIC_ZONE_COOLING_FACTOR).abs < 1e-9
          sz.resetZoneCoolingSizingFactor
          cleared += 1
        elsif (sz.zoneCoolingSizingFactor.get - HP_ZONE_COOLING_FACTOR).abs < 1e-9
          hp_pinned += 1 # the HP builders' deliberate 1.0 — preserved
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
      return if hp_pinned.zero?

      # 8.4.4.13.(2)(b): "the heat pump's cooling capacity shall be set based on
      # the peak cooling load, without oversizing". The HP builders stamp a
      # Sizing:Zone cooling factor of 1.0, which OVERRIDES (does not multiply
      # with) the capped global above — measured on the sized DX coil: identical
      # capacity with the global at 1.10 vs 1.00 (A/B ratio 1.0000), while
      # clearing the zone factor grew it 4.15%, proving the probe's sensitivity.
      audit.decision(:rules, 'heat pump cooling sized at the peak cooling load, without oversizing',
                     inputs: { zones_pinned: hp_pinned, global_cooling_factor: cool_ref },
                     value: 'per-zone cooling sizing factor 1.0 overrides the global factor (measured: sized DX ' \
                            'capacity identical with the global at 1.10 vs 1.00)',
                     article: '8.4.4.13.(2)(b)', ruling: 'D-52')
    end

    # ==================== 8.4.4.13.(2)(g): the HP auxiliary-fuel election (D-52) ====================
    # 8.4.4.13.(2)(g)/(h) — the reference heat pump's terminal/auxiliary heating
    # energy type (D-52). The election is ANNUAL-ENERGY-based: among the energy
    # types used for terminal or auxiliary heating of the thermal blocks the
    # heat pump serves, elect the one with the largest annual energy use —
    # PROVIDED the heat pump exceeds the vendored threshold (33%) of the total
    # annual space-heating energy use for those blocks. (g)(i) scopes an
    # air-source HP to its own blocks; (g)(ii) scopes a water-/ground-source HP
    # to the blocks of ALL heat pumps connected to the same water loop. All
    # quantities are DELIVERED heat (one consistent basis across fuels).
    #
    # Returns nil — falling back to the structural 8.4.4.9.(4) proxy, audited —
    # when there is no annual data (simulate: :sizing/:none), when the blocks
    # have no terminal/aux heating at all, or when the 33% proviso fails (the
    # sentence then simply does not elect).
    #
    # (h) forces electricity when the HP is not air-, water- or ground-source.
    # Our taxonomy classifies every detected HP as :air, :water_loop or
    # :external (water/ground), so (h) is only ever AFFIRMATIVELY established
    # for a source-less detection — which keeps the proxy instead, with the
    # inapplicability recorded, rather than guessing.
    # @param group [Hash] one Classify.characterize group (the heat-pump system)
    # @param facts [Hash] the full Classify.characterize output
    # @param hp_rules [Hash, nil] the ruleset's heat-pump rules block (threshold source)
    # @param annual [Hash, nil] proposed-annual delivered-heat data
    #   ({loops: {name => {hp_j:, aux: [{fuel:, j:}]}}, zones: {name => [{role:, fuel:, j:}]}})
    # @param audit [AuditLog, nil]
    # @return [String, nil] elected reference energy-type variant (e.g. 'gas',
    #   'electric'), or nil when sentence (g) does not elect (proxy applies)
    def self.heat_pump_aux_energy_type(group, facts, hp_rules, annual, audit)
      threshold = (hp_rules || {})['aux_energy_type_threshold_fraction'] || 0.33
      if annual.nil?
        audit&.info(:selection,
                    'no proposed annual data (simulate: :sizing/:none, or the annual run predates this ' \
                    'feature) — the 8.4.4.13.(2)(g) auxiliary-fuel election cannot run; the structural ' \
                    '8.4.4.9.(4) proxy elects the fuel instead',
                    target: group[:zones].join(','), article: '8.4.4.13.(2)(g)', ruling: 'D-52')
        return nil
      end

      scope_loops, scope_zones, sentence = election_scope(group, facts)
      hp_j = 0.0
      aux_by_fuel = Hash.new(0.0)
      scope_loops.each do |loop_name|
        entry = (annual[:loops] || {})[loop_name] || {}
        hp_j += entry[:hp_j].to_f
        Array(entry[:aux]).each { |a| aux_by_fuel[a[:fuel]] += a[:j].to_f }
      end
      scope_zones.each do |zone_name|
        Array((annual[:zones] || {})[zone_name]).each do |e|
          e[:role] == :hp ? hp_j += e[:j].to_f : aux_by_fuel[e[:fuel]] += e[:j].to_f
        end
      end

      total_j = hp_j + aux_by_fuel.values.sum
      if aux_by_fuel.empty? || total_j <= 0.0
        audit&.info(:selection,
                    'the proposed thermal blocks have no terminal or auxiliary heating energy in the annual ' \
                    'run — 8.4.4.13.(2)(g) has nothing to elect; the structural 8.4.4.9.(4) proxy elects the fuel',
                    target: group[:zones].join(','),
                    inputs: { hp_gj: (hp_j / 1e9).round(2) }, article: '8.4.4.13.(2)(g)', ruling: 'D-52')
        return nil
      end

      share = hp_j / total_j
      if share <= threshold
        audit&.decision(:selection,
                        "the heat pump carries #{(share * 100).round(1)}% of the blocks' annual space-heating " \
                        "energy — NOT above the #{(threshold * 100).round}% proviso, so sentence (g) does not " \
                        'elect; the structural 8.4.4.9.(4) proxy elects the fuel',
                        target: group[:zones].join(','),
                        inputs: { hp_gj: (hp_j / 1e9).round(2), total_gj: (total_j / 1e9).round(2),
                                  share: share.round(3), threshold: threshold, sentence: sentence },
                        article: "8.4.4.13.(2)#{sentence}", ruling: 'D-52')
        return nil
      end

      elected_fuel, elected_j = aux_by_fuel.max_by { |_fuel, j| j }
      variant = energy_type_variant(elected_fuel)
      if variant.nil?
        audit&.warn(:selection,
                    "the largest terminal/aux energy type is '#{elected_fuel}', which maps to NO reference " \
                    'system variant — the structural 8.4.4.9.(4) proxy elects the fuel instead',
                    target: group[:zones].join(','),
                    inputs: { by_fuel_gj: aux_by_fuel.transform_values { |j| (j / 1e9).round(2) } },
                    article: "8.4.4.13.(2)#{sentence}", ruling: 'D-52')
        return nil
      end
      audit&.decision(:selection,
                      'auxiliary heating energy type ELECTED from the proposed annual run: the terminal/aux ' \
                      "energy type with the largest annual energy use is #{elected_fuel} " \
                      "(#{(elected_j / 1e9).round(2)} GJ delivered), and the heat pump's " \
                      "#{(share * 100).round(1)}% share exceeds the #{(threshold * 100).round}% proviso " \
                      '((h) inapplicable: the source is classified air/water/ground)',
                      target: group[:zones].join(','),
                      inputs: { by_fuel_gj: aux_by_fuel.transform_values { |j| (j / 1e9).round(2) },
                                hp_gj: (hp_j / 1e9).round(2), share: share.round(3),
                                sentence: sentence, scope_loops: scope_loops, scope_zone_count: scope_zones.size },
                      value: variant, article: "8.4.4.13.(2)#{sentence}", ruling: 'D-52')
      variant
    end

    # (g)(i) vs (g)(ii): an :external-source (water/ground) heat pump elects over
    # the thermal blocks of ALL heat pumps connected to the same source water
    # loop, so sibling zone groups sharing a source loop are pulled in.
    def self.election_scope(group, facts)
      loops = [group[:air_loop]].compact
      zones = group[:zones].dup
      if (group[:heat_pump_sources] || []).include?(:external) && group[:heat_pump_source_loops]&.any?
        (facts[:zone_groups] || []).each do |other|
          next if other.equal?(group)
          next unless (Array(other[:heat_pump_source_loops]) & group[:heat_pump_source_loops]).any?

          loops |= [other[:air_loop]].compact
          zones |= other[:zones]
        end
        [loops, zones, '(g)(ii)']
      else
        [loops, zones, '(g)(i)']
      end
    end

    # Map an elected proposed energy type onto the reference system-definition
    # variant. Purchased heating is represented by a gas-fired boiler
    # (8.4.4.6.(1)); an unknown type cannot elect (nil -> structural proxy).
    def self.energy_type_variant(fuel)
      return 'gas' if fuel =~ /gas|oil|propane|purchased/i
      return 'electric' if fuel =~ /electric/i

      nil
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

    # ---- internals (not API) ----
    private_class_method :category_for, :audit_museum_row, :assign, :condition_met?,
                         :residential_assignment, :heat_pump_redirects?,
                         :residential_compatible_cooling?, :finalize,
                         :audit_terminal_secondary_split, :apply_zone_fan_rules,
                         :purge_orphaned_ems, :apply_unitary_operating_schedule,
                         :apply_operating_schedules, :emit_article_coverage,
                         :clone_model, :building_info, :apply_economizers,
                         :apply_water_economizer, :chilled_water_loops,
                         :condenser_loop_for, :build_water_economizer,
                         :reset_condenser_setpoint, :humidifier_kind,
                         :air_loop_humidifier, :capture_humidification,
                         :humidifier_energy_source, :scheduled_humidity_setpoint,
                         :rebuild_humidification, :build_reference_humidifier,
                         :elect_humidifier_kind, :attach_humidity_control,
                         :apply_dcv, :audit_dcv_caveats, :apply_fan_rules,
                         :set_fan_total_efficiency, :apply_heat_pump_limits,
                         :apply_oversizing_caps,
                         :election_scope, :energy_type_variant, :reference_energy_type
  end
end
