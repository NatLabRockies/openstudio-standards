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

    # 'air-cooled unitary, packaged terminal or room air conditioner (or heat pumps), or fan coils'
    def self.residential_compatible_cooling?(group)
      return true if group[:heat_pump]
      return true if %i[zonal_heat_cool packaged_single_zone].include?(group[:family_guess])

      %w[psz mau_ptac zone_terminal fan_coils wshp vrf].include?(group[:family])
    end

    # ---- finalize: heat-pump override, energy type, catalog name ----

    def self.finalize(assignment, group, definitions, selection, facts, audit)
      return assignment if assignment.action == :copy_proposed

      hp_rule = selection['special_rules']['heat_pump']
      if group[:heat_pump] && hp_rule['applies_to_systems'].include?(assignment.reference_system)
        audit&.decision(:selection, 'proposed heat pump -> reference is an air-source heat pump (Table 8.4.4.13)',
                        target: group[:zones].join(','),
                        inputs: { selected_system: assignment.reference_system },
                        value: 'hp', article: hp_rule['article'])
        assignment.reference_system = 'hp'
        assignment.articles << hp_rule['article']
      end

      assignment.energy_type = reference_energy_type(group, selection, facts, audit)
      definition = definitions.fetch(assignment.reference_system.to_s)
      variant = definition.fetch(assignment.energy_type)
      assignment.catalog_name = variant.fetch('name')
      assignment.config = variant['config']

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
        apply_heat_pump_limits(result.air_loops, ruleset, audit) if assignment.reference_system == 'hp'
      end

      apply_oversizing_caps(model, reference, ruleset, audit)
      Efficiency.apply(reference, vintage: vintage, audit: audit)

      ReferenceResult.new(model: reference, assignments: assignments, audit: audit)
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

    # 8.4.4.18.(3): systems 1/3/4/5 -> supply fan 640 Pa @ 40% combined efficiency, no
    # return fan. 8.4.4.18.(4): system 6 -> supply 1000 Pa @ 55%, return 250 Pa @ 30%.
    def self.apply_fan_rules(air_loops, reference_system, ruleset, audit)
      fans = ruleset.fetch('fans')
      spec = reference_system == 6 ? fans['system_6'] : fans['systems_1_3_4_5']
      Array(air_loops).each do |air_loop|
        air_loop.supplyComponents.each do |comp|
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
        air_loop.supplyComponents.each do |comp|
          next unless comp.to_CoilHeatingDXSingleSpeed.is_initialized

          coil = comp.to_CoilHeatingDXSingleSpeed.get
          coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(cutoff)
          audit.decision(:rules, 'heat pump heating cutoff set', target: coil.nameString,
                         value: "compressor off below #{cutoff} degC",
                         article: ruleset.fetch('heat_pump_reference')['article'])
        end
      end
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
      audit.decision(:rules, 'equipment oversizing capped',
                     inputs: { proposed_heating: heat_prop, proposed_cooling: cool_prop },
                     value: "heating sizing factor #{heat_ref.round(3)} = min(proposed #{heat_prop.round(3)}, cap #{(1.0 + caps['heating_max_fraction']).round(2)}); " \
                            "cooling #{cool_ref.round(3)} = min(proposed #{cool_prop.round(3)}, cap #{(1.0 + caps['cooling_max_fraction']).round(2)})",
                     article: caps['article'])
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
