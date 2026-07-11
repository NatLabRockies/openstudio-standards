module OpenStudioHVAC
  module Systems
    # Packaged single-zone rooftop unit: one shared constant-volume air handler with DX
    # cooling + a heating coil, tracking ONE control zone's thermostat, delivering to all
    # served zones through uncontrolled diffusers, with per-zone baseboards.
    #
    # This is the unified port of NECB sys3 (packaged rooftop) and sys4 (make-up air unit
    # with exhaust) — topologically identical (the legacy code's own comment: "This is the
    # same as system type 3... SHOULD WE COMBINE sys3 and sys4"); they differ only in
    # catalog config (sys_abbr and descriptive name).
    #
    # The control zone is an explicit caller choice (default: first zone) — no sizing run
    # or stored loads are needed to elect it.
    class PSZ < BaseSystem
      # @param model [OpenStudio::Model::Model]
      # @param zones [Array<OpenStudio::Model::ThermalZone>]
      # @param control_zone [OpenStudio::Model::ThermalZone] drives the shared handler
      # @param namer [Symbol] :default or :necb_pipe_name
      # @param hw_loop [OpenStudio::Model::PlantLoop, nil] for hot-water coil/baseboards
      # @return [Array<OpenStudio::Model::AirLoopHVAC>]
      def build(model, zones, control_zone:, namer: :default, hw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        heating_coil_type = config['heating_coil_type']
        baseboard_type = config['baseboard_type']

        # --- air handler ---
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        fan.setName("#{config['sys_abbr']} Supply Fan")

        # Coil names are load-bearing for host efficiency dispatch (e.g. NECB '_dx' selectors).
        clg_coil = Coils.dx_cooling_single_speed(model, always_on)
        htg_coil = Coils.heating_coil(model, heating_coil_type, always_on, hw_loop: hw_loop)

        oa_system = build_oa_system(model)

        supply_inlet_node = air_loop.supplyInletNode
        fan.addToNode(supply_inlet_node)
        htg_coil.addToNode(supply_inlet_node)
        clg_coil.addToNode(supply_inlet_node)
        oa_system.addToNode(supply_inlet_node)

        # Single-zone reheat setpoint manager tracking the control zone.
        spm = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
        spm.setControlZone(control_zone)
        if sizing['setpoint_manager_single_zone_reheat_supply_temp_min']
          spm.setMinimumSupplyAirTemperature(sizing['setpoint_manager_single_zone_reheat_supply_temp_min'])
        end
        if sizing['setpoint_manager_single_zone_reheat_supply_temp_max']
          spm.setMaximumSupplyAirTemperature(sizing['setpoint_manager_single_zone_reheat_supply_temp_max'])
        end
        spm.addToNode(air_loop.supplyOutletNode)

        # --- zones: sizing, baseboards, diffusers ---
        zones.each do |zone|
          apply_zone_sizing(zone)
          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)
          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
        end

        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: 'mixed',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: 'dx',
                       sys_htg: heating_coil_type,
                       sys_sf: 'cv',
                       zone_htg: baseboard_type,
                       zone_clg: 'none',
                       sys_rf: 'none'
                     },
                     suffix: control_zone.nameString)
        [air_loop]
      end
    end
  end
end
