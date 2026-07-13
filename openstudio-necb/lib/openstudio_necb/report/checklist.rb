require 'set'

module OpenStudioNECB
  module Report
    # Derives the AHJ-style checklist from the audit log. Rows come from
    # :compliance decisions (the article-cited verdicts), and every warning is
    # elevated so the checklist can never look cleaner than the run actually
    # was. Coverage entries are reconciled: a host_scope delegation with no
    # implementing coverage entry in the same audit surfaces as a warning row;
    # everything else stays in the coverage appendix.
    module Checklist
      Row = Struct.new(:glyph, :article, :statement, :measured, :audit_index, :building, keyword_init: true)

      # The audit convention SHOUTS violations ('EXCEEDS', 'does NOT meet',
      # 'BELOW the') while pass texts stay lowercase ('does not exceed',
      # 'within 100 h') — so the fail check is deliberately case-SENSITIVE.
      FAIL_WORDS = /\b(EXCEEDS?|NOT|BELOW|FAILS?)\b|non-compliant/.freeze
      PASS_WORDS = /\b(meets|complies|compliant|does not exceed|within|satisfied)\b/i.freeze

      # Coverage statuses that count as an article being actually handled in
      # this run (so a sibling host_scope delegation is reconciled, not warned).
      COVERING_STATUSES = %w[implemented partial satisfied_by_clone].freeze

      module_function

      # @param audit_entries [Array<Hash>] AuditLog#entries (symbol keys)
      # @return [Array<Row>] article-sorted checklist rows
      def rows(audit_entries)
        covered = covered_articles(audit_entries)
        out = []
        audit_entries.each_with_index do |entry, index|
          step = entry[:step].to_s
          inputs = entry[:inputs]
          status = inputs.is_a?(Hash) ? inputs[:status].to_s : ''
          if %i[warn warning].include?(entry[:level])
            out << Row.new(glyph: :warning, article: entry[:article].to_s, building: entry[:building],
                           statement: statement_for(entry), measured: measured_for(entry), audit_index: index)
          elsif step == 'compliance' && entry[:level] == :decision
            out << Row.new(glyph: verdict_glyph(entry[:action].to_s), article: entry[:article].to_s,
                           building: entry[:building],
                           statement: statement_for(entry), measured: measured_for(entry), audit_index: index)
          elsif step == 'coverage' && entry[:level] == :info && status == 'host_scope' &&
                !covered?(entry[:article].to_s, covered)
            out << Row.new(glyph: :warning, article: entry[:article].to_s, building: entry[:building],
                           statement: "Delegated but NOT covered in this run: #{entry[:action]}",
                           measured: nil, audit_index: index)
          end
        end
        out.sort_by { |r| [article_sort_key(r.article), r.audit_index] }
      end

      # Articles an implementing coverage entry claims in THIS audit. Shared by
      # the checklist reconciliation and the coverage appendix so both agree.
      def covered_articles(audit_entries)
        covered = Set.new
        audit_entries.each do |entry|
          next unless entry[:step].to_s == 'coverage'

          inputs = entry[:inputs]
          next unless inputs.is_a?(Hash) && COVERING_STATUSES.include?(inputs[:status].to_s)

          article = entry[:article].to_s
          covered << article unless article.empty?
        end
        covered
      end

      # Bidirectional prefix match (subsumes exact equality): '8.4.4.20.' covers
      # '8.4.4.20.(1)' and vice versa. NECB article strings end in '.', so the
      # trailing dot guards against '8.4.4.2.' matching '8.4.4.20.'.
      def covered?(article, covered_set)
        a = article.to_s
        return false if a.empty?

        covered_set.any? { |b| a.start_with?(b) || b.start_with?(a) }
      end

      def verdict_glyph(action)
        return :fail if action =~ FAIL_WORDS
        return :pass if action =~ PASS_WORDS

        :na
      end

      def statement_for(entry)
        text = entry[:action].to_s
        target = entry[:target]
        target && !text.include?(target.to_s) ? "#{target}: #{text}" : text
      end

      # Compact "measured" cell from the decision's inputs hash.
      def measured_for(entry)
        inputs = entry[:inputs]
        return nil unless inputs.is_a?(Hash) && !inputs.empty?

        inputs.first(4).map do |k, v|
          value = v.is_a?(Float) ? v.round(2) : v
          "#{k}: #{value}"
        end.join(', ')
      end

      # Sort "8.4.1.2.(2)" numerically per level; unknown articles sink last.
      def article_sort_key(article)
        numbers = article.to_s.scan(/\d+/).map(&:to_i)
        numbers.empty? ? [99] : numbers
      end
    end
  end
end
