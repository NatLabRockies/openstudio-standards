module OpenStudioHVAC
  module Systems
    # Fan coils + make-up air unit (port of NECB sys2 FPFC / sys5 TPFC): a constant-volume
    # MAU delivers ventilation through uncontrolled diffusers while per-zone four-pipe fan
    # coils (FPFC) or two-pipe fan coils (TPFC, via seasonal heating/cooling availability
    # schedules) do the conditioning. Hot-water and chilled/condenser-water plant serve the
    # fan coils; the MAU cooling coil is DX (NECB curves) or hydronic per config.
    #
    # Legacy parity notes:
    # - The MAU DX cooling coil uses the SEASONAL cooling availability schedule even for
    #   FPFC (legacy behavior, preserved).
    # - The MAU's SetpointManagerSingleZoneReheat has NO explicit control zone (legacy lets
    #   OpenStudio pick), and its min/max supply temps are inverted (13.1/13.0) — preserved.
    class FanCoils < BaseSystem
      # @param model [OpenStudio::Model::Model]
      # @param zones [Array<OpenStudio::Model::ThermalZone>]
      # @param control_zone [OpenStudio::Model::ThermalZone] unused (legacy MAU sets no
      #   control zone); accepted for the shared build contract
      # @param namer [Symbol] :default or :necb_pipe_name
      # @param hw_loop [OpenStudio::Model::PlantLoop] fan-coil heating (always hydronic)
      # @param chw_loop [OpenStudio::Model::PlantLoop] fan-coil cooling
      # @return [Array<OpenStudio::Model::AirLoopHVAC>]
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        raise(ArgumentError, 'FanCoils requires a hot water loop (needs_boiler)') if hw_loop.nil?
        raise(ArgumentError, 'FanCoils requires a chilled water loop (needs_chiller)') if chw_loop.nil?

        always_on = model.alwaysOnDiscreteSchedule
        fan_coil_type = config.fetch('fan_coil_type', 'FPFC')
        mau_cooling_type = config.fetch('mau_cooling_type', 'DX')
        mau_heating_coil_type = config.fetch('mau_heating_coil_type', 'Gas')
        with_mau = config.fetch('mau', true)

        clg_avail_sch, htg_avail_sch = Schedules.seasonal_availability(model)

        # --- fan coils only (no MAU): ventilation comes from elsewhere, e.g. a DOAS
        #     composite part (the CBECS 'DOAS with fan coil ...' pattern) ---
        unless with_mau
          zones.each do |zone|
            apply_zone_sizing(zone)
            add_zone_fan_coil(model, zone, fan_coil_type, always_on, htg_avail_sch, clg_avail_sch,
                              hw_loop: hw_loop, chw_loop: chw_loop)
          end
          return []
        end

        # --- make-up air unit ---
        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        apply_system_sizing(air_loop)

        fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        fan.setName("#{config['sys_abbr']} MAU Supply Fan")

        htg_coil = Coils.heating_coil(model, mau_heating_coil_type, always_on, hw_loop: hw_loop)

        clg_coil =
          case mau_cooling_type
          when 'DX'
            Coils.dx_cooling_single_speed(model, clg_avail_sch)
          when 'Hydronic', 'Hot Water', 'HotWater', 'Chilled Water'
            coil = OpenStudio::Model::CoilCoolingWater.new(model, clg_avail_sch)
            chw_loop.addDemandBranchForComponent(coil)
            coil
          else
            raise(ArgumentError, "'#{mau_cooling_type}' is not a valid MAU cooling type")
          end

        oa_system = build_oa_system(model)

        supply_inlet_node = air_loop.supplyInletNode
        fan.addToNode(supply_inlet_node)
        htg_coil.addToNode(supply_inlet_node)
        clg_coil.addToNode(supply_inlet_node)
        oa_system.addToNode(supply_inlet_node)

        spm = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
        if sizing['setpoint_manager_single_zone_reheat_supply_temp_min']
          spm.setMinimumSupplyAirTemperature(sizing['setpoint_manager_single_zone_reheat_supply_temp_min'])
        end
        if sizing['setpoint_manager_single_zone_reheat_supply_temp_max']
          spm.setMaximumSupplyAirTemperature(sizing['setpoint_manager_single_zone_reheat_supply_temp_max'])
        end
        spm.addToNode(air_loop.supplyOutletNode)

        # --- zones: sizing, fan coils, diffusers ---
        zones.each do |zone|
          apply_zone_sizing(zone)
          add_zone_fan_coil(model, zone, fan_coil_type, always_on, htg_avail_sch, clg_avail_sch,
                            hw_loop: hw_loop, chw_loop: chw_loop)
          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
        end

        # parts insertion order matches legacy sys2/5: hr, clg, htg, sf, zone_htg, zone_clg, rf
        mau_clg_part = %w[Hydronic Hot\ Water HotWater Chilled\ Water].include?(mau_cooling_type) ? 'Hydronic' : 'DX'
        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config['sys_abbr'],
                     sys_oa: 'doas',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: mau_clg_part,
                       sys_htg: legacy_htg_part(mau_heating_coil_type),
                       sys_sf: 'cv',
                       zone_htg: fan_coil_type,
                       zone_clg: fan_coil_type,
                       sys_rf: 'none'
                     },
                     suffix: nil)
        [air_loop]
      end

      private

      def add_zone_fan_coil(model, zone, fan_coil_type, always_on, htg_avail_sch, clg_avail_sch, hw_loop:, chw_loop:)
        fc_fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
        if fan_coil_type == 'TPFC'
          fc_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, htg_avail_sch)
          fc_clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, clg_avail_sch)
        else # FPFC
          fc_htg_coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
          fc_clg_coil = OpenStudio::Model::CoilCoolingWater.new(model, always_on)
        end
        hw_loop.addDemandBranchForComponent(fc_htg_coil)
        chw_loop.addDemandBranchForComponent(fc_clg_coil)

        fan_coil = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, always_on, fc_fan, fc_clg_coil, fc_htg_coil)
        fan_coil.addToThermalZone(zone)
        fan_coil
      end

      # Legacy sys2 emits short fuel tokens ('g'/'e') for the MAU heating coil.
      def legacy_htg_part(mau_heating_coil_type)
        case mau_heating_coil_type
        when 'Gas', 'NaturalGas' then 'g'
        when 'Electric', 'Electricity', 'FuelOilNo2' then 'e'
        else mau_heating_coil_type
        end
      end
    end
  end
end
