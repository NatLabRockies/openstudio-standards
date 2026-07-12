module OpenStudioNECB
  module Report
    # Derives the AHJ-style checklist from the audit log. Rows come from
    # :compliance decisions (the article-cited verdicts), :coverage entries
    # become scope notes, and every warning is elevated so the checklist can
    # never look cleaner than the run actually was.
    module Checklist
      Row = Struct.new(:glyph, :article, :statement, :measured, :audit_index, keyword_init: true)

      # The audit convention SHOUTS violations ('EXCEEDS', 'does NOT meet',
      # 'BELOW the') while pass texts stay lowercase ('does not exceed',
      # 'within 100 h') — so the fail check is deliberately case-SENSITIVE.
      FAIL_WORDS = /\b(EXCEEDS?|NOT|BELOW|FAILS?)\b|non-compliant/.freeze
      PASS_WORDS = /\b(meets|complies|compliant|does not exceed|within|satisfied)\b/i.freeze

      module_function

      # @param audit_entries [Array<Hash>] AuditLog#entries (symbol keys)
      # @return [Array<Row>] article-sorted checklist rows
      def rows(audit_entries)
        out = []
        audit_entries.each_with_index do |entry, index|
          step = entry[:step].to_s
          if %i[warn warning].include?(entry[:level])
            out << Row.new(glyph: :warning, article: entry[:article].to_s,
                           statement: statement_for(entry), measured: measured_for(entry), audit_index: index)
          elsif step == 'compliance' && entry[:level] == :decision
            out << Row.new(glyph: verdict_glyph(entry[:action].to_s), article: entry[:article].to_s,
                           statement: statement_for(entry), measured: measured_for(entry), audit_index: index)
          elsif step == 'coverage' && entry[:level] == :decision
            out << Row.new(glyph: :info, article: entry[:article].to_s,
                           statement: statement_for(entry), measured: nil, audit_index: index)
          end
        end
        out.sort_by { |r| [article_sort_key(r.article), r.audit_index] }
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
