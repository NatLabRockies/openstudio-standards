module OpenStudioEnvelope
  module NECB
    # Core prescriptive lookups over the vendored rules data. Semantics are
    # legacy-exact (parity-gated against openstudio-standards NECB2020):
    # - max_u: scan HDD-bin ceilings ascending, return the first value where
    #   hdd < bin; fallback 0.110 (legacy max_u_necb, building_envelope.rb:307)
    # - max_fdwr: piecewise interpreter over structured data (never eval'd)
    module_function

    U_FALLBACK = 0.110
    SURFACE_TYPES = %w[wall roofceiling floor window skylight door].freeze
    BOUNDARIES = %w[outdoors ground].freeze

    # Maximum overall (effective) thermal transmittance, W/(m2.K).
    # @param surface [String] wall|roofceiling|floor|window|skylight|door
    # @param boundary [String] outdoors|ground
    def max_u(vintage:, surface:, boundary:, hdd:, audit: nil)
      table = NECB.rules(vintage).fetch('u_values').fetch(boundary.to_s) do
        raise(ArgumentError, "unknown boundary '#{boundary}' (#{BOUNDARIES.join('/')})")
      end
      bins = table.fetch(surface.to_s) do
        raise(ArgumentError, "unknown surface '#{surface}' for boundary '#{boundary}'")
      end
      value = bins.sort_by { |k, _| k.to_i }.find { |k, _| hdd < k.to_i }&.last || U_FALLBACK
      audit&.decision(:rules, 'maximum effective U-value looked up',
                      inputs: { vintage: vintage, surface: surface, boundary: boundary, hdd: hdd },
                      value: "#{value} W/m2K",
                      article: "NECB #{vintage} Tables 3.2.2.x/3.2.3.1 (3.1.1.7 effective)")
      value
    end

    # Ground-floor insulation extent (Table 3.2.3.1 floors row): zone 8
    # requires the table U over the full slab area; zones 4-7B require it only
    # within a perimeter strip (3.2.3.3.(3)) — the slab field carries no
    # prescriptive maximum there.
    def ground_floor_extent(vintage:, hdd:)
      ext = NECB.rules(vintage)['ground_floor_extent']
      return { extent: :full_area } if ext.nil? || hdd >= ext.fetch('full_area_min_hdd')

      { extent: :perimeter_strip, width_m: ext.fetch('strip_width_m') }
    end

    # Maximum fenestration-and-door-to-gross-wall ratio (3.2.1.4.(1)).
    def max_fdwr(vintage:, hdd:, audit: nil)
      fdwr = NECB.rules(vintage).fetch('fdwr')
      value = fdwr.fetch('pieces').each do |piece|
        if piece['linear']
          next unless hdd >= piece['min_hdd'] && hdd < piece['max_hdd']

          l = piece['linear']
          break (l['intercept'] + l['slope'] * hdd) / l['divisor']
        elsif piece['max_hdd']
          break piece['value'] if hdd < piece['max_hdd']
        elsif piece['min_hdd']
          break piece['value'] if hdd >= piece['min_hdd']
        end
      end
      raise("fdwr pieces did not cover hdd=#{hdd}") unless value.is_a?(Numeric)

      audit&.decision(:rules, 'maximum FDWR computed',
                      inputs: { vintage: vintage, hdd: hdd }, value: value.round(4),
                      article: fdwr['article'])
      value
    end

    # Maximum skylight-to-gross-roof-area ratio (3.2.1.4.(2)).
    def max_srr(vintage:, audit: nil)
      srr = NECB.rules(vintage).fetch('srr_max')
      audit&.decision(:rules, 'maximum skylight-to-roof ratio looked up',
                      inputs: { vintage: vintage }, value: srr['value'], article: srr['article'])
      srr['value']
    end
  end
end
