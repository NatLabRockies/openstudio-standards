module OpenStudioHVAC
  # Zone-scoped HVAC removal: clear the given zones so a new system replaces (rather than
  # stacks on top of) whatever served them, leaving other zones' systems untouched.
  # Ported from the openstudio-standards remove_hvac_from_zones work, including the
  # fixpoint that handles water-cooled chiller -> condenser-loop chains.
  module Teardown
    # @param model [OpenStudio::Model::Model]
    # @param zones [Array<OpenStudio::Model::ThermalZone>] zones to clear of HVAC
    # @return [OpenStudio::Model::Model]
    def self.remove_hvac_from_zones(model, zones)
      zone_handles = zones.map { |zone| zone.handle.to_s }

      # 1. Zone equipment on the given zones (baseboards, PTAC/PTHP, fan coils, VRF terminals...)
      #    Exhaust fans are preserved (they represent code-required exhaust, not the system).
      zones.each do |zone|
        zone.equipment.each do |equipment|
          next if equipment.to_FanZoneExhaust.is_initialized

          equipment.remove
        end
      end

      # 2. Air loops serving the given zones: remove entirely if they serve only these zones,
      #    otherwise detach just the given zones from the shared loop.
      model.getAirLoopHVACs.each do |air_loop|
        served = air_loop.thermalZones
        next if (served.map { |z| z.handle.to_s } & zone_handles).empty?

        if served.all? { |z| zone_handles.include?(z.handle.to_s) }
          air_loop.remove
        else
          served.each { |z| air_loop.removeBranchForZone(z) if zone_handles.include?(z.handle.to_s) }
        end
      end

      # 3. Remove plant loops orphaned by the above (no demand-side equipment left), keeping
      #    service-hot-water loops. Iterate to a fixpoint: a water-cooled chiller straddles its
      #    chilled-water loop (supply) and condenser loop (demand), so removing the chilled-water
      #    loop only strands the chiller; removing the stranded chiller then frees the condenser
      #    loop on the next pass.
      loop do
        changed = false

        model.getPlantLoops.each do |plant_loop|
          shw_use = plant_loop.demandComponents.any? do |component|
            component.to_WaterUseConnections.is_initialized || component.to_CoilWaterHeatingDesuperheater.is_initialized
          end
          next if shw_use

          demand_equipment = plant_loop.demandComponents.reject do |component|
            component.to_Node.is_initialized ||
              component.to_ConnectorMixer.is_initialized ||
              component.to_ConnectorSplitter.is_initialized ||
              component.to_PipeAdiabatic.is_initialized ||
              component.to_PipeIndoor.is_initialized ||
              component.to_PipeOutdoor.is_initialized
          end
          next unless demand_equipment.empty?

          plant_loop.remove
          changed = true
        end

        model.getChillerElectricEIRs.each do |chiller|
          next unless chiller.plantLoop.empty?

          chiller.remove
          changed = true
        end

        break unless changed
      end

      # 4. Remove now-unused performance curves.
      model.getCurves.each do |curve|
        model.removeObject(curve.handle) if curve.directUseCount.zero?
      end

      model
    end
  end
end
