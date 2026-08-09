module OpenStudioHVAC
  module Systems
    # VRF: outdoor VRF unit + per-zone terminal units (the CBECS 'VRF' name). Standalone
    # 'VRF' lets terminals ventilate (default OA); in 'DOAS with VRF' composites the
    # terminals' OA is zeroed (config 'zone_ventilation': false) and the DOAS ventilates.
    class Vrf < BaseSystem
      def build(model, zones, control_zone: nil, namer: :default, hw_loop: nil, chw_loop: nil)
        outdoor_unit = EcmAir.add_outdoor_vrf_unit(model)
        vent = config.fetch('zone_ventilation', true)
        zones.sort_by(&:nameString).each do |zone|
          terminal = EcmAir.add_zone_vrf_terminal(model, zone, outdoor_unit)
          next unless vent

          # restore default (autosized) OA on the terminal for the self-ventilating case
          terminal.autosizeOutdoorAirFlowRateDuringCoolingOperation
          terminal.autosizeOutdoorAirFlowRateDuringHeatingOperation
          terminal.autosizeOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded
        end
        []
      end
    end
  end
end
