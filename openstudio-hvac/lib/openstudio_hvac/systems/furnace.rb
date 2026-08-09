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
  end
end
