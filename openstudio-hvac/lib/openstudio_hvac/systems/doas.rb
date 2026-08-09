module OpenStudioHVAC
  module Systems
    # Standalone ventilation DOAS: 100% outdoor-air CV loop at a constant neutral supply
    # temperature with uncontrolled diffusers — the ventilation half of the CBECS
    # 'DOAS with <zone system>' composites (built here in the NECB MAU style).
    class Doas < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        fan.setName('DOAS Supply Fan')
        htg = Coils.heating_coil(model, config.fetch('heating_type', 'Electric'), always_on, hw_loop: hw_loop)
        clg = Coils.dx_cooling_single_speed(model, always_on, name: 'DOAS DX Clg Coil')

        supply_inlet_node = air_loop.supplyInletNode
        fan.addToNode(supply_inlet_node)
        htg.addToNode(supply_inlet_node)
        clg.addToNode(supply_inlet_node)
        build_oa_system(model).addToNode(supply_inlet_node)

        spm = OpenStudio::Model::SetpointManagerScheduled.new(
          model, Schedules.constant_ruleset(model, 'DOAS Neutral Supply Air Temp', 20.0)
        )
        spm.addToNode(air_loop.supplyOutletNode)

        zones.each do |zone|
          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
        end

        Naming.apply(namer, air_loop,
                     system_name: config['name'], sys_abbr: 'doas', sys_oa: 'doas',
                     parts: { sys_hr: 'none', sys_clg: 'dx',
                              sys_htg: config.fetch('heating_type', 'Electric'),
                              sys_sf: 'cv', zone_htg: 'none', zone_clg: 'none', sys_rf: 'none' },
                     suffix: nil)
        [air_loop]
      end
    end
  end
end
