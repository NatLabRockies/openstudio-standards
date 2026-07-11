module OpenStudioHVAC
  module Systems
    # ECM "hs08"/"hs13": DOAS + VRF (port of NECB ECMS add_ecm_hs08_ccashp_vrf /
    # add_ecm_hs13_ashp_vrf topologies). An air-cooled outdoor VRF unit with heat recovery
    # serves per-zone VRF terminal units; a DOAS (CCASHP for hs08 or ASHP for hs13, with a
    # supplemental coil) delivers ventilation at a constant 20C supply.
    #
    # Topology only: the Mitsubishi/NECB2015 performance curves are applied by the host's
    # ECM efficiency pass after sizing (including the outdoor unit's defrost-EIR curve).
    class DoasVrf < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        air_eqpt = config.fetch('air_eqpt', 'ccashp')
        supp = config.fetch('supp_htg_fuel', 'Electric') == 'Gas' ? 'coil_gas' : 'coil_electric'

        outdoor_unit = EcmAir.add_outdoor_vrf_unit(model)

        air_loop, = EcmAir.assemble(model, zones,
                                    air_eqpt: air_eqpt,
                                    supp_htg_type: supp,
                                    spm_type: 'scheduled',
                                    supply_fan_type: 'constant_volume',
                                    hw_loop: hw_loop)
        apply_system_sizing(air_loop)

        zones.sort_by(&:nameString).each do |zone|
          apply_zone_sizing(zone)
          EcmAir.add_diffuser(model, air_loop, zone, 'single_duct_uncontrolled')
          EcmAir.add_zone_vrf_terminal(model, zone, outdoor_unit)
        end

        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config.fetch('sys_abbr', 'sys_1'),
                     sys_oa: 'doas',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: air_eqpt,
                       sys_htg: air_eqpt,
                       sys_sf: 'cv',
                       zone_htg: 'vrf',
                       zone_clg: 'vrf',
                       sys_rf: 'none'
                     },
                     suffix: nil)
        [air_loop]
      end
    end
  end
end
