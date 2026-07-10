module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Helpers
    # Helper methods to remove HVAC equipment, rename nodes, and rename HVAC equipment

    # Remove all air loops in model
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_air_loops(model)
      model.getAirLoopHVACs.each(&:remove)

      return model
    end

    # Remove plant loops in model except those used for service hot water
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_plant_loops(model)
      plant_loops = model.getPlantLoops
      plant_loops.each do |plant_loop|
        shw_use = false
        plant_loop.demandComponents.each do |component|
          if component.to_WaterUseConnections.is_initialized || component.to_CoilWaterHeatingDesuperheater.is_initialized
            shw_use = true
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "#{plant_loop.name} is used for SHW or refrigeration heat reclaim and will not be removed.")
            break
          end
        end
        plant_loop.remove unless shw_use
      end

      return model
    end

    # Remove all plant loops in model including those used for service hot water
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_all_plant_loops(model)
      model.getPlantLoops.each(&:remove)

      return model
    end

    # Remove VRF units
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_vrf(model)
      model.getAirConditionerVariableRefrigerantFlows.each(&:remove)
      model.getZoneHVACTerminalUnitVariableRefrigerantFlows.each(&:remove)

      return model
    end

    # Remove zone equipment except for exhaust fans
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_zone_equipment(model)
      model.getThermalZones.each do |zone|
        zone.equipment.each do |equipment|
          if equipment.to_FanZoneExhaust.is_initialized
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "#{equipment.name} is a zone exhaust fan and will not be removed.")
          else
            equipment.remove
          end
        end
      end

      return model
    end

    # Remove all zone equipment including exhaust fans
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_all_zone_equipment(model)
      model.getThermalZones.each do |zone|
        zone.equipment.each(&:remove)
      end

      return model
    end

    # Remove unused performance curves
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_unused_curves(model)
      model.getCurves.each do |curve|
        if curve.directUseCount == 0
          model.removeObject(curve.handle)
        end
      end

      return model
    end

    # Remove HVAC equipment except for service hot water loops and zone exhaust fans
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_hvac(model)
      OpenstudioStandards::HVAC.remove_air_loops(model)
      OpenstudioStandards::HVAC.remove_plant_loops(model)
      OpenstudioStandards::HVAC.remove_vrf(model)
      OpenstudioStandards::HVAC.remove_zone_equipment(model)
      OpenstudioStandards::HVAC.remove_unused_curves(model)

      return model
    end

    # Remove all HVAC equipment including service hot water loops and zone exhaust fans
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_all_hvac(model)
      OpenstudioStandards::HVAC.remove_air_loops(model)
      OpenstudioStandards::HVAC.remove_all_plant_loops(model)
      OpenstudioStandards::HVAC.remove_vrf(model)
      OpenstudioStandards::HVAC.remove_all_zone_equipment(model)
      OpenstudioStandards::HVAC.remove_unused_curves(model)

      return model
    end

    # Remove HVAC serving only the given thermal zones, leaving the rest of the model untouched.
    # Removes the zones' zone equipment (except exhaust fans), removes air loops that serve only
    # the given zones (and detaches the given zones from air loops shared with other zones), and
    # removes any plant loop left with no demand-side equipment (keeping service-hot-water loops).
    # Use this to replace (rather than stack on top of) an existing system on a subset of zones.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param zones [Array<OpenStudio::Model::ThermalZone>] thermal zones to clear of HVAC
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.remove_hvac_from_zones(model, zones)
      zone_handles = zones.map { |zone| zone.handle.to_s }

      # 1. Zone equipment on the given zones (baseboards, PTAC/PTHP, fan coils, VRF terminals, ...)
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

      # 3. Remove plant loops orphaned by the above (no demand-side equipment left), keeping SHW.
      #    Iterate to a fixpoint: a water-cooled chiller straddles its chilled-water loop (supply)
      #    and condenser loop (demand), so removing the chilled-water loop only strands the chiller;
      #    removing the stranded chiller then frees the condenser loop on the next pass.
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

        # A chiller no longer connected to a chilled-water (supply) loop is stranded; remove it so
        # its condenser loop can be reclaimed on the next pass.
        model.getChillerElectricEIRs.each do |chiller|
          next unless chiller.plantLoop.empty?

          chiller.remove
          changed = true
        end

        break unless changed
      end

      OpenstudioStandards::HVAC.remove_unused_curves(model)

      return model
    end

    # renames air loop nodes to readable values
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.rename_air_loop_nodes(model)
      # rename all hvac components on air loops
      model.getHVACComponents.sort.each do |component|
        next if component.to_Node.is_initialized # skip nodes

        unless component.airLoopHVAC.empty?
          # rename water to air component outlet nodes
          if component.to_WaterToAirComponent.is_initialized
            component = component.to_WaterToAirComponent.get
            unless component.airOutletModelObject.empty?
              component_outlet_object = component.airOutletModelObject.get
              next unless component_outlet_object.to_Node.is_initialized

              component_outlet_object.setName("#{component.name} Outlet Air Node")
            end
          end

          # rename air to air component nodes
          if component.to_AirToAirComponent.is_initialized
            component = component.to_AirToAirComponent.get
            unless component.primaryAirOutletModelObject.empty?
              component_outlet_object = component.primaryAirOutletModelObject.get
              next unless component_outlet_object.to_Node.is_initialized

              component_outlet_object.setName("#{component.name} Primary Outlet Air Node")
            end
            unless component.secondaryAirInletModelObject.empty?
              component_inlet_object = component.secondaryAirInletModelObject.get
              next unless component_inlet_object.to_Node.is_initialized

              component_inlet_object.setName("#{component.name} Secondary Inlet Air Node")
            end
          end

          # rename straight component outlet nodes
          if component.to_StraightComponent.is_initialized && !component.to_StraightComponent.get.outletModelObject.empty?
            component_outlet_object = component.to_StraightComponent.get.outletModelObject.get
            next unless component_outlet_object.to_Node.is_initialized

            component_outlet_object.setName("#{component.name} Outlet Air Node")
          end
        end

        # rename zone hvac component nodes
        if component.to_ZoneHVACComponent.is_initialized
          component = component.to_ZoneHVACComponent.get
          unless component.airInletModelObject.empty?
            component_inlet_object = component.airInletModelObject.get
            next unless component_inlet_object.to_Node.is_initialized

            component_inlet_object.setName("#{component.name} Inlet Air Node")
          end
          unless component.airOutletModelObject.empty?
            component_outlet_object = component.airOutletModelObject.get
            next unless component_outlet_object.to_Node.is_initialized

            component_outlet_object.setName("#{component.name} Outlet Air Node")
          end
        end
      end

      # rename supply side nodes
      model.getAirLoopHVACs.sort.each do |air_loop|
        air_loop_name = air_loop.name.to_s
        air_loop.demandInletNode.setName("#{air_loop_name} Demand Inlet Node")
        air_loop.demandOutletNode.setName("#{air_loop_name} Demand Outlet Node")
        air_loop.supplyInletNode.setName("#{air_loop_name} Supply Inlet Node")
        air_loop.supplyOutletNode.setName("#{air_loop_name} Supply Outlet Node")

        unless air_loop.reliefAirNode.empty?
          relief_node = air_loop.reliefAirNode.get
          relief_node.setName("#{air_loop_name} Relief Air Node")
        end

        unless air_loop.mixedAirNode.empty?
          mixed_node = air_loop.mixedAirNode.get
          mixed_node.setName("#{air_loop_name} Mixed Air Node")
        end

        # rename outdoor air system and nodes
        unless air_loop.airLoopHVACOutdoorAirSystem.empty?
          oa_system = air_loop.airLoopHVACOutdoorAirSystem.get
          unless oa_system.outboardOANode.empty?
            oa_node = oa_system.outboardOANode.get
            oa_node.setName("#{air_loop_name} Outdoor Air Node")
          end
        end
      end

      # rename zone air and terminal nodes
      model.getThermalZones.sort.each do |zone|
        zone.zoneAirNode.setName("#{zone.name} Zone Air Node")

        unless zone.returnAirModelObject.empty?
          zone.returnAirModelObject.get.setName("#{zone.name} Return Air Node")
        end

        unless zone.airLoopHVACTerminal.empty?
          terminal_unit = zone.airLoopHVACTerminal.get
          if terminal_unit.to_StraightComponent.is_initialized
            component = terminal_unit.to_StraightComponent.get
            component.inletModelObject.get.setName("#{terminal_unit.name} Inlet Air Node")
          end
        end
      end

      # rename zone equipment list objects
      model.getZoneHVACEquipmentLists.sort.each do |obj|
        begin
          zone = obj.thermalZone
          obj.setName("#{zone.name} Zone HVAC Equipment List")
        rescue StandardError => e
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.model.Model', "Removing ZoneHVACEquipmentList #{obj.name}; missing thermal zone.")
          obj.remove
        end
      end

      return model
    end

    # renames plant loop nodes to readable values
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::Model] OpenStudio model object
    def self.rename_plant_loop_nodes(model)
      # rename all hvac components on plant loops
      model.getHVACComponents.sort.each do |component|
        next if component.to_Node.is_initialized # skip nodes

        unless component.plantLoop.empty?
          # rename straight component nodes
          # some inlet or outlet nodes may get renamed again
          if component.to_StraightComponent.is_initialized
            unless component.to_StraightComponent.get.inletModelObject.empty?
              component_inlet_object = component.to_StraightComponent.get.inletModelObject.get
              next unless component_inlet_object.to_Node.is_initialized

              component_inlet_object.setName("#{component.name} Inlet Water Node")
            end
            unless component.to_StraightComponent.get.outletModelObject.empty?
              component_outlet_object = component.to_StraightComponent.get.outletModelObject.get
              next unless component_outlet_object.to_Node.is_initialized

              component_outlet_object.setName("#{component.name} Outlet Water Node")
            end
          end

          # rename water to air component nodes
          if component.to_WaterToAirComponent.is_initialized
            component = component.to_WaterToAirComponent.get
            unless component.waterInletModelObject.empty?
              component_inlet_object = component.waterInletModelObject.get
              next unless component_inlet_object.to_Node.is_initialized

              component_inlet_object.setName("#{component.name} Inlet Water Node")
            end
            unless component.waterOutletModelObject.empty?
              component_outlet_object = component.waterOutletModelObject.get
              next unless component_outlet_object.to_Node.is_initialized

              component_outlet_object.setName("#{component.name} Outlet Water Node")
            end
          end

          # rename water to water component nodes
          if component.to_WaterToWaterComponent.is_initialized
            component = component.to_WaterToWaterComponent.get
            unless component.demandInletModelObject.empty?
              demand_inlet_object = component.demandInletModelObject.get
              next unless demand_inlet_object.to_Node.is_initialized

              demand_inlet_object.setName("#{component.name} Demand Inlet Water Node")
            end
            unless component.demandOutletModelObject.empty?
              demand_outlet_object = component.demandOutletModelObject.get
              next unless demand_outlet_object.to_Node.is_initialized

              demand_outlet_object.setName("#{component.name} Demand Outlet Water Node")
            end
            unless component.supplyInletModelObject.empty?
              supply_inlet_object = component.supplyInletModelObject.get
              next unless supply_inlet_object.to_Node.is_initialized

              supply_inlet_object.setName("#{component.name} Supply Inlet Water Node")
            end
            unless component.supplyOutletModelObject.empty?
              supply_outlet_object = component.supplyOutletModelObject.get
              next unless supply_outlet_object.to_Node.is_initialized

              supply_outlet_object.setName("#{component.name} Supply Outlet Water Node")
            end
          end
        end
      end

      # rename plant nodes
      model.getPlantLoops.sort.each do |plant_loop|
        plant_loop_name = plant_loop.name.to_s
        plant_loop.demandInletNode.setName("#{plant_loop_name} Demand Inlet Node")
        plant_loop.demandOutletNode.setName("#{plant_loop_name} Demand Outlet Node")
        plant_loop.supplyInletNode.setName("#{plant_loop_name} Supply Inlet Node")
        plant_loop.supplyOutletNode.setName("#{plant_loop_name} Supply Outlet Node")
      end

      return model
    end

    # converts existing string to ems friendly string
    #
    # @param name [String] original name
    # @return [String] the resulting EMS friendly string
    def self.ems_friendly_name(name)
      # replace white space and special characters with underscore
      # \W is equivalent to [^a-zA-Z0-9_]
      new_name = name.to_s.gsub(/\W/, '_')

      # prepend ems_ in case the name starts with a number
      new_name = "ems_#{new_name}"

      return new_name
    end
  end
end
