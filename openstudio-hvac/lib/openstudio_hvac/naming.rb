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
      'dx' => 'sc>dx', 'ccashp' => 'sc>ccashp', 'ashp' => 'sc>ashp'
    }.freeze

    FAN_TOKENS = { 'none' => 'none', 'cv' => 'cv', 'vv' => 'vv' }.freeze

    ZONE_HTG_TOKENS = {
      'none' => 'zh>none', 'electric' => 'zh>b-e', 'hot water' => 'zh>b-hw',
      'tpfc' => 'zh>tpfc', 'fpfc' => 'zh>fpfc', 'pthp' => 'zh>pthp'
    }.freeze

    ZONE_CLG_TOKENS = {
      'none' => 'zc>none', 'tpfc' => 'zc>tpfc', 'fpfc' => 'zc>fpfc',
      'ptac' => 'zc>ptac', 'pthp' => 'zc>pthp'
    }.freeze

    # Build the NECB pipe-name from name parts. Token semantics and ordering match
    # openstudio-standards assign_base_sys_name exactly (sys_hr, sys_clg, sys_htg, sys_sf,
    # zone_htg, zone_clg, sys_rf).
    #
    # @param sys_abbr [String] e.g. 'sys_3'
    # @param sys_oa [String] 'mixed' or 'doas'
    # @param parts [Hash] sys_hr:, sys_clg:, sys_htg:, sys_sf:, zone_htg:, zone_clg:, sys_rf:
    # @return [String]
    def self.necb_pipe_name(sys_abbr:, sys_oa:, parts:)
      htg = parts.fetch(:sys_htg, 'none').to_s.downcase
      clg = parts.fetch(:sys_clg, 'none').to_s.downcase

      # Legacy quirk preserved: DX cooling paired with heat-pump heating reads 'sc>ashp'.
      clg_token = if clg == 'dx' && ['dx', 'ashp>c-g', 'ashp>c-e', 'ashp>c-hw'].include?(htg)
                    'sc>ashp'
                  else
                    CLG_TOKENS.fetch(clg, 'sc>none')
                  end

      [
        sys_abbr, sys_oa,
        'shr>none',
        clg_token,
        HTG_TOKENS.fetch(htg, 'sh>none'),
        "ssf>#{FAN_TOKENS.fetch(parts.fetch(:sys_sf, 'none').to_s.downcase, 'none')}",
        ZONE_HTG_TOKENS.fetch(parts.fetch(:zone_htg, 'none').to_s.downcase, 'zh>none'),
        ZONE_CLG_TOKENS.fetch(parts.fetch(:zone_clg, 'none').to_s.downcase, 'zc>none'),
        "srf>#{FAN_TOKENS.fetch(parts.fetch(:sys_rf, 'none').to_s.downcase, 'none')}"
      ].join('|') + '|'
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
