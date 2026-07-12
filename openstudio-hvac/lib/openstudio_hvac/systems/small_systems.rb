module OpenStudioHVAC
  module Systems
    # Per-zone forced-air furnace / central AC (port of the generic
    # model_add_furnace_central_ac essentials): one CV air loop per zone with a gas
    # heating coil (config 'heating': true) and/or single-speed DX cooling
    # (config 'cooling': true); outdoor air per config 'ventilation'.
    class Furnace < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        heating = config.fetch('heating', true)
        cooling = config.fetch('cooling', false)
        ventilation = config.fetch('ventilation', true)

        zones.sort_by(&:nameString).map do |zone|
          air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
          air_loop.setName("#{config.fetch('name')} | #{zone.nameString}")

          fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
          fan.setName("#{air_loop.nameString} Fan")

          supply_inlet_node = air_loop.supplyInletNode
          fan.addToNode(supply_inlet_node)
          if heating
            htg = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
            htg.setName("#{air_loop.nameString} Heating Coil")
            htg.addToNode(supply_inlet_node)
          end
          if cooling
            clg = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
            clg.setName("#{air_loop.nameString} Cooling Coil")
            clg.addToNode(supply_inlet_node)
          end
          build_oa_system(model).addToNode(supply_inlet_node) if ventilation

          spm = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
          spm.setControlZone(zone)
          spm.addToNode(air_loop.supplyOutletNode)

          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
          air_loop
        end
      end
    end

    # Per-zone direct evaporative coolers (port of the generic model_add_evap_cooler
    # essentials): one air loop per zone with a direct research-special evaporative
    # cooler and a supply-air setpoint that follows outdoor wet-bulb. The legacy EMS
    # availability program (cooling-load-driven on/off) is NOT replicated — documented
    # simplification; the follow-OAT setpoint still governs operation.
    class EvapCooler < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        zones.sort_by(&:nameString).map do |zone|
          air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
          air_loop.setName("#{config.fetch('name')} | #{zone.nameString}")

          fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
          fan.setName("#{air_loop.nameString} Fan")

          evap = OpenStudio::Model::EvaporativeCoolerDirectResearchSpecial.new(model, always_on)
          evap.setName("#{air_loop.nameString} Evap Media")
          evap.setCoolerDesignEffectiveness(0.85)

          supply_inlet_node = air_loop.supplyInletNode
          fan.addToNode(supply_inlet_node)
          evap.addToNode(supply_inlet_node)
          build_oa_system(model).addToNode(supply_inlet_node)

          spm = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(model)
          spm.setReferenceTemperatureType('OutdoorAirWetBulb')
          spm.setOffsetTemperatureDifference(0.0)
          spm.setMaximumSetpointTemperature(30.0)
          spm.setMinimumSetpointTemperature(15.5)
          spm.addToNode(air_loop.supplyOutletNode)

          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
          air_loop
        end
      end
    end

    # Water-source heat pumps: a condenser loop (10-35C, boiler + evaporative fluid
    # cooler) serving per-zone water-to-air heat pump units (equation-fit coils,
    # electric supplemental, cycling fan). Port of the generic model_add_hp_loop +
    # model_add_water_source_hp essentials. Ventilation defaults off (the CBECS WSHP
    # names are all DOAS composites — the DOAS part ventilates).
    class Wshp < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        always_on = model.alwaysOnDiscreteSchedule
        hp_loop = build_hp_loop(model, boiler_fuel: config.fetch('boiler_fuel', 'NaturalGas'))

        zones.sort_by(&:nameString).each do |zone|
          apply_zone_sizing(zone)

          fan = OpenStudio::Model::FanOnOff.new(model)
          fan.setName("#{zone.nameString} WSHP Fan")

          htg_coil = OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit.new(model)
          htg_coil.setName("#{zone.nameString} Water-to-Air HP Htg Coil")
          clg_coil = OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit.new(model)
          clg_coil.setName("#{zone.nameString} Water-to-Air HP Clg Coil")
          supp_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
          supp_coil.setName("#{zone.nameString} Supplemental Htg Coil")

          wshp = OpenStudio::Model::ZoneHVACWaterToAirHeatPump.new(model, always_on, fan, htg_coil, clg_coil, supp_coil)
          wshp.setName("#{zone.nameString} WSHP")
          unless config.fetch('ventilation', false)
            wshp.setOutdoorAirFlowRateDuringCoolingOperation(OpenStudio::OptionalDouble.new(0.0))
            wshp.setOutdoorAirFlowRateDuringHeatingOperation(OpenStudio::OptionalDouble.new(0.0))
            wshp.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(OpenStudio::OptionalDouble.new(0.0))
          end
          wshp.addToThermalZone(zone)

          hp_loop.addDemandBranchForComponent(htg_coil)
          hp_loop.addDemandBranchForComponent(clg_coil)
        end
        []
      end

      private

      # config 'heat_rejection': 'fluid_cooler' (default), 'cooling_tower', or 'ground'
      # (vertical ground heat exchanger, no boiler — the GSHP variant).
      def build_hp_loop(model, boiler_fuel:)
        existing = model.getPlantLoops.find { |pl| pl.nameString == 'Heat Pump Loop' }
        return existing if existing

        heat_rejection = config.fetch('heat_rejection', 'fluid_cooler')

        loop = OpenStudio::Model::PlantLoop.new(model)
        loop.setName('Heat Pump Loop')
        loop.setMinimumLoopTemperature(10.0)
        loop.setMaximumLoopTemperature(35.0)
        sizing = loop.sizingPlant
        sizing.setLoopType('Heating')
        sizing.setDesignLoopExitTemperature(30.0)
        sizing.setLoopDesignTemperatureDifference(11.0)

        pump = OpenStudio::Model::PumpConstantSpeed.new(model)
        pump.setName("#{loop.nameString} Pump")
        pump.addToNode(loop.supplyInletNode)

        unless heat_rejection == 'ground'
          boiler = OpenStudio::Model::BoilerHotWater.new(model)
          boiler.setName("#{loop.nameString} Boiler")
          boiler.setFuelType(boiler_fuel)
          loop.addSupplyBranchForComponent(boiler)
        end

        case heat_rejection
        when 'ground'
          ghx = OpenStudio::Model::GroundHeatExchangerVertical.new(model)
          ghx.setName("#{loop.nameString} Ground HX")
          loop.addSupplyBranchForComponent(ghx)
        when 'cooling_tower'
          tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
          tower.setName("#{loop.nameString} Cooling Tower")
          loop.addSupplyBranchForComponent(tower)
        else # fluid_cooler
          cooler = OpenStudio::Model::EvaporativeFluidCoolerSingleSpeed.new(model)
          cooler.setName("#{loop.nameString} Fluid Cooler")
          cooler.setDesignSprayWaterFlowRate(0.002208)
          cooler.setPerformanceInputMethod('UFactorTimesAreaAndDesignWaterFlowRate')
          loop.addSupplyBranchForComponent(cooler)
        end

        loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(loop.supplyOutletNode)

        spm = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
        spm.setName("#{loop.nameString} Scheduled Dual Setpoint")
        spm.setHighSetpointSchedule(Schedules.constant_ruleset(model, 'HP Loop High Temp', 35.0))
        spm.setLowSetpointSchedule(Schedules.constant_ruleset(model, 'HP Loop Low Temp', 10.0))
        spm.addToNode(loop.supplyOutletNode)
        loop
      end
    end

    # VRF: outdoor VRF unit + per-zone terminal units (the CBECS 'VRF' name). Standalone
    # 'VRF' lets terminals ventilate (default OA); in 'DOAS with VRF' composites the
    # terminals' OA is zeroed (config 'zone_ventilation': false) and the DOAS ventilates.
    class Vrf < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        outdoor_unit = EcmAir.add_outdoor_vrf_unit(model)
        vent = config.fetch('zone_ventilation', true)
        zones.sort_by(&:nameString).each do |zone|
          terminal = EcmAir.add_zone_vrf_terminal(model, zone, outdoor_unit)
          next unless vent

          # restore default (autosized) OA on the terminal for the self-ventilating case
          terminal.autosizeOutdoorAirFlowRateDuringCoolingOperation
          terminal.autosizeOutdoorAirFlowRateDuringHeatingOperation
          terminal.autosizeOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded
        end
        []
      end
    end

    # Per-zone energy recovery ventilators (the 'with ERVs' suffix): a standalone zone ERV
    # with supply/exhaust fans and a sensible+latent air-to-air heat exchanger.
    class ZoneErvs < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        zones.sort_by(&:nameString).each do |zone|
          supply_fan = OpenStudio::Model::FanOnOff.new(model)
          supply_fan.setName("#{zone.nameString} ERV Supply Fan")
          exhaust_fan = OpenStudio::Model::FanOnOff.new(model)
          exhaust_fan.setName("#{zone.nameString} ERV Exhaust Fan")

          erv_controller = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilatorController.new(model)
          heat_exchanger = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(model)
          heat_exchanger.setName("#{zone.nameString} ERV HX")
          heat_exchanger.setSupplyAirOutletTemperatureControl(false)

          erv = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator.new(model, heat_exchanger, supply_fan, exhaust_fan)
          erv.setName("#{zone.nameString} ERV")
          erv.setController(erv_controller)
          erv.addToThermalZone(zone)
        end
        []
      end
    end

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
