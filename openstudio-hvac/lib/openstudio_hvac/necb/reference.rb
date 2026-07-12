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
