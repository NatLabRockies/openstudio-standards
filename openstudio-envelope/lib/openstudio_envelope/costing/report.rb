module OpenStudioEnvelope
  module Costing
    Report = Struct.new(:total, :envelope, :thermal_bridging, :warnings, :city,
                        :province_state, :audit, keyword_init: true)

    module_function

    # Cost a model's envelope (and optionally its thermal-bridge edges).
    #
    # @param model [OpenStudio::Model::Model]
    # @param city [String, nil] cost location; nil => nearest city to the model's site
    # @param province_state [String, nil]
    # @param structure [Hash, nil] { framing: :steel|:wood|:cmu, cladding:, finish: } —
    #   drives the costed wall assembly (default: steel-framed)
    # @param performance [Symbol] :lp or :hp assembly tier
    # @param tbd_result [Hash, nil] a TBD.process result — edges are tallied and
    #   costed, and the parapet allowance is applied
    # @param tb_tallies [Hash, nil] pre-built { edge_type => { wall_ref => m } }
    #   tallies (legacy shape); takes precedence over tbd_result
    # @param tb_quality [Symbol] :good or :bad detail tier for the wall reference
    # @param costs_csv [String, nil] runtime-injected priced cost table
    # @param local_factors_csv [String, nil] runtime-injected localization table
    # @param audit [AuditLog, nil] shared audit (compliance + costing in ONE log)
    # @return [Report]
    def cost(model, city: nil, province_state: nil, structure: nil, performance: :lp,
             tbd_result: nil, tb_tallies: nil, tb_quality: :good,
             costs_csv: nil, local_factors_csv: nil, audit: nil)
      audit ||= AuditLog.new
      database = Database.new(costs_csv: costs_csv, local_factors_csv: local_factors_csv)

      if city.nil? || province_state.nil?
        site = model.getSite
        location = database.closest_location(site.latitude, site.longitude)
        city ||= location['city']
        province_state ||= location['province_state']
        audit.info(:costing_envelope, 'cost location resolved from the model site',
                   value: "#{city}, #{province_state}")
      end

      tb_section = nil
      tallies = tb_tallies
      if tallies.nil? && tbd_result
        wall_reference = "#{Assemblies.costed_assembly(structure, :walls, performance)} #{tb_quality}"
        tallies = ThermalBridgingCosts.tallies_from_tbd(tbd_result, wall_reference)
      end

      envelope = EnvelopeCosts.cost(model, database: database, province_state: province_state,
                                    city: city, structure: structure, performance: performance,
                                    tb_tallies: tallies, audit: audit)
      tb_section = ThermalBridgingCosts.cost(tallies, database: database, audit: audit) if tallies

      database.warnings.each { |w| audit.warn(:costing_envelope, w) }
      total = envelope['total_envelope_cost'] + (tb_section ? tb_section['total_thermal_bridging_cost'] : 0.0)
      audit.decision(:costing_envelope, 'envelope costing complete',
                     inputs: { envelope: envelope['total_envelope_cost'],
                               thermal_bridging: tb_section ? tb_section['total_thermal_bridging_cost'] : 'not requested' },
                     value: "$#{total.round(2)}")

      Report.new(total: total.round(2), envelope: envelope, thermal_bridging: tb_section,
                 warnings: audit.warnings.map { |w| w[:action] }, city: city,
                 province_state: province_state, audit: audit)
    end
  end
end
