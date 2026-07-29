require 'json'

module OpenStudioNECB
  # The adjudicated-decision registry: the machine-readable mirror of
  # docs/necb_decisions.md.
  #
  # Runtime code cites decisions through the AuditLog `ruling:` kwarg
  # (`ruling: 'D-14'`, or `'D-19 D-21'` for several). This module resolves those
  # ids to a title and a SELF-CONTAINED summary, so the AHJ report can explain
  # WHY a ruled code path did what it did without sending the reader anywhere —
  # the report carries no external references by contract.
  #
  # Entry: { 'id', 'title', 'kind', 'summary', 'articles' }
  #   kind: 'runtime'         — has at least one ruling-tagged audit call
  #         'runtime_unwired' — runtime behaviour, no ruling-tagged call
  #         'data'            — manifest / vendored-data / verification only
  #         'process'         — how the project works, not what the code does
  #
  # test/test_decisions_registry.rb enforces both drift directions: every
  # `## D-XX` heading in the doc has an entry here, and every 'runtime' entry is
  # cited by at least one `ruling:` literal in gem code.
  module Decisions
    DATA_DIR = File.expand_path('data', __dir__)

    # Every consumer of a ruling string parses it with this — mirrors the
    # joined-citation convention already used for `article:`.
    ID_PATTERN = /\bD-\d{2}\b/.freeze

    module_function

    # @return [Array<Hash>] every registered decision, document order
    def all
      @all ||= JSON.parse(File.read(File.join(DATA_DIR, 'decisions.json')))['decisions'].freeze
    end

    # @return [Hash] id => entry
    def by_id
      @by_id ||= all.to_h { |d| [d['id'], d] }.freeze
    end

    # @param id [String] e.g. 'D-14'
    # @return [Hash, nil] the entry, or nil when the id is not registered
    def lookup(id)
      by_id[id.to_s]
    end

    # @return [Array<String>] every id registered
    def ids
      @ids ||= all.map { |d| d['id'] }.freeze
    end

    # Scan a ruling string (or anything to_s-able, including nil) for decision
    # ids. Order-preserving and de-duplicated.
    # @param string [String, nil] e.g. 'D-19 D-21'
    # @return [Array<String>]
    def ids_in(string)
      string.to_s.scan(ID_PATTERN).uniq
    end

    # @param kind [String] 'runtime' | 'runtime_unwired' | 'data' | 'process'
    # @return [Array<Hash>]
    def of_kind(kind)
      all.select { |d| d['kind'] == kind.to_s }
    end
  end
end
