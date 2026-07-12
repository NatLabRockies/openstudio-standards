module OpenStudioLighting
  module Costing
    Report = Struct.new(:total, :lighting, :warnings, :city, :province_state, :audit, keyword_init: true)

    module_function

    # Cost a model's lighting fixtures. Same location/injection contract as the
    # sibling gems' costing facades.
    def cost(model, vintage: '2020', city: nil, province_state: nil,
             costs_csv: nil, local_factors_csv: nil, audit: nil)
      audit ||= AuditLog.new
      database = Database.new(costs_csv: costs_csv, local_factors_csv: local_factors_csv)

      if city.nil? || province_state.nil?
        site = model.getSite
        location = database.closest_location(site.latitude, site.longitude)
        raise(ArgumentError, 'pass city:/province_state: — locations.csv unavailable') if location.nil?

        city ||= location['city']
        province_state ||= location['province_state']
        audit.info(:costing_lighting, 'cost location resolved from the model site',
                   value: "#{city}, #{province_state}")
      end

      section = Fixtures.cost(model, database: database, vintage: vintage,
                              province_state: province_state, city: city, audit: audit)
      database.warnings.each { |w| audit.warn(:costing_lighting, w) }
      Report.new(total: section['total_lighting_cost'], lighting: section,
                 warnings: audit.warnings.map { |w| w[:action] },
                 city: city, province_state: province_state, audit: audit)
    end
  end
end
