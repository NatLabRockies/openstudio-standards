module OpenStudioHVAC
  module Systems
    # Make-up air unit + per-zone PTAC (port of NECB sys1, non-heat-pump path): a 100%%
    # outdoor-air constant-volume MAU (sized on the ventilation requirement, constant 20C
    # supply) delivers ventilation through uncontrolled diffusers, while each zone gets a
    # PTAC (DX cooling with NECB curves, always-off electric heating section, zero OA) for
    # cooling and baseboards for heating.
    class MauPtac < BaseSystem
      # @param model [OpenStudio::Model::Model]
      # @param zones [Array<OpenStudio::Model::ThermalZone>]
      # @param control_zone [OpenStudio::Model::ThermalZone] unused (MAU has a scheduled
      #   setpoint); accepted for the shared build contract
      # @param namer [Symbol] :default or :necb_pipe_name
      # @param hw_loop [OpenStudio::Model::PlantLoop, nil] for hot-water MAU coil/baseboards
      # @return [Array<OpenStudio::Model::AirLoopHVAC>]
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        always_off = Schedules.always_off(model)
        mau_heating_coil_type = config.fetch('mau_heating_coil_type', 'Electric')
        baseboard_type = config['baseboard_type']

        # --- make-up air unit ---
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        fan.setName("#{config['sys_abbr']} MAU Supply Fan")

        htg_coil = Coils.heating_coil(model, mau_heating_coil_type, always_on, hw_loop: hw_loop)
        clg_coil = Coils.dx_cooling_single_speed(model, always_on)
        oa_system = build_oa_system(model)

        supply_inlet_node = air_loop.supplyInletNode
        fan.addToNode(supply_inlet_node)
        htg_coil.addToNode(supply_inlet_node)
        clg_coil.addToNode(supply_inlet_node)
        oa_system.addToNode(supply_inlet_node)

        sat = sizing.fetch('system_supply_air_temperature', 20.0)
        spm = OpenStudio::Model::SetpointManagerScheduled.new(
          model, Schedules.constant_ruleset(model, 'Makeup-Air Unit Supply Air Temp', sat)
        )
        spm.addToNode(air_loop.supplyOutletNode)

        # --- zones: sizing, PTAC, baseboards, diffusers ---
        zones.each do |zone|
          apply_zone_sizing(zone)
          add_ptac(model, zone, always_on, always_off)
          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)
          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
        end

        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: 'doas',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: 'dx',
                       sys_htg: mau_heating_coil_type,
                       sys_sf: 'cv',
                       zone_htg: baseboard_type,
                       zone_clg: 'ptac',
                       sys_rf: 'none'
                     },
                     suffix: nil)
        [air_loop]
      end

      private

      # PTAC with DX cooling (NECB curves), an always-off electric heating section (heating
      # is the baseboards' job), and effectively zero outdoor air (the MAU ventilates).
      # Port of NECB add_ptac_dx_cooling with zero_outdoor_air = true.
      def add_ptac(model, zone, always_on, always_off)
        htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_off)
        clg_coil = Coils.dx_cooling_single_speed(model, always_on, name: "#{zone.nameString} PTAC DX Clg Coil")

        fan = OpenStudio::Model::FanOnOff.new(model)
        fan.setPressureRise(640)

        ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model, always_on, fan, htg_coil, clg_coil)
        ptac.setName("#{zone.nameString} PTAC")
        ptac.setSupplyAirFanOperatingModeSchedule(always_off)
        ptac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-5)
        ptac.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-5)
        ptac.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-5)
        ptac.addToThermalZone(zone)
      end
    end
  end
end
