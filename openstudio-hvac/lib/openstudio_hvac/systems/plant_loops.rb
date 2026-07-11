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
      # @return [OpenStudio::Model::PlantLoop]
      def self.hot_water(model, fuel: 'NaturalGas', backup_fuel: nil, reuse: true)
        if reuse
          existing = find_hot_water(model)
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

        boiler1 = OpenStudio::Model::BoilerHotWater.new(model)
        boiler2 = OpenStudio::Model::BoilerHotWater.new(model)
        boiler1.setFuelType(fuel)
        boiler2.setFuelType(backup_fuel)
        # Names are load-bearing downstream (NECB boiler efficiency rules match on them).
        boiler1.setName('Primary Boiler')
        boiler2.setName('Secondary Boiler')

        boiler_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)
        supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

        pump.addToNode(hw_loop.supplyInletNode)
        hw_loop.addSupplyBranchForComponent(boiler1)
        hw_loop.addSupplyBranchForComponent(boiler2)
        hw_loop.addSupplyBranchForComponent(boiler_bypass_pipe)
        supply_outlet_pipe.addToNode(hw_loop.supplyOutletNode)

        stpt = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
        stpt.setControlVariable('Temperature')
        stpt.setSetpointatOutdoorLowTemperature(82.0)
        stpt.setOutdoorLowTemperature(-16.0)
        stpt.setSetpointatOutdoorHighTemperature(60.0)
        stpt.setOutdoorHighTemperature(0.0)
        stpt.addToNode(hw_loop.supplyOutletNode)

        hw_loop
      end
    end
  end
end
