module OpenStudioHVAC
  module Systems
    # Self-ventilating per-zone terminal units (port of the generic prototype
    # model_add_ptac / model_add_pthp / model_add_window_ac topologies used by CBECS).
    # Unlike the NECB MAU+PTAC pattern, these units provide their own outdoor air —
    # there is no central ventilation loop.
    #
    # config 'unit_type':
    # - 'ptac'      : PTAC, single-speed DX cooling, heating per 'heating_type'
    #                 (nil/'None' = always-off zero-capacity electric section — the CBECS
    #                 "PTAC with baseboard X" pattern where baseboards do the heating),
    #                 'Electric', or 'Water' (hw_loop)
    # - 'pthp'      : PTHP, DX heat + DX cool + electric supplemental
    # - 'window_ac' : cooling-only PTAC at EER 8.5 with a zero-capacity heat section
    # config 'baseboard_type': adds zone baseboards ('Electric'/'Hot Water'/'None')
    class ZoneTerminal < BaseSystem
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] empty (no central air system)
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        unit_type = config.fetch('unit_type', 'ptac')
        heating_type = config.fetch('heating_type', 'None')
        baseboard_type = config.fetch('baseboard_type', 'None')

        zones.sort_by(&:nameString).each do |zone|
          apply_zone_sizing(zone)
          sz = zone.sizingZone
          # 0.008 kg/kg design supply humidity ratios: legacy parity with the prototype
          # zone-terminal creators — model_add_ptac (Prototype.hvac_systems.rb:4067-4068)
          # and model_add_pthp (:4179-4180) set the same pair (also the common E+ sizing
          # default neighbourhood; legacy carries it bare).
          sz.setZoneCoolingDesignSupplyAirHumidityRatio(0.008)
          sz.setZoneHeatingDesignSupplyAirHumidityRatio(0.008)

          case unit_type
          when 'ptac'      then add_ptac(model, zone, heating_type, hw_loop)
          when 'pthp'      then add_pthp(model, zone)
          when 'window_ac' then add_window_ac(model, zone)
          else raise(ArgumentError, "unknown zone terminal unit_type '#{unit_type}'")
          end

          Baseboards.add(model, zone, baseboard_type: baseboard_type, hw_loop: hw_loop)
        end
        []
      end

      private

      def no_heat_coil(model, zone)
        coil = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOffDiscreteSchedule)
        coil.setName("#{zone.nameString} PTAC No Heat")
        coil.setNominalCapacity(0.0)
        coil
      end

      def cycling_fan(model, zone, label)
        fan = OpenStudio::Model::FanOnOff.new(model)
        fan.setName("#{zone.nameString} #{label} Fan")
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
        fan
      end

      def add_ptac(model, zone, heating_type, hw_loop)
        always_on = model.alwaysOnDiscreteSchedule
        htg_coil =
          case heating_type
          when 'None', nil then no_heat_coil(model, zone)
          when 'Electric', 'Electricity'
            coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
            coil.setName("#{zone.nameString} PTAC Electric Htg Coil")
            coil
          when 'Water', 'Hot Water'
            raise(ArgumentError, 'a hot water loop is required for a Water PTAC coil') if hw_loop.nil?

            coil = OpenStudio::Model::CoilHeatingWater.new(model, always_on)
            coil.setName("#{zone.nameString} PTAC Water Htg Coil")
            hw_loop.addDemandBranchForComponent(coil)
            coil
          else
            raise(ArgumentError, "'#{heating_type}' is not a valid PTAC heating type")
          end

        clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
        clg_coil.setName("#{zone.nameString} PTAC 1spd DX AC Clg Coil")

        ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(
          model, always_on, cycling_fan(model, zone, 'PTAC'), htg_coil, clg_coil
        )
        ptac.setName("#{zone.nameString} PTAC")
        ptac.addToThermalZone(zone)   # ventilation: default OA (self-ventilating)
        ptac
      end

      def add_pthp(model, zone)
        always_on = model.alwaysOnDiscreteSchedule
        htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
        htg_coil.setName("#{zone.nameString} PTHP Htg Coil")
        clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
        clg_coil.setName("#{zone.nameString} PTHP Clg Coil")
        supp_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
        supp_coil.setName("#{zone.nameString} PTHP Supp Htg Coil")

        pthp = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(
          model, always_on, cycling_fan(model, zone, 'PTHP'), htg_coil, clg_coil, supp_coil
        )
        pthp.setName("#{zone.nameString} PTHP")
        pthp.addToThermalZone(zone)
        pthp
      end

      WINDOW_AC_EER = 8.5 # Btu/W-h (generic model_add_window_ac default)

      def add_window_ac(model, zone)
        always_on = model.alwaysOnDiscreteSchedule
        clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
        clg_coil.setName("#{zone.nameString} Window AC Clg Coil")
        clg_coil.setRatedCOP(OpenStudio.convert(WINDOW_AC_EER, 'Btu/h', 'W').get)

        ac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(
          model, always_on, cycling_fan(model, zone, 'Window AC'), no_heat_coil(model, zone), clg_coil
        )
        ac.setName("#{zone.nameString} Window AC")
        ac.addToThermalZone(zone)
        ac
      end
    end
  end
end
