module OpenStudioHVAC
  module Systems
    # Shared behavior for system builders: sizing-block application helpers.
    # Subclass contract: `build(model, zones, control_zone:, namer:)` returning
    # the Array of AirLoopHVACs created.
    class BaseSystem
      attr_reader :config

      # @param config [Hash] a resolved catalog row (string keys; 'sizing' is a Hash)
      def initialize(config)
        @config = config
      end

      def sizing
        config['sizing'] || {}
      end

      # Apply the sizing block's air-loop-level fields to a Sizing:System object.
      # Ported from openstudio-standards common_air_loop.
      def apply_system_sizing(air_loop)
        s = air_loop.sizingSystem
        s.autosizeDesignOutdoorAirFlowRate
        z = sizing
        s.setPreheatDesignTemperature(z['preheat_design_temperature']) if z['preheat_design_temperature']
        s.setPreheatDesignHumidityRatio(z['preheat_design_humidity_ratio']) if z['preheat_design_humidity_ratio']
        s.setPrecoolDesignTemperature(z['precool_design_temperature']) if z['precool_design_temperature']
        s.setPrecoolDesignHumidityRatio(z['precool_design_humidity_ratio']) if z['precool_design_humidity_ratio']
        s.setSizingOption(z['sizing_option']) if z['sizing_option']
        s.setCoolingDesignAirFlowMethod(z['cooling_design_air_flow_method']) if z['cooling_design_air_flow_method']
        s.setCoolingDesignAirFlowRate(z['cooling_design_air_flow_rate']) if z['cooling_design_air_flow_rate']
        s.setHeatingDesignAirFlowMethod(z['heating_design_air_flow_method']) if z['heating_design_air_flow_method']
        s.setHeatingDesignAirFlowRate(z['heating_design_air_flow_rate']) if z['heating_design_air_flow_rate']
        s.setSystemOutdoorAirMethod(z['system_outdoor_air_method']) if z['system_outdoor_air_method']
        if z['central_cooling_design_supply_air_humidity_ratio']
          s.setCentralCoolingDesignSupplyAirHumidityRatio(z['central_cooling_design_supply_air_humidity_ratio'])
        end
        if z['central_heating_design_supply_air_humidity_ratio']
          s.setCentralHeatingDesignSupplyAirHumidityRatio(z['central_heating_design_supply_air_humidity_ratio'])
        end
        s.setTypeofLoadtoSizeOn(z['type_of_load_to_size_on']) if z['type_of_load_to_size_on']
        if z['central_cooling_design_supply_air_temperature']
          s.setCentralCoolingDesignSupplyAirTemperature(z['central_cooling_design_supply_air_temperature'])
        end
        if z['central_heating_design_supply_air_temperature']
          s.setCentralHeatingDesignSupplyAirTemperature(z['central_heating_design_supply_air_temperature'])
        end
        s.setAllOutdoorAirinCooling(z['all_outdoor_air_in_cooling']) unless z['all_outdoor_air_in_cooling'].nil?
        s.setAllOutdoorAirinHeating(z['all_outdoor_air_in_heating']) unless z['all_outdoor_air_in_heating'].nil?
        if z['minimum_system_air_flow_ratio']
          s.setCentralHeatingMaximumSystemAirFlowRatio(z['minimum_system_air_flow_ratio'])
        end
        s
      end

      # Apply the sizing block's zone-level fields: either the TemperatureDifference method
      # (NECB reference systems) or absolute supply temperatures (ECM systems), plus factors.
      def apply_zone_sizing(zone)
        sz = zone.sizingZone
        z = sizing
        if z['zone_cooling_design_supply_air_temperature']
          sz.setZoneCoolingDesignSupplyAirTemperature(z['zone_cooling_design_supply_air_temperature'])
        end
        if z['zone_heating_design_supply_air_temperature']
          sz.setZoneHeatingDesignSupplyAirTemperature(z['zone_heating_design_supply_air_temperature'])
        end
        if z['zone_cooling_design_supply_air_temperature_input_method']
          sz.setZoneCoolingDesignSupplyAirTemperatureInputMethod(z['zone_cooling_design_supply_air_temperature_input_method'])
        end
        if z['zone_cooling_design_supply_air_temperature_difference']
          sz.setZoneCoolingDesignSupplyAirTemperatureDifference(z['zone_cooling_design_supply_air_temperature_difference'])
        end
        if z['zone_heating_design_supply_air_temperature_input_method']
          sz.setZoneHeatingDesignSupplyAirTemperatureInputMethod(z['zone_heating_design_supply_air_temperature_input_method'])
        end
        if z['zone_heating_design_supply_air_temperature_difference']
          sz.setZoneHeatingDesignSupplyAirTemperatureDifference(z['zone_heating_design_supply_air_temperature_difference'])
        end
        sz.setZoneCoolingSizingFactor(z['zone_cooling_sizing_factor']) if z['zone_cooling_sizing_factor']
        sz.setZoneHeatingSizingFactor(z['zone_heating_sizing_factor']) if z['zone_heating_sizing_factor']
        apply_doas_zone_sizing(sz, z)
        sz
      end

      # 8.4.4.9.(3)/8.4.4.10.(7) (2025: 8.4.5.x) terminal/secondary capacity
      # split, D-50. Where the selection table puts heating (or cooling) in BOTH
      # a zone terminal and a make-up-air secondary system, the terminal is sized
      # for the space loads and the ventilation air is carried at system level.
      # EnergyPlus expresses exactly that as Sizing:Zone dedicated-outdoor-air
      # accounting with a NEUTRAL supply-air strategy: the DOAS stream neither
      # adds nor removes zone load, so the terminal's design load is the
      # envelope(-and-internal) load alone.
      #
      # The low/high setpoint pair must be strictly increasing (EnergyPlus
      # rejects low >= high with a Severe), hence the 0.1 degC spread — the same
      # convention the make-up-air sizing block already uses for its own
      # setpoint pair.
      def apply_doas_zone_sizing(sizing_zone, z)
        return unless z['account_for_dedicated_outdoor_air_system']

        sizing_zone.setAccountforDedicatedOutdoorAirSystem(true)
        if z['dedicated_outdoor_air_system_control_strategy']
          sizing_zone.setDedicatedOutdoorAirSystemControlStrategy(z['dedicated_outdoor_air_system_control_strategy'])
        end
        if z['dedicated_outdoor_air_low_setpoint_temperature_for_design']
          sizing_zone.setDedicatedOutdoorAirLowSetpointTemperatureforDesign(
            z['dedicated_outdoor_air_low_setpoint_temperature_for_design']
          )
        end
        return unless z['dedicated_outdoor_air_high_setpoint_temperature_for_design']

        sizing_zone.setDedicatedOutdoorAirHighSetpointTemperatureforDesign(
          z['dedicated_outdoor_air_high_setpoint_temperature_for_design']
        )
      end

      # ZoneSum outdoor-air controller with autosized minimum OA (the NECB convention).
      def build_oa_system(model)
        oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
        oa_controller.autosizeMinimumOutdoorAirFlowRate
        oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('ZoneSum')
        OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller)
      end
    end
  end
end
