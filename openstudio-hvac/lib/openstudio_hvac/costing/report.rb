module OpenStudioHVAC
  module Costing
    Report = Struct.new(:total, :by_category, :items, :warnings, :city, :province_state, keyword_init: true)

    # The costing facade. Requires a SIZED model (capacities/flows are read from the
    # objects' hard or autosized values).
    #
    # @param model [OpenStudio::Model::Model]
    # @param systems [Array<Builder::Result>, nil] gem build results — used to map each
    #   air loop to its family for AHU/distribution costing. nil => plant/zonal only for
    #   foreign loops (with warnings).
    # @param city [String, nil] cost location; nil => nearest city to the model's weather site
    # @param province_state [String, nil]
    # @param costs_csv [String, nil] inject licensed cost values (see data/costing/README.md)
    # @return [Report]
    def self.cost(model, systems: nil, city: nil, province_state: nil, costs_csv: nil)
      database = Database.new(costs_csv: costs_csv)
      ledger = Ledger.new

      if city.nil? || province_state.nil?
        site = model.getSite
        location = database.closest_location(site.latitude, site.longitude)
        city ||= location['city']
        province_state ||= location['province_state']
      end

      equipment = EquipmentQuantifier.new(database, ledger)
      equipment.quantify_plant(model)
      equipment.quantify_zonal(model)

      loop_families = {}
      Array(systems).each do |result|
        family = result.respond_to?(:system_name) ? Catalog.resolve(result.system_name)['family'] : nil
        Array(result.respond_to?(:air_loops) ? result.air_loops : nil).each do |air_loop|
          loop_families[air_loop.nameString] = family
        end
      end
      ventilation = VentilationQuantifier.new(database, ledger)
      ventilation.quantify(model, loop_families)

      priced = ledger.price(database, province_state: province_state, city: city)
      Report.new(total: priced['total'],
                 by_category: priced['by_category'],
                 items: priced['items'],
                 warnings: (database.warnings + equipment.warnings + ventilation.warnings).uniq,
                 city: city, province_state: province_state)
    end
  end
end
