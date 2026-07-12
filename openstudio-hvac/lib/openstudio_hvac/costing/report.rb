module OpenStudioHVAC
  module Costing
    Report = Struct.new(:total, :by_category, :items, :warnings, :city, :province_state, :audit, keyword_init: true)

    # The costing facade. Requires a SIZED model (capacities/flows are read from the
    # objects' hard or autosized values).
    #
    # @param model [OpenStudio::Model::Model]
    # @param systems [Array<Builder::Result>, nil] gem build results — the highest-
    #   fidelity mapping of air loops to families for AHU/distribution costing.
    #   OPTIONAL: any loop not covered (or any general OSM with systems: omitted) is
    #   classified automatically — exactly when its name is recognizable (gem catalog /
    #   legacy sys_N pipe names), structurally otherwise (guess reported as a warning).
    # @param city [String, nil] cost location; nil => nearest city to the model's weather site
    # @param province_state [String, nil]
    # @param costs_csv [String, nil] inject licensed cost values (see data/costing/README.md)
    # @param mech_room_name [String, nil] pin the mechanical-room space by name for the
    #   geometry-derived items (utility runs, flues, header piping); nil => legacy
    #   election (Electrical/Mechanical space type, else lowest storey closest to centre)
    # @return [Report]
    def self.cost(model, systems: nil, city: nil, province_state: nil, costs_csv: nil,
                  mech_room_name: nil, audit: nil)
      audit ||= AuditLog.new
      database = Database.new(costs_csv: costs_csv)
      ledger = Ledger.new

      if city.nil? || province_state.nil?
        site = model.getSite
        location = database.closest_location(site.latitude, site.longitude)
        city ||= location['city']
        province_state ||= location['province_state']
        audit.decision(:costing, 'cost location resolved from site coordinates',
                       inputs: { latitude: site.latitude.round(3), longitude: site.longitude.round(3) },
                       value: "#{city}, #{province_state}")
      end

      equipment = EquipmentQuantifier.new(database, ledger, mech_room_name: mech_room_name, audit: audit)
      equipment.quantify_plant(model)
      equipment.quantify_zonal(model)

      loop_families = {}
      Array(systems).each do |result|
        family = result.respond_to?(:system_name) ? Catalog.resolve(result.system_name)['family'] : nil
        Array(result.respond_to?(:air_loops) ? result.air_loops : nil).each do |air_loop|
          loop_families[air_loop.nameString] = family
          audit.decision(:costing_classification, 'air loop family from build result',
                         target: air_loop.nameString, value: family)
        end
      end
      classifier_warnings = classify_unmapped_loops(model, loop_families, audit)

      ventilation = VentilationQuantifier.new(database, ledger, audit: audit)
      ventilation.quantify(model, loop_families, mech_room_name: mech_room_name)

      priced = ledger.price(database, province_state: province_state, city: city)
      warnings = (database.warnings + equipment.warnings +
                  classifier_warnings + ventilation.warnings).uniq
      warnings.each { |w| audit.warn(:costing, w) }
      audit.info(:costing, 'costing complete',
                 inputs: { items: priced['items'].size, city: city },
                 value: priced['by_category'].map { |k, v| "#{k}=#{v.round(0)}" }.join(', '))
      Report.new(total: priced['total'],
                 by_category: priced['by_category'],
                 items: priced['items'],
                 warnings: warnings,
                 city: city, province_state: province_state, audit: audit)
    end

    # Structural-guess -> costing family (AHU assembly class). Exact recognition
    # (gem catalog names, legacy sys_N pipe names) already yields a real family.
    STRUCTURAL_FAMILY = {
      multizone_vav: 'vav_reheat',       # central VAV -> sys6 assembly class
      multizone_cv: 'psz',               # central CV w/ reheat -> packaged class
      packaged_single_zone: 'psz',       # single-zone packaged -> sys3/4 class
      central_doas_or_cv: 'doas'         # multi-zone CV ventilation -> sys1 class
    }.freeze

    # Costing works on ANY OSM: air loops not covered by build results are classified
    # (exactly by recognized names, else structurally) so their AHU/distribution can be
    # costed. Guessed families are reported as warnings — approximations are never
    # silent. Loops the classifier cannot place remain uncosted with the standard
    # foreign-loop warning from the ventilation quantifier.
    def self.classify_unmapped_loops(model, loop_families, audit = nil)
      unmapped = model.getAirLoopHVACs.reject { |al| loop_families.key?(al.nameString) }
      return [] if unmapped.empty?

      warnings = []
      facts = Classify.characterize(model)
      facts[:zone_groups].each do |group|
        name = group[:air_loop]
        next if name.nil? || loop_families.key?(name)

        if group[:family]
          loop_families[name] = group[:family]
          audit&.decision(:costing_classification, 'air loop family recognized from catalog name',
                          target: name, value: group[:family],
                          evidence: group[:evidence].grep(/catalog/).first)
        elsif group[:family_guess].is_a?(String)
          # exact mapping (legacy sys_N pipe names) — a real family, not a guess
          loop_families[name] = group[:family_guess]
          audit&.decision(:costing_classification, 'air loop family mapped from legacy NECB pipe name',
                          target: name, value: group[:family_guess])
        elsif (family = STRUCTURAL_FAMILY[group[:family_guess]])
          loop_families[name] = family
          audit&.decision(:costing_classification, 'air loop family guessed structurally (approximation)',
                          target: name, inputs: { structural_guess: group[:family_guess] }, value: family,
                          evidence: group[:evidence].last(2).join('; '))
          warnings << "air loop '#{name}': family '#{family}' guessed structurally " \
                      "(#{group[:family_guess]}) — AHU assembly class is an approximation"
        end
      end
      warnings
    end
  end
end
