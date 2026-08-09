module OpenStudioHVAC
  module Systems
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
  end
end
