module OpenStudioHVAC
  module Systems
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
        # 10/35 C loop limits: legacy parity with model_add_hp_loop
        # (Prototype.hvac_systems.rb:794-795).
        loop.setMinimumLoopTemperature(10.0)
        loop.setMaximumLoopTemperature(35.0)
        sizing = loop.sizingPlant
        sizing.setLoopType('Heating')
        # 30.0 C exit is NOT the legacy default (model_add_hp_loop sizes at 102.2 F =
        # 39.0 C): gem choice — sized inside the loop's own 10-35 C operating band.
        # 11.0 K deltaT IS legacy parity (the 19.8 R default, converted).
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
          cooler.setDesignSprayWaterFlowRate(0.002208) # legacy parity: model_add_hp_loop (Prototype.hvac_systems.rb:870, "Based on HighRiseApartment")
          cooler.setPerformanceInputMethod('UFactorTimesAreaAndDesignWaterFlowRate')
          loop.addSupplyBranchForComponent(cooler)
        end

        loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(loop.supplyOutletNode)

        # Dual-setpoint 35/10 C reuses the loop max/min above; NOT the legacy defaults
        # (model_add_hp_loop uses 87/67 F = 30.6/19.4 C) — gem choice.
        spm = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(model)
        spm.setName("#{loop.nameString} Scheduled Dual Setpoint")
        spm.setHighSetpointSchedule(Schedules.constant_ruleset(model, 'HP Loop High Temp', 35.0))
        spm.setLowSetpointSchedule(Schedules.constant_ruleset(model, 'HP Loop Low Temp', 10.0))
        spm.addToNode(loop.supplyOutletNode)
        loop
      end
    end
  end
end
