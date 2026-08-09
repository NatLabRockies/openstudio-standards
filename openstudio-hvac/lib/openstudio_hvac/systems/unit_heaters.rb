module OpenStudioHVAC
  module Systems
    # Per-zone unit heaters (port of the generic model_add_unitheater essentials):
    # constant-volume fan + gas/electric/hot-water heating coil, no cooling.
    class UnitHeaters < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        heating_type = config.fetch('heating_type', 'Gas')
        always_on = model.alwaysOnDiscreteSchedule

        zones.sort_by(&:nameString).each do |zone|
          fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
          fan.setName("#{zone.nameString} Unit Heater Fan")
          fan.setPressureRise(OpenStudio.convert(0.2, 'inH_{2}O', 'Pa').get)

          htg_coil = Coils.heating_coil(model, heating_type, always_on, hw_loop: hw_loop)
          htg_coil.setName("#{zone.nameString} Unit Heater Coil")

          heater = OpenStudio::Model::ZoneHVACUnitHeater.new(model, always_on, fan, htg_coil)
          heater.setName("#{zone.nameString} Unit Heater")
          heater.setFanControlType('OnOff')
          heater.addToThermalZone(zone)
        end
        []
      end
    end
  end
end
