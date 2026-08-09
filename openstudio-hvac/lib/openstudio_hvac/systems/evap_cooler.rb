module OpenStudioHVAC
  module Systems
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
          # 90% design effectiveness, per legacy model_add_evap_cooler
          # (Prototype.hvac_systems.rb:4501), which cites
          # https://basc.pnnl.gov/resource-guides/evaporative-cooling-systems#edit-group-description
          evap.setCoolerDesignEffectiveness(0.90)

          supply_inlet_node = air_loop.supplyInletNode
          fan.addToNode(supply_inlet_node)
          evap.addToNode(supply_inlet_node)
          build_oa_system(model).addToNode(supply_inlet_node)

          # Supply setpoint follows the outdoor WET BULB plus a 3 R wet-bulb approach,
          # clamped to the legacy evap-cooler design supply temperatures of 70 F
          # (minimum) and 78 F (maximum). Mirrors legacy model_add_evap_cooler
          # (Prototype.hvac_systems.rb:4427-4432 for the temperatures, :4451-4457 for the
          # setpoint manager); the conversions are the same OpenStudio.convert calls the
          # legacy code makes, so the SI field values are bit-identical
          # (21.111111111111143 / 25.5555555555556 C, 1.6666666666666667 K).
          clg_dsgn_sup_air_temp_c = OpenStudio.convert(70.0, 'F', 'C').get
          max_clg_dsgn_sup_air_temp_c = OpenStudio.convert(78.0, 'F', 'C').get
          approach_k = OpenStudio.convert(3.0, 'R', 'K').get
          spm = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(model)
          spm.setReferenceTemperatureType('OutdoorAirWetBulb')
          spm.setMaximumSetpointTemperature(max_clg_dsgn_sup_air_temp_c)
          spm.setMinimumSetpointTemperature(clg_dsgn_sup_air_temp_c)
          spm.setOffsetTemperatureDifference(approach_k)
          spm.addToNode(air_loop.supplyOutletNode)

          diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
          air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
          air_loop
        end
      end
    end
  end
end
