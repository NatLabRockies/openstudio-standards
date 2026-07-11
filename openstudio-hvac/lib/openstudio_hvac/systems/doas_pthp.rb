module OpenStudioHVAC
  module Systems
    # ECM "hs11": DOAS + air-source heat pump + zone PTHPs (port of NECB ECMS
    # add_ecm_hs11_ashp_pthp topology). A 100% outdoor-air DOAS with single-speed DX
    # heating/cooling (ASHP) and a supplemental coil serves ventilation at a constant
    # 20C supply; each zone gets a packaged terminal heat pump (DX heat/cool + electric
    # supplemental) with ~zero outdoor air, plus uncontrolled diffusers.
    #
    # Topology only: the ECM equipment performance curves and COPs (capacity-binned
    # HS11_PTHP data) are applied by the host's ECM efficiency pass
    # (ECMS#apply_efficiency_ecm_hs11_ashp_pthp) after sizing — exactly as in the legacy
    # flow, where build-time curve application is provisional and re-done post-sizing.
    class DoasPthp < BaseSystem
      # @return [Array<OpenStudio::Model::AirLoopHVAC>]
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        always_off = model.alwaysOffDiscreteSchedule
        supp_htg_fuel = config.fetch('supp_htg_fuel', 'Electric')

        # --- DOAS air loop ---
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
        clg_coil.setName('CoilCoolingDxSingleSpeed_ASHP')
        clg_coil.setCrankcaseHeaterCapacity(1.0e-6)

        htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
        htg_coil.setName('CoilHeatingDXSingleSpeed_ASHP')
        htg_coil.setDefrostStrategy('ReverseCycle')
        htg_coil.setDefrostControl('OnDemand')
        htg_coil.setCrankcaseHeaterCapacity(1.0e-6)

        supp_coil = Coils.heating_coil(model, supp_htg_fuel, always_on, hw_loop: hw_loop)
        supp_coil.setName('CoilHeatingElectric') if supp_htg_fuel =~ /Electric/i

        fan = OpenStudio::Model::FanConstantVolume.new(model)
        fan.setName('Supply Fan')   # 'Supply' substring is load-bearing for host fan rules

        # Legacy insertion order (each added at the supply outlet): clg, htg, supp, fan, spm
        clg_coil.addToNode(air_loop.supplyOutletNode)
        htg_coil.addToNode(air_loop.supplyOutletNode)
        supp_coil.addToNode(air_loop.supplyOutletNode)
        fan.addToNode(air_loop.supplyOutletNode)

        sat = sizing.fetch('system_supply_air_temperature', 20.0)
        spm = OpenStudio::Model::SetpointManagerScheduled.new(
          model, Schedules.constant_ruleset(model, 'DOAS Supply Air Temp', sat)
        )
        spm.addToNode(air_loop.supplyOutletNode)

        oa_system = build_oa_system(model)
        oa_system.addToNode(air_loop.supplyInletNode)

        # --- zones: sizing, diffuser, PTHP ---
        zones.sort_by(&:nameString).each do |zone|
          apply_zone_sizing(zone)

          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)

          pthp_clg = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
          pthp_clg.setName('CoilCoolingDXSingleSpeed_PTHP')
          pthp_clg.setCrankcaseHeaterCapacity(1.0e-6)

          pthp_htg = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
          pthp_htg.setName('CoilHeatingDXSingleSpeed_PTHP')
          pthp_htg.setDefrostStrategy('ReverseCycle')
          pthp_htg.setDefrostControl('OnDemand')
          pthp_htg.setCrankcaseHeaterCapacity(1.0e-6)

          pthp_supp = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
          pthp_supp.setName('CoilHeatingElectric')

          pthp_fan = OpenStudio::Model::FanOnOff.new(model)
          pthp_fan.setName('FanOnOff')

          pthp = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(
            model, always_on, pthp_fan, pthp_htg, pthp_clg, pthp_supp
          )
          pthp.setName('ZoneHVACPackagedTerminalHeatPump')
          pthp.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-6)
          pthp.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-6)
          pthp.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-6)
          pthp.setSupplyAirFanOperatingModeSchedule(always_off)
          pthp.addToThermalZone(zone)
        end

        # Legacy final name (assign_base_sys_name + update_sys_name):
        # sys_1|doas|shr>none|sc>ashp|sh>ashp|ssf>cv|zh>pthp|zc>pthp|srf>none|
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config.fetch('sys_abbr', 'sys_1'),
                     sys_oa: 'doas',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: 'ashp',
                       sys_htg: 'ashp',
                       sys_sf: 'cv',
                       zone_htg: 'pthp',
                       zone_clg: 'pthp',
                       sys_rf: 'none'
                     },
                     suffix: nil)
        [air_loop]
      end
    end
  end
end
