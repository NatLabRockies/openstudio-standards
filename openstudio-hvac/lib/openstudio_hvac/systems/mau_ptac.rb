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
        reference_hp = config['reference_hp'] == true
        mau_heating_coil_type = config.fetch('mau_heating_coil_type', 'Electric')
        baseboard_type = config['baseboard_type']
        supp_fuel = config.fetch('supp_htg_fuel', 'Electric')

        # --- make-up air unit ---
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        fan.setName("#{config['sys_abbr']} MAU Supply Fan")

        if reference_hp
          htg_coil = Coils.dx_heating_single_speed(model, always_on, name: 'CoilHeatingDXSingleSpeed_ashp')
          clg_coil = Coils.dx_cooling_single_speed(model, always_on, name: 'CoilCoolingDXSingleSpeed_ashp')
        else
          htg_coil = Coils.heating_coil(model, mau_heating_coil_type, always_on, hw_loop: hw_loop)
          clg_coil = Coils.dx_cooling_single_speed(model, always_on)
        end
        oa_system = build_oa_system(model)

        supply_inlet_node = air_loop.supplyInletNode
        fan.addToNode(supply_inlet_node)
        htg_coil.addToNode(supply_inlet_node)
        clg_coil.addToNode(supply_inlet_node)
        oa_system.addToNode(supply_inlet_node)

        if reference_hp
          spm = OpenStudio::Model::SetpointManagerWarmest.new(model)
          spm.setName('SAT Warmest Reset Heatpump')
          spm.setStrategy('MaximumTemperature')
          spm.setMinimumSetpointTemperature(13.0)
          spm.setMaximumSetpointTemperature(20.0)
        else
          sat = sizing.fetch('system_supply_air_temperature', 20.0)
          spm = OpenStudio::Model::SetpointManagerScheduled.new(
            model, Schedules.constant_ruleset(model, 'Makeup-Air Unit Supply Air Temp', sat)
          )
        end
        spm.addToNode(air_loop.supplyOutletNode)

        # --- zones ---
        # non-HP: PTAC (cooling) + baseboards + uncontrolled diffusers (MAU ventilates)
        # ref-HP: CAV reheat terminals (reheat coil per name-encoded supplemental fuel) + baseboards
        zones.each do |zone|
          apply_zone_sizing(zone)
          if reference_hp
            rh_coil = Coils.heating_coil(model, supp_fuel, always_on, hw_loop: hw_loop)
            terminal = OpenStudio::Model::AirTerminalSingleDuctConstantVolumeReheat.new(model, always_on, rh_coil)
            air_loop.addBranchForZone(zone, terminal.to_StraightComponent)
          else
            add_ptac(model, zone, always_on, always_off)
            diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
            air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
          end
          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)
        end

        htg_part = mau_heating_coil_type
        if reference_hp
          htg_part = case supp_fuel
                     when 'Gas', 'NaturalGas' then 'ashp>c-g'
                     when 'Hot Water', 'HotWater' then 'ashp>c-hw'
                     else 'ashp>c-e'
                     end
        end
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: reference_hp ? 'mixed' : 'doas',   # legacy sys1 ref-HP reads 'mixed'
                     parts: {
                       sys_hr: 'none',
                       sys_clg: reference_hp ? 'ashp' : 'dx',
                       sys_htg: htg_part,
                       sys_sf: 'cv',
                       zone_htg: baseboard_type,
                       zone_clg: reference_hp ? 'none' : 'ptac',
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
