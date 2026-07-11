module OpenStudioHVAC
  module Systems
    # ECM "hs09"/"hs12": air-source heat pump air system + zone baseboards (port of NECB
    # ECMS add_ecm_hs09_ccashp_baseboard / add_ecm_hs12_ashp_baseboard topologies).
    # config 'air_eqpt': 'ccashp' (hs09, cold-climate variable-speed DX) or 'ashp' (hs12,
    # single-speed DX). config 'vent_type':
    # - 'doas' (default): DOAS at constant 20C + per-zone PTAC (DX cooling, always-off
    #   electric heat section, ~zero OA) + baseboards
    # - 'mixed': multizone VAV (warmest SPM 13/22, VV supply+return fans, VAV terminals
    #   with electric reheat) + baseboards; single-zone gets CV single-zone-reheat
    class AshpBaseboard < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        air_eqpt = config.fetch('air_eqpt', 'ashp')
        vent_type = config.fetch('vent_type', 'doas')
        baseboard_type = config.fetch('baseboard_type', 'Electric')
        supp = config.fetch('supp_htg_fuel', 'Electric') == 'Gas' ? 'coil_gas' : 'coil_electric'

        doas = vent_type == 'doas'
        multizone = zones.size > 1

        air_loop, = EcmAir.assemble(model, zones,
                                    air_eqpt: air_eqpt,
                                    supp_htg_type: supp,
                                    spm_type: doas ? 'scheduled' : (multizone ? 'warmest' : 'single_zone_reheat'),
                                    supply_fan_type: !doas && multizone ? 'variable_volume' : 'constant_volume',
                                    return_fan: !doas && multizone,
                                    hw_loop: hw_loop)
        apply_system_sizing(air_loop)

        diffuser_type = doas || !multizone ? 'single_duct_uncontrolled' : 'single_duct_vav_reheat'
        zones.sort_by(&:nameString).each do |zone|
          apply_zone_sizing(zone)
          EcmAir.add_diffuser(model, air_loop, zone, diffuser_type)
          EcmAir.add_zone_ptac_electric_off(model, zone) if doas
          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)
        end

        # Legacy naming quirk: in DOAS mode the zone tokens come from the PTAC pass
        # (zh>b-e, zc>ptac) regardless of the actual baseboard type.
        zone_htg_part = doas ? 'Electric' : baseboard_type
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config.fetch('sys_abbr', 'sys_1'),
                     sys_oa: doas ? 'doas' : 'mixed',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: air_eqpt,
                       sys_htg: air_eqpt,
                       sys_sf: !doas && multizone ? 'vv' : 'cv',
                       zone_htg: zone_htg_part,
                       zone_clg: doas ? 'ptac' : 'none',
                       sys_rf: !doas && multizone ? 'vv' : 'none'
                     },
                     suffix: nil)
        [air_loop]
      end
    end
  end
end
