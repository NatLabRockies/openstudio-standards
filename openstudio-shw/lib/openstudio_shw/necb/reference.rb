module OpenStudioSHW
  module NECB
    # Reference-building SWH — NECB 2020 8.4.4.20 (2025: 8.4.5.20):
    #   (1) storage capacity, power input and energy type identical to proposed —
    #       satisfied by construction in the umbrella (the reference is a clone
    #       and no transform touches SWH plant sizing or fuel)
    #   (2) HP-source SWH -> air-source HP: vacuous until HP SWH is modeled
    #   (3)-(4) not machine-retrievable (extraction gap) — treated as Part 6
    #       minimums by re-applying the Table 6.2.2.1 performance on the
    #       reference's (identical) heaters.
    module Reference
      module_function

      def reference_shw(model, vintage: '2020', audit: nil)
        audit ||= AuditLog.new
        prefix = vintage.to_s == '2025' ? '8.4.5' : '8.4.4'
        heaters = model.getWaterHeaterMixeds.sort_by(&:nameString)
        audit.info(:shw_reference,
                   'reference SWH storage capacity, power input and energy type identical to proposed ' \
                   'by construction (clone; no transform touches SWH sizing or fuel)',
                   inputs: { water_heaters: heaters.size }, article: "#{prefix}.20.(1)")
        heaters.each { |heater| Efficiency.apply_efficiency(heater, vintage: vintage, audit: audit) }
        # Table 6.2.2.1 solar-thermal + pool-heater rows (D-63): apply-when-present.
        Efficiency.apply_solar_pool_minimums(model, vintage: vintage, audit: audit)
        emit_article_coverage(vintage, audit)
        audit
      end

      def emit_article_coverage(vintage, audit)
        coverage = NECB.rules(vintage)['article_coverage']
        return if coverage.nil?

        cited = Hash.new(0)
        audit.entries.each { |e| e[:article].to_s.scan(/\d+\.\d+(?:\.\d+)*\./) { |a| cited[a] += 1 } }
        coverage['articles'].each do |article|
          applied = cited.select { |a, _| a.start_with?(article['article'].to_s.sub(/\.\z/, '').sub(/\(\d+\).*/, '')) }.values.sum
          inputs = { status: article['status'], decisions_citing: applied }
          inputs[:gap_owner] = article['gap_owner'] if article['gap_owner']
          if %w[implemented satisfied_by_clone host_scope].include?(article['status'])
            audit.info(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}#{article['how'] ? ": #{article['how']}" : ''}",
                       inputs: inputs, article: article['article'])
          elsif article['gap_owner'] == 'modeller' # scope note, not a warning (D-09)
            audit.info(:coverage, "#{article['title']} — #{article['status'].tr('_', ' ')}, modeller scope" \
                                  "#{article['how'] ? ". Applied: #{article['how']}" : ''}" \
                                  "#{article['gaps'] ? ". Modeller's responsibility: #{article['gaps']}" : ''}",
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

    def self.reference_shw(model, **kwargs)
      Reference.reference_shw(model, **kwargs)
    end
  end
end
