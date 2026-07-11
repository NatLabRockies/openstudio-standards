module OpenStudioHVAC
  module Systems
    # Built-up multizone VAV with reheat (port of NECB sys6): per building story, one air
    # handler with variable-volume supply AND return fans, hot-water or electric heating
    # coil, chilled-water cooling coil, constant 13C supply-air setpoint, and per-zone VAV
    # reheat terminals with NECB minimums, plus zone baseboards. Chilled/condenser water
    # plant is created by the builder (PlantLoops.chilled_water) and passed in.
    class VAVReheat < BaseSystem
      # @param model [OpenStudio::Model::Model]
      # @param zones [Array<OpenStudio::Model::ThermalZone>]
      # @param control_zone [OpenStudio::Model::ThermalZone] unused (multizone system);
      #   accepted for the shared build contract
      # @param namer [Symbol] :default or :necb_pipe_name
      # @param hw_loop [OpenStudio::Model::PlantLoop, nil] for hot-water coil/reheat/baseboards
      # @param chw_loop [OpenStudio::Model::PlantLoop] chilled-water loop for the cooling coil
      # @return [Array<OpenStudio::Model::AirLoopHVAC>]
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        raise(ArgumentError, 'VAVReheat requires a chilled water loop (needs_chiller)') if chw_loop.nil?

        heating_coil_type = config['heating_coil_type']
        baseboard_type = config['baseboard_type']
        air_loops = []

        zone_groups(model, zones).each do |group|
          air_loops << build_air_loop(model, group,
                                      heating_coil_type: heating_coil_type,
                                      baseboard_type: baseboard_type,
                                      hw_loop: hw_loop, chw_loop: chw_loop,
                                      namer: namer)
        end
        air_loops
      end

      private

      # One air handler per building story (the NECB sys6 convention); zones not assigned
      # to any story form one additional group.
      def zone_groups(model, zones)
        groups = []
        grouped = []
        model.getBuildingStorys.sort_by(&:nameString).each do |story|
          story_zones = story.spaces
                             .map { |space| space.thermalZone }
                             .select(&:is_initialized).map(&:get).uniq
          group = story_zones & zones
          next if group.empty?

          groups << group
          grouped |= group
        end
        leftovers = zones - grouped
        groups << leftovers unless leftovers.empty?
        groups
      end

      def build_air_loop(model, group, heating_coil_type:, baseboard_type:, hw_loop:, chw_loop:, namer:)
        always_on = model.alwaysOnDiscreteSchedule

        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        supply_fan = OpenStudio::Model::FanVariableVolume.new(model, always_on)
        supply_fan.setName('Sys6 Supply Fan')   # 'Supply'/'Return' substrings are load-bearing
        return_fan = OpenStudio::Model::FanVariableVolume.new(model, always_on)
        return_fan.setName('Sys6 Return Fan')   # for host fan rules

        htg_coil = Coils.heating_coil(model, heating_coil_type, always_on, hw_loop: hw_loop)
        clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, always_on)
        chw_loop.addDemandBranchForComponent(clg_coil)

        oa_system = build_oa_system(model)

        supply_inlet_node = air_loop.supplyInletNode
        supply_fan.addToNode(supply_inlet_node)
        htg_coil.addToNode(supply_inlet_node)
        clg_coil.addToNode(supply_inlet_node)
        oa_system.addToNode(supply_inlet_node)
        return_air_node = oa_system.returnAirModelObject.get.to_Node.get
        return_fan.addToNode(return_air_node)

        sat = sizing.fetch('system_supply_air_temperature', 13.0)
        spm = OpenStudio::Model::SetpointManagerScheduled.new(
          model, Schedules.constant_ruleset(model, 'Supply Air Temp', sat)
        )
        spm.addToNode(air_loop.supplyOutletNode)

        group.each do |zone|
          apply_zone_sizing(zone)
          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)

          reheat_coil = Coils.heating_coil(model, heating_coil_type, always_on, hw_loop: hw_loop)
          terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, always_on, reheat_coil)
          air_loop.addBranchForZone(zone, terminal.to_StraightComponent)
          # NECB minimum zone airflow settings
          if sizing['zone_vav_min_flow_factor_per_floor_area']
            terminal.setFixedMinimumAirFlowRate(sizing['zone_vav_min_flow_factor_per_floor_area'] * zone.floorArea)
          end
          terminal.setMaximumReheatAirTemperature(sizing['zone_vav_max_reheat_temp']) if sizing['zone_vav_max_reheat_temp']
          terminal.setDamperHeatingAction(sizing['zone_vav_damper_action']) if sizing['zone_vav_damper_action']
        end

        # NOTE parts order: sys6 legacy emits sys_htg BEFORE sys_clg (insertion order).
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: 'mixed',
                     parts: {
                       sys_hr: 'none',
                       sys_htg: heating_coil_type,
                       sys_clg: 'Chilled Water',
                       sys_sf: 'vv',
                       zone_htg: baseboard_type,
                       zone_clg: 'none',
                       sys_rf: 'vv'
                     },
                     suffix: group.first.nameString)
        air_loop
      end
    end
  end
end
