module OpenStudioHVAC
  # ONE consolidated naming grammar, GENERATED from each catalog row's structured config
  # (never hand-written, so it cannot drift or go inconsistent). The legacy names — CBECS's
  # fuel-first ("Baseboard gas boiler"), NECB's medium-first ("... Hot Water Baseboard"),
  # ECM ids ("hs11_ashp_pthp") — remain the stable catalog keys, byte-matched to their
  # upstream vocabularies; the canonical name is an equally valid resolver key and the
  # recommended one for new code and tool/MCP surfaces.
  #
  # Grammar:  <primary system>[ + <zone equipment>][ (<plant>)]
  # Example:  'Baseboard gas boiler'  ->  'hot water baseboards (gas boiler)'
  #           'PSZ RTU Gas and DX Coils and Hot Water Baseboard'
  #                -> 'packaged single-zone DX with gas heat + hot water baseboards (gas boiler)'
  module Canonical
    FUEL_WORDS = {
      'NaturalGas' => 'gas', 'Gas' => 'gas', 'Electricity' => 'electric', 'Electric' => 'electric',
      # 'DX' is the LEGACY spelling of the reference-ASHP marker (now `heat_source: 'ashp'`);
      # kept so an out-of-tree row still written that way reads as ASHP rather than as 'dx'.
      'Hot Water' => 'hot water', 'HotWater' => 'hot water', 'DX' => 'ASHP', 'None' => nil, nil => nil
    }.freeze

    def self.fuel(value)
      FUEL_WORDS.fetch(value, value.to_s.downcase)
    end

    # @param row [Hash] a catalog row (string keys). Composites recurse via Catalog.
    # @return [String] the canonical name
    def self.name(row)
      primary = primary_part(row)
      zone = zone_part(row)
      plant = plant_part(row)
      out = primary
      out += " + #{zone}" if zone
      out += " (#{plant})" if plant
      out
    end

    def self.primary_part(row)
      case row['family']
      when 'baseboards'
        row['baseboard_type'] == 'Hot Water' ? 'hot water baseboards' : 'electric baseboards'
      when 'psz'
        # Reference-ASHP marker: `heat_source: 'ashp'`, with the legacy
        # `heating_coil_type: 'DX'` spelling accepted as an alias (see data/README.md).
        ashp = row['heat_source'] == 'ashp' || row['heating_coil_type'] == 'DX'
        heat = ashp ? "ASHP heat with #{fuel(row['supp_htg_fuel'])} backup" : "#{fuel(row['heating_coil_type'])} heat"
        base = "packaged single-zone DX with #{heat}"
        base += ', one unit per zone' if row['per_zone']
        base += ', with exhaust' if row['sys_abbr'] == 'sys_4'
        base
      when 'vav_reheat'
        cool = row['cooling_type'] == 'dx' ? 'DX' : 'chilled water'
        "built-up VAV with #{fuel(row['heating_coil_type'])} reheat and #{cool} cooling"
      when 'fan_coils'
        pipes = row['fan_coil_type'] == 'TPFC' ? 'two-pipe' : 'four-pipe'
        mau = row.fetch('mau', true) ? " + #{row['mau_cooling_type'] == 'DX' ? 'DX' : 'hydronic'} make-up air" : ''
        "#{pipes} fan coils#{mau}"
      when 'mau_ptac'
        if row['reference_hp']
          "100% OA make-up air ASHP + CAV #{fuel(row['supp_htg_fuel'])} reheat"
        else
          "100% OA make-up air (#{fuel(row['mau_heating_coil_type'])} heat) + zone PTAC cooling"
        end
      when 'zone_terminal'
        case row['unit_type']
        when 'pthp' then 'zone PTHPs'
        when 'window_ac' then 'window AC units'
        else 'zone PTAC cooling'
        end
      when 'unit_heaters' then "#{fuel(row['heating_type'])} unit heaters"
      when 'furnace'
        h = row.fetch('heating', true)
        c = row.fetch('cooling', false)
        h && c ? 'per-zone furnace with DX cooling' : (h ? 'per-zone gas furnace' : 'per-zone central AC')
      when 'evap_cooler' then 'per-zone direct evaporative coolers'
      when 'wshp'
        rej = { 'cooling_tower' => 'cooling tower', 'ground' => 'ground' }.fetch(row.fetch('heat_rejection', 'fluid_cooler'), 'fluid cooler')
        "water-source heat pumps on a #{rej} loop"
      when 'doas' then 'DOAS ventilation'
      when 'vrf' then 'VRF heat recovery system'
      when 'doas_pthp' then 'DOAS ASHP + zone PTHPs'
      when 'ecm_ashp_baseboard'
        hp = row['air_eqpt'] == 'ccashp' ? 'cold-climate ASHP' : 'ASHP'
        "DOAS #{hp} + zone PTAC cooling"
      when 'ecm_doas_vrf'
        hp = row['air_eqpt'] == 'ccashp' ? 'cold-climate ASHP' : 'ASHP'
        "DOAS #{hp} + VRF"
      when 'ecm_hp_fancoils'
        plant = row['plant_type'] == 'gshp' ? 'ground-source heat pump plant' : 'air-to-water heat pump plant'
        air = row['air_eqpt'] == 'ashp' ? ' with ASHP DOAS' : ''
        "four-pipe fan coils on a #{plant}#{air}"
      when 'zone_ervs' then 'zone energy recovery ventilators'
      when 'composite'
        row.fetch('parts').map { |part| name(Catalog.resolve(part.fetch('name')).merge((part['config'] || {}).transform_keys(&:to_s))) }.join(' + ')
      else
        row['name'].to_s.downcase
      end
    end

    def self.zone_part(row)
      return nil if row['family'] == 'baseboards' # baseboards ARE the primary there

      case row['baseboard_type']
      when 'Hot Water' then 'hot water baseboards'
      when 'Electric' then 'electric baseboards'
      end
    end

    def self.plant_part(row)
      bits = []
      if row['needs_boiler']
        bits << (row['hw_source'] == 'district' ? 'district heating' : "#{fuel(row.fetch('boiler_fuel', 'NaturalGas'))} boiler")
      end
      if row['needs_chiller']
        bits << case row['chw_source']
                when 'air_cooled' then "air-cooled #{row.fetch('chiller_type', 'scroll').downcase} chiller"
                when 'district' then 'district cooling'
                else "#{row.fetch('chiller_type', 'Scroll').downcase} chiller"
                end
      end
      bits.empty? ? nil : bits.join(', ')
    end
  end
end
