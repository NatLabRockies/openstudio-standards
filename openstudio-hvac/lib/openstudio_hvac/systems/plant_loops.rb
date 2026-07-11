module OpenStudioHVAC
  module Systems
    # Config-driven plant loop builders (NECB setpoints ported from
    # openstudio-standards setup_hw_loop_with_components et al.).
    module PlantLoops
      # Find an existing hot-water loop (one with a boiler on the supply side), or nil.
      #
      # @param model [OpenStudio::Model::Model]
      # @return [OpenStudio::Model::PlantLoop, nil]
      def self.find_hot_water(model)
        model.getPlantLoops.find do |pl|
          pl.supplyComponents(OpenStudio::Model::BoilerHotWater.iddObjectType).any?
        end
      end

      # Build a hot-water loop: primary + secondary boiler, variable-speed pump,
      # 82C design exit / 16K dT, OA-reset 82C@-16C down to 60C@0C.
      #
      # @param model [OpenStudio::Model::Model]
      # @param fuel [String] primary boiler fuel (OpenStudio Boiler fuel type keyword)
      # @param backup_fuel [String] secondary boiler fuel (defaults to primary)
      # @param reuse [Boolean] return an existing boiler loop when present (default true)
      # @param source [String] 'boiler' (default) or 'district' (DistrictHeating object
      #   instead of boilers — the CBECS 'district hot water' pattern)
      # @return [OpenStudio::Model::PlantLoop]
      def self.hot_water(model, fuel: 'NaturalGas', backup_fuel: nil, reuse: true, source: 'boiler')
        if reuse
          existing = find_hot_water(model)
          existing ||= model.getPlantLoops.find { |pl| pl.nameString == 'Hot Water Loop' }
          return existing unless existing.nil?
        end

        backup_fuel ||= fuel
        hw_loop = OpenStudio::Model::PlantLoop.new(model)
        hw_loop.setName('Hot Water Loop')
        sizing_plant = hw_loop.sizingPlant
        sizing_plant.setLoopType('Heating')
        sizing_plant.setDesignLoopExitTemperature(82.0)
        sizing_plant.setLoopDesignTemperatureDifference(16.0)

        # Variable speed (legacy note: constant-speed showed run-away plant temperatures)
        pump = OpenStudio::Model::PumpVariableSpeed.new(model)
        pump.addToNode(hw_loop.supplyInletNode)

        if source == 'district'
          district = if model.version < OpenStudio::VersionString.new('3.7.0')
                       OpenStudio::Model::DistrictHeating.new(model)
                     else
                       OpenStudio::Model::DistrictHeatingWater.new(model)
                     end
          district.setName('District Hot Water')
          hw_loop.addSupplyBranchForComponent(district)
        else
          boiler1 = OpenStudio::Model::BoilerHotWater.new(model)
          boiler2 = OpenStudio::Model::BoilerHotWater.new(model)
          boiler1.setFuelType(fuel)
          boiler2.setFuelType(backup_fuel)
          # Names are load-bearing downstream (NECB boiler efficiency rules match on them).
          boiler1.setName('Primary Boiler')
          boiler2.setName('Secondary Boiler')
          hw_loop.addSupplyBranchForComponent(boiler1)
          hw_loop.addSupplyBranchForComponent(boiler2)
        end

        hw_loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(hw_loop.supplyOutletNode)

        stpt = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
        stpt.setControlVariable('Temperature')
        stpt.setSetpointatOutdoorLowTemperature(82.0)
        stpt.setOutdoorLowTemperature(-16.0)
        stpt.setSetpointatOutdoorHighTemperature(60.0)
        stpt.setOutdoorHighTemperature(0.0)
        stpt.addToNode(hw_loop.supplyOutletNode)

        hw_loop
      end

      # Find an existing chilled-water loop (one with a chiller on the supply side), or nil.
      def self.find_chilled_water(model)
        model.getPlantLoops.find do |pl|
          pl.supplyComponents(OpenStudio::Model::ChillerElectricEIR.iddObjectType).any?
        end
      end

      # Build a chilled-water loop (7C exit / 6K dT, variable-speed pump, primary + secondary
      # water-cooled chillers, constant 7C setpoint) AND its condenser-water loop (29C / 6K,
      # single-speed cooling tower 24/35/5/6 design temps, constant 29C setpoint), ported from
      # NECB setup_chw_loop_with_components / setup_cw_loop_with_components.
      #
      # @param model [OpenStudio::Model::Model]
      # @param chiller_type [String] 'Scroll', 'Centrifugal', 'Rotary Screw', 'Reciprocating'
      #   (embedded in the chiller names, which host efficiency rules key on)
      # @param reuse [Boolean] return an existing chiller loop when present (default true)
      # @return [OpenStudio::Model::PlantLoop] the chilled-water loop
      def self.chilled_water(model, chiller_type: 'Scroll', reuse: true)
        if reuse
          existing = find_chilled_water(model)
          return existing unless existing.nil?
        end

        # --- chilled water ---
        chw_loop = OpenStudio::Model::PlantLoop.new(model)
        chw_loop.setName('Chilled Water Loop')
        sizing_plant = chw_loop.sizingPlant
        sizing_plant.setLoopType('Cooling')
        sizing_plant.setDesignLoopExitTemperature(7.0)
        sizing_plant.setLoopDesignTemperatureDifference(6.0)

        chw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)

        chiller1 = OpenStudio::Model::ChillerElectricEIR.new(model)
        chiller2 = OpenStudio::Model::ChillerElectricEIR.new(model)
        chiller1.setCondenserType('WaterCooled')
        chiller2.setCondenserType('WaterCooled')
        # Names are load-bearing downstream (NECB chiller efficiency rules match on them).
        chiller1.setName("Primary Chiller WaterCooled #{chiller_type}".strip)
        chiller2.setName("Secondary Chiller WaterCooled #{chiller_type}".strip)

        chw_pump.addToNode(chw_loop.supplyInletNode)
        chw_loop.addSupplyBranchForComponent(chiller1)
        chw_loop.addSupplyBranchForComponent(chiller2)
        chw_loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(chw_loop.supplyOutletNode)

        chw_stpt = OpenStudio::Model::SetpointManagerScheduled.new(
          model, Schedules.constant_ruleset(model, 'CHW Temp', 7.0)
        )
        chw_stpt.addToNode(chw_loop.supplyOutletNode)

        # --- condenser water ---
        cw_loop = OpenStudio::Model::PlantLoop.new(model)
        cw_loop.setName('Condenser Water Loop')
        cw_sizing = cw_loop.sizingPlant
        cw_sizing.setLoopType('Condenser')
        cw_sizing.setDesignLoopExitTemperature(29.0)
        cw_sizing.setLoopDesignTemperatureDifference(6.0)

        cw_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
        clg_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)
        clg_tower.setDesignInletAirWetBulbTemperature(24.0)
        clg_tower.setDesignInletAirDryBulbTemperature(35.0)
        clg_tower.setDesignApproachTemperature(5.0)
        clg_tower.setDesignRangeTemperature(6.0)

        cw_pump.addToNode(cw_loop.supplyInletNode)
        cw_loop.addSupplyBranchForComponent(clg_tower)
        cw_loop.addSupplyBranchForComponent(OpenStudio::Model::PipeAdiabatic.new(model))
        OpenStudio::Model::PipeAdiabatic.new(model).addToNode(cw_loop.supplyOutletNode)
        cw_loop.addDemandBranchForComponent(chiller1)
        cw_loop.addDemandBranchForComponent(chiller2)

        cw_stpt = OpenStudio::Model::SetpointManagerScheduled.new(
          model, Schedules.constant_ruleset(model, 'CW Temp', 29.0)
        )
        cw_stpt.addToNode(cw_loop.supplyOutletNode)

        chw_loop
      end
    end
  end
end
