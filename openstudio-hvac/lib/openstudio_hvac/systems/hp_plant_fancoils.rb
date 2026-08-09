module OpenStudioHVAC
  module Systems
    # ECM "hs14"/"hs15"/"hs16": heat-pump plant + four-pipe fan coils (port of NECB ECMS
    # add_ecm_hs14_cgshp_fancoils / add_ecm_hs15_cawhp_fancoils / add_ecm_hs16_...).
    # A DOAS (hot/chilled-water coils, or ASHP DX for hs16) ventilates; per-zone four-pipe
    # fan coils condition; heating and cooling plants are heat-pump-led with boiler backup:
    #
    # - 'gshp' (hs14): water-to-water equation-fit heating HP (W2W HCAPF/HPOWERF curves) +
    #   series boilers on the HW loop; water-cooled + series air-cooled chillers on the CHW
    #   loop; a ground-loop heat exchanger condenser loop modeled as district heating +
    #   cooling in series (5C/25C setpoints), serving the HP and the water-cooled chiller.
    # - 'cawhp' (hs15/hs16): air-source plant-loop-EIR heating HP (60C, min -15C source,
    #   COP 3) + series boilers; companion plant-loop-EIR cooling HP (7C/6K); the four
    #   CAWHP performance biquadratics are part of the equipment definition (curves.json).
    #
    # Deviations from legacy (documented): the legacy 'AirSoure' typo (a silently failing
    # setCondenserType on the heating HP) is corrected to 'AirSource'; legacy hs14's
    # destructive `model.getOutputVariables.each(&:remove)` is NOT replicated (the two
    # district-rate output variables are still added).
    class HpPlantFanCoils < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        plant_type = config.fetch('plant_type', 'cawhp')
        air_eqpt = config.fetch('air_eqpt', 'hydronic') # 'hydronic' (coil_hw/chw) or 'ashp' (hs16)
        supp = config.fetch('supp_htg_fuel', 'None')

        # --- DOAS + zone fan coils (coils intentionally unattached until plants exist) ---
        air_loop, = EcmAir.assemble(model, zones,
                                    htg_type: air_eqpt == 'ashp' ? 'ashp' : 'coil_hw',
                                    clg_type: air_eqpt == 'ashp' ? 'ashp' : 'coil_chw',
                                    supp_htg_type: supp == 'None' ? 'none' : (supp == 'Gas' ? 'coil_gas' : 'coil_electric'),
                                    spm_type: 'warmest',
                                    supply_fan_type: 'constant_volume')
        apply_system_sizing(air_loop)

        zones.sort_by(&:nameString).each do |zone|
          apply_zone_sizing(zone)
          EcmAir.add_diffuser(model, air_loop, zone, 'single_duct_uncontrolled')
          EcmAir.add_zone_fancoil(model, zone)
        end

        boiler_fuels = [config.fetch('boiler_fuel', 'Electricity')]

        # --- heating plant ---
        hp_hw_loop, hw_hp = build_hw_plant(model, plant_type, boiler_fuels)
        model.getCoilHeatingWaters.sort_by(&:nameString).each { |c| hp_hw_loop.addDemandBranchForComponent(c) }

        # --- cooling plant ---
        hp_chw_loop, chw_eqpt = build_chw_plant(model, plant_type, hw_hp)
        model.getCoilCoolingWaters.sort_by(&:nameString).each { |c| hp_chw_loop.addDemandBranchForComponent(c) }

        # --- ground loop (hs14 only) ---
        build_glhx_loop(model, hw_hp, chw_eqpt) if plant_type == 'gshp'

        Naming.apply(namer, air_loop,
                     system_name: config['name'],
                     sys_abbr: config.fetch('sys_abbr', 'sys_1'),
                     sys_oa: 'doas',
                     parts: {
                       sys_hr: 'none',
                       sys_clg: air_eqpt == 'ashp' ? 'ashp' : 'coil_chw',
                       sys_htg: air_eqpt == 'ashp' ? 'ashp' : 'coil_hw',
                       sys_sf: 'cv',
                       zone_htg: 'fancoil_4pipe',
                       zone_clg: 'fancoil_4pipe',
                       sys_rf: 'none'
                     },
                     suffix: nil)
        [air_loop]
      end

      private

      def base_plant_loop(model, name, loop_type, setpoint, temp_diff)
        loop = OpenStudio::Model::PlantLoop.new(model)
        loop.setName(name)
        loop.sizingPlant.setLoopType(loop_type)
        loop.sizingPlant.setDesignLoopExitTemperature(setpoint) if setpoint
        loop.sizingPlant.setLoopDesignTemperatureDifference(temp_diff) if temp_diff
        pump = OpenStudio::Model::PumpVariableSpeed.new(model)
        pump.setName('PumpVariableSpeed')
        pump.addToNode(loop.supplyInletNode)
        loop
      end

      def finish_plant_loop(model, loop, eqpt, setpoint)
        loop.addSupplyBranchForComponent(eqpt)
        loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(loop.supplyOutletNode)
        return unless setpoint

        sch = OpenStudio::Model::ScheduleConstant.new(model)
        sch.setValue(setpoint)
        spm = OpenStudio::Model::SetpointManagerScheduled.new(model, sch)
        spm.setName('SetpointManagerScheduled')
        spm.addToNode(loop.supplyOutletNode)
      end

      def add_series_boilers(model, hp_outlet_node, fuels)
        boilers = fuels.map do |fuel|
          boiler = OpenStudio::Model::BoilerHotWater.new(model)
          boiler.setFuelType(fuel)
          boiler
        end
        boilers.reverse_each { |b| b.addToNode(hp_outlet_node) }
        boilers
      end

      def build_hw_plant(model, plant_type, boiler_fuels)
        # 60.0 C setpoint / 5.0 K deltaT: legacy parity — hs14 add_plantloop args
        # (ECMS/hvac_systems.rb:1834-1835) and hs15 (:2146-2147).
        loop = base_plant_loop(model, 'HW PlantLoop', 'Heating', 60.0, 5.0)
        if plant_type == 'gshp'
          hp = OpenStudio::Model::HeatPumpWaterToWaterEquationFitHeating.new(model)
          hp.setName('HeatPumpWaterToWaterEquationFitHeating')
          hp.setHeatingCapacityCurve(Curves.build(model, 'HEATPUMP_WATERTOWATER_HCAPF'))
          hp.setHeatingCompressorPowerCurve(Curves.build(model, 'HEATPUMP_WATERTOWATER_HPOWERF'))
        else
          # Heating-HP settings: legacy parity with add_ecm_hs15_cawhp_fancoils
          # (ECMS/hvac_systems.rb:2149-2156) — min source inlet -15.0 C (:2150,
          # air-source low-ambient cutoff), reference COP 3.0 (:2151),
          # min PLR 0.2 (:2156). The legacy source carries the values bare.
          hp = OpenStudio::Model::HeatPumpPlantLoopEIRHeating.new(model)
          hp.setName('HeatPumpPlantLoopEIRHeating')
          hp.setCondenserType('AirSource')   # legacy 'AirSoure' typo corrected
          hp.setMinimumSourceInletTemperature(-15.0)
          hp.setReferenceCoefficientofPerformance(3.0)
          hp.setHeatPumpSizingMethod('CoolingCapacity')
          hp.setHeatPumpDefrostControl('OnDemand')
          hp.setFlowMode('VariableSpeedPumping')
          hp.setControlType('Setpoint')
          hp.setMinimumPartLoadRatio(0.2)
          hp.setCapacityModifierFunctionofTemperatureCurve(Curves.build(model, 'CAWHP-HS15-HCAPFT'))
          hp.setElectricInputtoOutputRatioModifierFunctionofTemperatureCurve(Curves.build(model, 'CAWHP-HS15-HEIRFT'))
          loop.setLoadDistributionScheme('SequentialLoad')
        end
        finish_plant_loop(model, loop, hp, 60.0)

        hp_outlet = hp.supplyOutletModelObject.get.to_Node.get
        add_series_boilers(model, hp_outlet, boiler_fuels)
        unless plant_type == 'gshp'
          # 60.0 C SPM at the HP outlet: legacy parity, hs15 (ECMS/hvac_systems.rb:2173-2177).
          sch = OpenStudio::Model::ScheduleConstant.new(model)
          sch.setValue(60.0)
          spm = OpenStudio::Model::SetpointManagerScheduled.new(model, sch)
          spm.setName('HeatPumpHtgSetpointManager')
          spm.addToNode(hp_outlet)
        end
        [loop, hp]
      end

      def build_chw_plant(model, plant_type, hw_hp)
        # 7.0 C setpoint / 6.0 K deltaT: legacy parity — hs14 add_plantloop args
        # (ECMS/hvac_systems.rb:1871-1872) and hs15 (:2185-2186).
        loop = base_plant_loop(model, 'CHW PlantLoop', 'Cooling', 7.0, 6.0)
        if plant_type == 'gshp'
          chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
          chiller.setName('ChillerWaterCooled')
          chiller.setCondenserType('WaterCooled')
          finish_plant_loop(model, loop, chiller, 7.0)
          sec = OpenStudio::Model::ChillerElectricEIR.new(model)
          sec.addToNode(chiller.supplyOutletModelObject.get.to_Node.get)
          sec.setName('ChillerAirCooled')
          [loop, chiller]
        else
          # Cooling-HP settings: legacy parity with add_ecm_hs15_cawhp_fancoils
          # (ECMS/hvac_systems.rb:2188-2193) — reference COP 3.0 (:2190),
          # min PLR 0.2 (:2193).
          hp = OpenStudio::Model::HeatPumpPlantLoopEIRCooling.new(model)
          hp.setName('HeatPumpPlantLoopEIRCooling')
          hp.setCondenserType('AirSource')
          hp.setReferenceCoefficientofPerformance(3.0)
          hp.setFlowMode('VariableSpeedPumping')
          hp.setControlType('Load')
          hp.setMinimumPartLoadRatio(0.2)
          hp.setCapacityModifierFunctionofTemperatureCurve(Curves.build(model, 'CAWHP-HS15-CCAPFT'))
          hp.setElectricInputtoOutputRatioModifierFunctionofTemperatureCurve(Curves.build(model, 'CAWHP-HS15-CEIRFT'))
          hw_hp.setCompanionCoolingHeatPump(hp)
          finish_plant_loop(model, loop, hp, 7.0)
          [loop, hp]
        end
      end

      # Ground-loop heat exchanger modeled as district heating + cooling in series
      # (the legacy hs14 GLHX pattern), serving the W2W HP and the water-cooled chiller.
      def build_glhx_loop(model, hw_hp, chiller)
        # 10.0 K condenser deltaT: legacy parity — hs14 GLHX add_plantloop arg
        # (ECMS/hvac_systems.rb:1890).
        loop = base_plant_loop(model, 'Condenser PlantLoop GLHX', 'Condenser', nil, 10.0)
        district_htg = model.version < OpenStudio::VersionString.new('3.7.0') ? OpenStudio::Model::DistrictHeating.new(model) : OpenStudio::Model::DistrictHeatingWater.new(model)
        district_htg.setName('DistrictHeating GLHX')
        loop.addSupplyBranchForComponent(district_htg)
        loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(loop.supplyOutletNode)

        htg_outlet = district_htg.outletModelObject.get.to_Node.get
        district_clg = OpenStudio::Model::DistrictCooling.new(model)
        district_clg.setName('DistrictCooling GLHX')
        district_clg.addToNode(htg_outlet)

        # 5.0 C heating-side / 25.0 C cooling-side setpoints (the ground-loop supply-temp
        # proxy band): legacy parity — hs14 (ECMS/hvac_systems.rb:1896 and :1899).
        htg_sch = OpenStudio::Model::ScheduleConstant.new(model)
        htg_sch.setValue(5.0)
        OpenStudio::Model::SetpointManagerScheduled.new(model, htg_sch).addToNode(htg_outlet)
        clg_sch = OpenStudio::Model::ScheduleConstant.new(model)
        clg_sch.setValue(25.0)
        OpenStudio::Model::SetpointManagerScheduled.new(model, clg_sch).addToNode(loop.supplyOutletNode)

        loop.addDemandBranchForComponent(hw_hp)
        loop.addDemandBranchForComponent(chiller)

        # District-rate reporting used downstream for GLHX sizing (legacy also removes ALL
        # pre-existing output variables; that destructive step is deliberately not ported).
        %w[District\ Heating\ Water\ Rate District\ Cooling\ Water\ Rate].each do |var|
          ov = OpenStudio::Model::OutputVariable.new(var, model)
          ov.setReportingFrequency('hourly')
          ov.setKeyValue('*')
        end
        loop
      end
    end
  end
end
