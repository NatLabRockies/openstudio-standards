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
      # @param chw_loop [OpenStudio::Model::PlantLoop, nil] unused (DX cooling); shared contract
      # @return [Array<OpenStudio::Model::AirLoopHVAC>]
      #
      # Config 'per_zone': true builds ONE packaged unit PER ZONE (each zone its own control
      # zone) — the CBECS/90.1 PSZ convention — instead of the NECB convention of one shared
      # unit over the zone group controlled by +control_zone+.
      def build(model, zones, control_zone:, namer: :default, hw_loop: nil, chw_loop: nil)
        if config['per_zone']
          return zones.map { |zone| build_unit(model, [zone], zone, namer: namer, hw_loop: hw_loop) }
        end

        [build_unit(model, zones, control_zone, namer: namer, hw_loop: hw_loop)]
      end

      private

      def build_unit(model, zones, control_zone, namer:, hw_loop:)
        always_on = model.alwaysOnDiscreteSchedule
        heating_coil_type = config['heating_coil_type']
        baseboard_type = config['baseboard_type']

        # --- air handler ---
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        fan.setName("#{config['sys_abbr']} Supply Fan")

        # Coil names are load-bearing for host efficiency dispatch (NECB '_dx'/'_ashp' selectors).
        reference_hp = heating_coil_type == 'DX'
        # 8.4.4.9.(7)/8.4.4.10.(8) staged coils: set ONLY by the NECB reference
        # ruleset (system_definitions config), so catalog defaults, proposed
        # models and CBECS builds keep the bare single-speed topology.
        staged = !config['staged_coils'].nil? && config['staged_coils'] != false
        if reference_hp
          clg_coil = if staged
                       Coils.dx_cooling_multi_speed(model, always_on, name: 'CoilCoolingDXMultiSpeed_ashp')
                     else
                       Coils.dx_cooling_single_speed(model, always_on, name: 'CoilCoolingDXSingleSpeed_ashp')
                     end
          htg_coil = if staged
                       Coils.dx_heating_multi_speed(model, always_on, name: 'CoilHeatingDXMultiSpeed_ashp')
                     else
                       Coils.dx_heating_single_speed(model, always_on, name: 'CoilHeatingDXSingleSpeed_ashp')
                     end
          supp_coil = Coils.heating_coil(model, config.fetch('supp_htg_fuel', 'Electric'), always_on, hw_loop: hw_loop)
        elsif staged
          clg_coil = Coils.dx_cooling_multi_speed(model, always_on)
          # D-49: electric resistance is not a furnace — 8.4.4.9.(7) staging does
          # not reach it, so an electric-heat staged PSZ pairs the multispeed DX
          # cooling coil with a plain single-stage electric coil.
          htg_coil = if %w[Gas NaturalGas].include?(heating_coil_type)
                       Coils.gas_heating_multi_stage(model, always_on)
                     else
                       Coils.heating_coil(model, heating_coil_type, always_on, hw_loop: hw_loop)
                     end
          supp_coil = nil
        else
          clg_coil = Coils.dx_cooling_single_speed(model, always_on)
          htg_coil = Coils.heating_coil(model, heating_coil_type, always_on, hw_loop: hw_loop)
          supp_coil = nil
        end

        oa_system = build_oa_system(model)

        supply_inlet_node = air_loop.supplyInletNode
        if staged
          # Multispeed coils cannot sit bare on an air loop (addToNode returns
          # false) — an AirLoopHVACUnitarySystem container is mandatory.
          # The supplemental coil goes on the LOOP, downstream of the unitary
          # (added first, so the unitary lands upstream of it), NOT in the
          # unitary's supplemental slot: EnergyPlus sizes a unitary's
          # supplemental heater to the heat-pump capacity, which measured 26-70%
          # short of the loop-sized coil and failed the cold-week conditioning
          # gate below the -10 degC compressor cutoff. On the loop it sizes on
          # the loop's heating design and is driven by the outlet
          # SetpointManagerSingleZoneReheat — the legacy arrangement.
          supp_coil.addToNode(supply_inlet_node) if supp_coil
          add_staged_unitary(model, air_loop, control_zone, fan, clg_coil, htg_coil, always_on)
        else
          # Legacy insertion order at the supply inlet: fan, (supp), htg, clg, oa ->
          # airflow OA -> clg -> htg -> (supp) -> fan.
          fan.addToNode(supply_inlet_node)
          supp_coil.addToNode(supply_inlet_node) if supp_coil
          htg_coil.addToNode(supply_inlet_node)
          clg_coil.addToNode(supply_inlet_node)
        end
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

        htg_part = heating_coil_type
        clg_part = 'dx'
        if reference_hp
          clg_part = 'ashp'
          supp = config.fetch('supp_htg_fuel', 'Electric')
          htg_part = case supp
                     when 'Gas', 'NaturalGas' then 'ashp>c-g'
                     when 'Hot Water', 'HotWater' then 'ashp>c-hw'
                     else 'ashp>c-e'
                     end
        end
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: 'mixed',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: clg_part,
                       sys_htg: htg_part,
                       sys_sf: 'cv',
                       zone_htg: baseboard_type,
                       zone_clg: 'none',
                       sys_rf: 'none'
                     },
                     suffix: control_zone.nameString)
        air_loop
      end

      # Wrap the fan and staged coils in an AirLoopHVACUnitarySystem — the only
      # SDK container that can host multispeed coils on an air loop.
      #
      # Control mirrors the legacy multi-speed sys3 build: Load control tracking
      # the elected control zone, an always-on fan schedule, and the
      # SetpointManagerSingleZoneReheat left on the loop outlet. Capacities and
      # flows are AUTOSIZED throughout; the equal capacity increments the code
      # asks for are realized by the UnitarySystemPerformanceMultispeed flow
      # ratios (stage k -> k/N), NOT by hard-setting stage capacities.
      #
      # @return [OpenStudio::Model::AirLoopHVACUnitarySystem]
      def add_staged_unitary(model, air_loop, control_zone, fan, clg_coil, htg_coil, always_on)
        unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
        unitary.setName("#{config['sys_abbr']} Staged Unitary #{control_zone.nameString}")
        unitary.setControlType('Load')
        unitary.setControllingZoneorThermostatLocation(control_zone)
        unitary.setSupplyFan(fan)
        unitary.setFanPlacement('BlowThrough')
        # The unitary's OWN availability schedule gates the fan inside it — the
        # air loop's availability does not reach it, and left at the always-on
        # default the reference fan runs 8760 h whatever 8.4.3.2.(1) says the
        # system's hours are. It follows the loop's schedule (the D-14 pass
        # re-points it at the schedule inherited from the proposed).
        # The fan OPERATING MODE stays continuous — a constant-volume system
        # runs its fan whenever it is available, and EnergyPlus rejects a mode
        # schedule containing zeros for this field anyway (it must be blank for
        # cycling, or strictly positive).
        unitary.setAvailabilitySchedule(air_loop.availabilitySchedule)
        unitary.setSupplyAirFanOperatingModeSchedule(always_on)
        unitary.setCoolingCoil(clg_coil)
        unitary.setHeatingCoil(htg_coil)
        if sizing['setpoint_manager_single_zone_reheat_supply_temp_max']
          unitary.setMaximumSupplyAirTemperature(sizing['setpoint_manager_single_zone_reheat_supply_temp_max'])
        end
        performance = OpenStudio::Model::UnitarySystemPerformanceMultispeed.new(model)
        performance.setName("#{config['sys_abbr']} Multispeed Performance #{control_zone.nameString}")
        unitary.setDesignSpecificationMultispeedObject(performance)
        Coils.set_stage_flow_ratios(unitary)
        unitary.addToNode(air_loop.supplyInletNode)
        unitary
      end
    end
  end
end
