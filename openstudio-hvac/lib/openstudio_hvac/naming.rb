module OpenStudioHVAC
  # Pluggable air-loop naming.
  #
  # :default    -> human-readable ("PSZ RTU ... | Zone Name")
  # :necb_pipe_name -> the machine-parseable NECB convention
  #                    (e.g. "sys_3|mixed|shr>none|sc>dx|sh>c-g|ssf>cv|zh>b-hw|zc>none|srf>none|"),
  #                    a faithful port of openstudio-standards assign_base_sys_name token maps,
  #                    for hosts whose downstream code (ECM, costing, QAQC) parses these names.
  module Naming
    HTG_TOKENS = {
      'none' => 'sh>none', 'electric' => 'sh>c-e', 'hot water' => 'sh>c-hw',
      'gas' => 'sh>c-g', 'g' => 'sh>c-g', 'naturalgas' => 'sh>c-g',
      'dx' => 'sh>ashp', 'ashp' => 'sh>ashp',
      'ashp>c-g' => 'sh>ashp>c-g', 'ashp>c-e' => 'sh>ashp>c-e', 'ashp>c-hw' => 'sh>ashp>c-hw',
      'ccashp' => 'sh>ccashp', 'ccashp>c-g' => 'sh>ccashp>c-g',
      'ccashp>c-e' => 'sh>ccashp>c-e', 'ccashp>c-hw' => 'sh>ccashp>c-hw'
    }.freeze

    CLG_TOKENS = {
      'none' => 'sc>none', 'chilled water' => 'sc>c-chw', 'hydronic' => 'sc>c-chw',
      'dx' => 'sc>dx', 'ccashp' => 'sc>ccashp', 'ashp' => 'sc>ashp',
      'coil_chw' => nil # legacy quirk: unmatched token; the namer pass drops the segment
    }.freeze

    FAN_TOKENS = { 'none' => 'none', 'cv' => 'cv', 'vv' => 'vv' }.freeze

    ZONE_HTG_TOKENS = {
      'none' => 'zh>none', 'electric' => 'zh>b-e', 'hot water' => 'zh>b-hw',
      'tpfc' => 'zh>tpfc', 'fpfc' => 'zh>fpfc', 'pthp' => 'zh>pthp', 'vrf' => 'zh>vrf',
      'fancoil_4pipe' => 'zh>fancoil_4pipe' # legacy update_sys_name splices the raw value
    }.freeze

    ZONE_CLG_TOKENS = {
      'none' => 'zc>none', 'tpfc' => 'zc>tpfc', 'fpfc' => 'zc>fpfc',
      'ptac' => 'zc>ptac', 'pthp' => 'zc>pthp', 'vrf' => 'zc>vrf',
      'fancoil_4pipe' => 'zc>fancoil_4pipe'
    }.freeze

    # Build the NECB pipe-name from name parts. Token semantics match openstudio-standards
    # assign_base_sys_name exactly, and — like the legacy method — tokens are emitted in the
    # PARTS HASH INSERTION ORDER (legacy systems differ: sys3/sys4 put sys_clg before
    # sys_htg; sys6 puts sys_htg before sys_clg). Callers pass parts in the legacy order.
    #
    # @param sys_abbr [String] e.g. 'sys_3'
    # @param sys_oa [String] 'mixed' or 'doas'
    # @param parts [Hash] insertion-ordered subset of
    #   sys_hr:, sys_clg:, sys_htg:, sys_sf:, zone_htg:, zone_clg:, sys_rf:
    # @return [String]
    def self.necb_pipe_name(sys_abbr:, sys_oa:, parts:)
      htg = (parts[:sys_htg] || 'none').to_s.downcase

      tokens = parts.map do |key, value|
        v = value.to_s.downcase
        case key.to_sym
        when :sys_hr then 'shr>none'
        when :sys_clg
          # Legacy quirk preserved: DX cooling paired with heat-pump heating reads 'sc>ashp'.
          if v == 'dx' && ['dx', 'ashp>c-g', 'ashp>c-e', 'ashp>c-hw'].include?(htg)
            'sc>ashp'
          elsif CLG_TOKENS.key?(v)
            CLG_TOKENS[v]   # may be nil (segment dropped, e.g. 'coil_chw')
          else
            'sc>none'
          end
        when :sys_htg then HTG_TOKENS.fetch(v, 'sh>none')
        when :sys_sf then "ssf>#{FAN_TOKENS.fetch(v, 'none')}"
        when :zone_htg then ZONE_HTG_TOKENS.fetch(v, 'zh>none')
        when :zone_clg then ZONE_CLG_TOKENS.fetch(v, 'zc>none')
        when :sys_rf then "srf>#{FAN_TOKENS.fetch(v, 'none')}"
        end
      end.compact

      ([sys_abbr, sys_oa] + tokens).join('|') + '|'
    end

    # Apply a name to an air loop per the selected namer.
    #
    # @param namer [Symbol] :default or :necb_pipe_name
    # @param air_loop [OpenStudio::Model::AirLoopHVAC]
    # @param system_name [String] the catalog's descriptive name
    # @param sys_abbr [String]
    # @param sys_oa [String]
    # @param parts [Hash] pipe-name parts (see necb_pipe_name)
    # @param suffix [String, nil] disambiguator (e.g. control zone name)
    def self.apply(namer, air_loop, system_name:, sys_abbr:, sys_oa:, parts:, suffix: nil)
      case namer
      when :necb_pipe_name
        air_loop.setName(necb_pipe_name(sys_abbr: sys_abbr, sys_oa: sys_oa, parts: parts))
      else
        air_loop.setName([system_name, suffix].compact.join(' | '))
      end
      air_loop
    end
  end
end
