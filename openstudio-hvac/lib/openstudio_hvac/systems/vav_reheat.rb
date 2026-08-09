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
      # config 'cooling_type': 'chilled_water' (default, NECB sys6) or 'dx' (packaged VAV —
      # the CBECS PVAV pattern: two-speed DX cooling, no chiller plant).
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        dx_cooling = config.fetch('cooling_type', 'chilled_water') == 'dx'
        raise(ArgumentError, 'VAVReheat requires a chilled water loop (needs_chiller)') if chw_loop.nil? && !dx_cooling

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

      # System grouping per NECB Note (3) to Table 8.4.4.7.-B (D-18; the former
      # one-air-handler-per-storey convention had NO code basis and was caught
      # by the archetype fixed-point comparison):
      #   <= 4 above-ground storeys: ONE system serves the thermal blocks of
      #     all storeys.
      #   > 4 storeys: EXTERNAL thermal blocks group by facade orientation
      #     (N/E/S/W, 45-degree-centred bins), INTERNAL blocks form one group,
      #     each grouping served by a single system.
      #   UNDERGROUND thermal blocks always form one independent group.
      # Corner blocks (exterior walls on several facades) bin by the LARGEST
      # exterior-wall area among orientations; ties resolve N > E > S > W.
      COMPASS = %w[N E S W].freeze

      def zone_groups(model, zones)
        underground, above = zones.partition { |z| underground_zone?(z) }
        groups = []
        if OpenStudioHVAC::Costing::Geometry.above_ground_storeys(model) <= 4
          groups << above unless above.empty?
        else
          external, internal = above.partition { |z| facade_wall_areas(z).values.sum > 0.0 }
          COMPASS.each do |dir|
            face = external.select { |z| dominant_orientation(z) == dir }
            groups << face unless face.empty?
          end
          groups << internal unless internal.empty?
        end
        groups << underground unless underground.empty?
        groups
      end

      # Below grade: ground-contact walls and no walls to Outdoors.
      def underground_zone?(zone)
        walls = zone.spaces.flat_map { |s| s.surfaces.select { |srf| srf.surfaceType == 'Wall' } }
        walls.none? { |w| w.outsideBoundaryCondition == 'Outdoors' } &&
          walls.any? { |w| w.outsideBoundaryCondition =~ /Ground|Foundation/i }
      end

      # Exterior wall area per compass bin (azimuth from outward normal).
      def facade_wall_areas(zone)
        areas = Hash.new(0.0)
        zone.spaces.each do |space|
          space.surfaces.each do |srf|
            next unless srf.surfaceType == 'Wall' && srf.outsideBoundaryCondition == 'Outdoors'

            az = (OpenStudio.radToDeg(srf.azimuth) + space.directionofRelativeNorth +
                  space.model.getBuilding.northAxis) % 360.0
            dir = case az
                  when 45...135 then 'E'
                  when 135...225 then 'S'
                  when 225...315 then 'W'
                  else 'N'
                  end
            areas[dir] += srf.grossArea
          end
        end
        areas
      end

      def dominant_orientation(zone)
        areas = facade_wall_areas(zone)
        COMPASS.max_by { |d| [areas[d], -COMPASS.index(d)] }
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
        if config.fetch('cooling_type', 'chilled_water') == 'dx'
          clg_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
          clg_coil.setName('CoilCoolingDXTwoSpeed_PVAV')
        else
          clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, always_on)
          chw_loop.addDemandBranchForComponent(clg_coil)
        end

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
          # Legacy NECB sys6 hard-sets max-flow-fraction-during-reheat to 0.5: with the
          # 'Single Maximum' damper action, a VAV box in reheat may open to at most half
          # its cooling design flow (air_loop_hvac_apply_vav_damper_action,
          # necb/NECB2011/hvac_systems.rb:466). T11: legacy parity (T11 = 2026-07-25 audit
          # register item; see openstudio-necb/docs/README.md).
          terminal.setMaximumFlowFractionDuringReheat(0.5)
        end

        # NOTE parts order: sys6 legacy emits sys_htg BEFORE sys_clg (insertion order).
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: 'mixed',
                     parts: {
                       sys_hr: 'none',
                       sys_htg: heating_coil_type,
                       sys_clg: config.fetch('cooling_type', 'chilled_water') == 'dx' ? 'dx' : 'Chilled Water',
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
