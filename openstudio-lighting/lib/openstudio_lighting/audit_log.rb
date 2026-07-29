require 'json'

module OpenStudioLighting
  # The gem-wide decision/audit trail: proposed characterization, NECB reference
  # generation, efficiency application AND costing all write to the same log.
  #
  # Every consequential step records WHAT was decided, the INPUTS it was decided from,
  # the model EVIDENCE behind it, and (where applicable) the NECB ARTICLE or data-table
  # citation that mandates it — so QAQC can answer "why did zone X get System 6?" or
  # "why was this AHU costed at 0.648 of the 2500 L/s assembly?" from the log instead
  # of diffing models, and debugging failures reads as a narrative.
  #
  # Entry schema (all optional except step/action/level):
  #   { step:, target:, action:, inputs:, value:, article:, ruling:, evidence:, building:, level: }
  #   level: :decision | :info | :warning
  #
  # ruling: WHICH adjudicated project decision(s) govern this code path — the
  # D-XX ids of the NECB gem family's decision record (mirrored machine-readably
  # in openstudio-necb's decisions.json and surfaced in the AHJ report). Where
  # `article` cites the CODE that mandates a value, `ruling` cites OUR judgement
  # call about how that code was interpreted or implemented, so a reader sees
  # both what was done and why we did it that way. Multiple ids are a single
  # space-separated string ('D-19 D-21'); consumers scan /\bD-\d{2}\b/.
  #
  # building: WHICH model the entry is about ('input model', 'proposed building',
  # 'reference building') — stamped automatically from the current #building
  # context, which a pipeline sets at phase boundaries (one audit spans several
  # models; without the stamp a warning can't be traced to the model it belongs
  # to). nil = cross-building comparison or verdict.
  #
  # Contract: warnings are never silent — anything skipped/unknown lands here.
  class AuditLog
      attr_reader :entries
      attr_accessor :building

      def initialize
        @entries = []
        @building = nil
      end

      # Stamp every entry recorded inside the block with the given building
      # context; restores the previous context afterwards (nestable).
      def with_building(name)
        previous = @building
        @building = name
        yield
      ensure
        @building = previous
      end

      # @param step [Symbol] pipeline stage (:characterize, :selection, :build, :rules, :efficiency)
      # @param action [String] what happened, in words
      # @param target [String, nil] the model object / zone group it applies to
      # @param inputs [Hash, nil] the values the decision was made from
      # @param value [Object, nil] the resulting value/assignment
      # @param article [String, nil] NECB article/table citation (e.g. "8.4.4.8.(1)")
      # @param ruling [String, nil] adjudicated decision id(s) governing this path
      #   (e.g. "D-14", or "D-19 D-21" for several)
      # @param evidence [String, nil] the model objects that support the conclusion
      def decision(step, action, target: nil, inputs: nil, value: nil, article: nil, ruling: nil, evidence: nil)
        add(:decision, step, action, target, inputs, value, article, ruling, evidence)
      end

      def info(step, action, target: nil, inputs: nil, value: nil, article: nil, ruling: nil, evidence: nil)
        add(:info, step, action, target, inputs, value, article, ruling, evidence)
      end

      def warn(step, action, target: nil, inputs: nil, value: nil, article: nil, ruling: nil, evidence: nil)
        add(:warning, step, action, target, inputs, value, article, ruling, evidence)
      end

      # @return [Array<Hash>] warning entries only
      def warnings
        @entries.select { |e| e[:level] == :warning }
      end

      def to_json(*args)
        JSON.pretty_generate(@entries.map { |e| e.transform_keys(&:to_s) }, *args)
      end

      # Human-readable narrative, one line per entry.
      def to_s
        @entries.map do |e|
          line = format('[%-8s] %-13s %s', e[:level], e[:step], e[:action])
          line += " | building: #{e[:building]}" if e[:building]
          line += " | target: #{e[:target]}" if e[:target]
          line += " | inputs: #{compact_hash(e[:inputs])}" if e[:inputs]
          line += " | value: #{e[:value]}" if e[:value]
          line += " | evidence: #{e[:evidence]}" if e[:evidence]
          line += " | per #{e[:article]}" if e[:article]
          line += " | ruling #{e[:ruling]}" if e[:ruling]
          line
        end.join("\n")
      end

      private

      def add(level, step, action, target, inputs, value, article, ruling, evidence)
        @entries << { step: step, target: target, action: action, inputs: inputs,
                      value: value, article: article, ruling: ruling, evidence: evidence,
                      building: @building, level: level }.compact
        self
      end

      def compact_hash(hash)
        hash.map { |k, v| "#{k}=#{v.is_a?(Array) ? v.join('/') : v}" }.join(', ')
      end
    end
end
