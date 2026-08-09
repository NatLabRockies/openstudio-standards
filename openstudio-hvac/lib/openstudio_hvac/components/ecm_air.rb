module OpenStudioHVAC
  # Shared machinery for the NECB ECM air systems (port of the ECMS create_airloop /
  # create_air_sys_* / create_zone_* creators). Topology only: ECM performance curves and
  # COPs are the host efficiency pass's job.
  module EcmAir
    # --- air-loop-side equipment -------------------------------------------------------

    def self.air_cooling_eqpt(model, type)
      case type
      when 'ashp'
        coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
        coil.setName('CoilCoolingDxSingleSpeed_ASHP')
        # 1.0e-6 ~ zero: legacy-parity near-zero (E+ rejects or special-cases a hard 0 on
        # these fields); used throughout this file.
        coil.setCrankcaseHeaterCapacity(1.0e-6)
        coil
      when 'ccashp'
        coil = OpenStudio::Model::CoilCoolingDXVariableSpeed.new(model)
        coil.setName('CoilCoolingDXVariableSpeed_CCASHP')
        coil.addSpeed(OpenStudio::Model::CoilCoolingDXVariableSpeedSpeedData.new(model))
        coil.setNominalSpeedLevel(1)
        coil.setCrankcaseHeaterCapacity(1.0e-6)
        coil
      when 'coil_chw'
        coil = OpenStudio::Model::CoilCoolingWater.new(model)
        coil.setName('CoilCoolingWater')
        coil   # unattached; caller sweeps it onto the CHW plant once built
      else
        raise(ArgumentError, "unknown ECM air cooling equipment '#{type}'")
      end
    end

    def self.air_heating_eqpt(model, type, hw_loop: nil)
      always_on = model.alwaysOnDiscreteSchedule
      case type
      when 'ashp'
        coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
        coil.setName('CoilHeatingDXSingleSpeed_ASHP')
        coil.setDefrostStrategy('ReverseCycle')
        coil.setDefrostControl('OnDemand')
        coil.setCrankcaseHeaterCapacity(1.0e-6)
        coil
      when 'ccashp'
        coil = OpenStudio::Model::CoilHeatingDXVariableSpeed.new(model)
        coil.setName('CoilHeatingDXVariableSpeed_CCASHP')
        coil.addSpeed(OpenStudio::Model::CoilHeatingDXVariableSpeedSpeedData.new(model))
        coil.setNominalSpeedLevel(1)
        coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-25.0)
        coil.setDefrostStrategy('ReverseCycle')
        coil.setDefrostControl('OnDemand')
        coil.setCrankcaseHeaterCapacity(1.0e-6)
        coil
      when 'coil_electric', 'Electric'
        coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
        coil.setName('CoilHeatingElectric')
        coil
      when 'coil_gas', 'Gas'
        coil = OpenStudio::Model::CoilHeatingGas.new(model, always_on)
        coil.setName('CoilHeatingGas')
        coil
      when 'coil_hw', 'Hot Water'
        coil = OpenStudio::Model::CoilHeatingWater.new(model)
        coil.setName('CoilHeatingWater')
        hw_loop.addDemandBranchForComponent(coil) unless hw_loop.nil?
        coil
      when 'none', nil
        nil
      else
        raise(ArgumentError, "unknown ECM air heating equipment '#{type}'")
      end
    end

    # Assemble an ECM air loop: components added at the supply outlet in the legacy order
    # (clg, htg, supp, fan, spm), OA system (ZoneSum) at the inlet, optional VV return fan
    # on the return-air node.
    #
    # @param spm_type [String] 'scheduled' (20C), 'single_zone_reheat' (13/43),
    #   'warmest' (13/22)
    # @param supply_fan_type [String] 'constant_volume' or 'variable_volume'
    # @return [Array] [air_loop, clg_coil, htg_coil, return_fan]
    def self.assemble(model, zones,
                      air_eqpt: nil, htg_type: nil, clg_type: nil,
                      supp_htg_type: 'none', spm_type:, supply_fan_type:,
                      return_fan: false, hw_loop: nil)
      air_loop = OpenStudio::Model::AirLoopHVAC.new(model)

      clg_coil = air_cooling_eqpt(model, clg_type || air_eqpt)
      htg_coil = air_heating_eqpt(model, htg_type || air_eqpt)
      supp_coil = air_heating_eqpt(model, supp_htg_type, hw_loop: hw_loop)

      fan = supply_fan_type == 'variable_volume' ? OpenStudio::Model::FanVariableVolume.new(model) : OpenStudio::Model::FanConstantVolume.new(model)
      fan.setName('Supply Fan')   # 'Supply' substring is load-bearing for host fan rules

      clg_coil.addToNode(air_loop.supplyOutletNode)
      htg_coil.addToNode(air_loop.supplyOutletNode)
      supp_coil.addToNode(air_loop.supplyOutletNode) if supp_coil
      fan.addToNode(air_loop.supplyOutletNode)

      # Setpoint temps are legacy parity with ECMS create_air_sys_spm
      # (necb/ECMS/hvac_systems.rb:674-696): 'scheduled' = constant 20.0 C neutral DOAS
      # supply; 'single_zone_reheat' = 13.0 C min / 43.0 C max supply (43 C is the NECB
      # warm-air heating design supply temperature, cf. add_zone_eqpt's 43.0 C zone
      # heating design supply at hvac_systems.rb:991); 'warmest' = 13.0/22.0 C band.
      spm =
        case spm_type
        when 'scheduled'
          OpenStudio::Model::SetpointManagerScheduled.new(
            model, Schedules.constant_ruleset(model, 'DOAS Supply Air Temp', 20.0)
          )
        when 'single_zone_reheat'
          m = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(model)
          m.setControlZone(zones.first)
          m.setMinimumSupplyAirTemperature(13.0)
          m.setMaximumSupplyAirTemperature(43.0)
          m
        when 'warmest'
          m = OpenStudio::Model::SetpointManagerWarmest.new(model)
          m.setMinimumSetpointTemperature(13.0)
          m.setMaximumSetpointTemperature(22.0)
          m
        end
      spm.addToNode(air_loop.supplyOutletNode)

      oa_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
      oa_controller.autosizeMinimumOutdoorAirFlowRate
      oa_controller.controllerMechanicalVentilation.setSystemOutdoorAirMethod('ZoneSum')
      OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_controller).addToNode(air_loop.supplyInletNode)

      rfan = nil
      if return_fan
        rfan = OpenStudio::Model::FanVariableVolume.new(model)
        rfan.setName('Return Fan')
        rfan.addToNode(air_loop.returnAirNode.get)
      end

      [air_loop, clg_coil, htg_coil, rfan]
    end

    # --- zone-side equipment -----------------------------------------------------------

    def self.add_diffuser(model, air_loop, zone, type)
      always_on = model.alwaysOnDiscreteSchedule
      diffuser =
        case type
        when 'single_duct_uncontrolled'
          OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, always_on)
        when 'single_duct_vav_reheat'
          reheat = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
          d = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, always_on, reheat)
          d.setMaximumReheatAirTemperature(43.0) # legacy parity: ECMS create_zone_diffuser (hvac_systems.rb:850)
          d.setDamperHeatingAction('Normal')
          d
        end
      air_loop.addBranchForZone(zone, diffuser.to_StraightComponent)
      diffuser
    end

    # PTAC with DX cooling and an always-off electric heating section (~zero OA) —
    # the ECM 'ptac_electric_off' zone cooling unit.
    def self.add_zone_ptac_electric_off(model, zone)
      always_on = model.alwaysOnDiscreteSchedule
      always_off = model.alwaysOffDiscreteSchedule
      htg = OpenStudio::Model::CoilHeatingElectric.new(model, always_on)
      htg.setName('CoilHeatingElectric')
      htg.setAvailabilitySchedule(always_off)
      clg = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
      clg.setName('CoilCoolingDXSingleSpeed_PTAC')
      clg.setCrankcaseHeaterCapacity(1.0e-6)
      fan = OpenStudio::Model::FanOnOff.new(model)
      fan.setName('FanOnOff')
      ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model, always_on, fan, htg, clg)
      ptac.setName('ZoneHVACPackagedTerminalAirConditioner')
      ptac.setSupplyAirFanOperatingModeSchedule(always_off)
      ptac.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-6)
      ptac.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-6)
      ptac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-6)
      ptac.addToThermalZone(zone)
      ptac
    end

    # Four-pipe fan coil with unattached hot/chilled-water coils (~zero OA, always-off fan
    # operating schedule) — the ECM 'fancoil_4pipe' zone unit. The caller attaches the
    # coils to plant loops afterwards (the legacy flow sweeps all CoilHeating/CoolingWaters
    # onto the HP plant loops once they exist).
    def self.add_zone_fancoil(model, zone)
      always_on = model.alwaysOnDiscreteSchedule
      always_off = model.alwaysOffDiscreteSchedule
      htg = OpenStudio::Model::CoilHeatingWater.new(model)
      htg.setName('CoilHeatingWater_FanCoil')
      clg = OpenStudio::Model::CoilCoolingWater.new(model)
      clg.setName('CoilCoolingWater_FanCoil')
      fan = OpenStudio::Model::FanOnOff.new(model)
      fan.setName('FanOnOff')
      fc = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(model, always_on, fan, clg, htg)
      fc.setName('ZoneHVACFourPipeFanCoil')
      fc.setSupplyAirFanOperatingModeSchedule(always_off)
      fc.setMaximumOutdoorAirFlowRate(1.0e-6)
      fc.addToThermalZone(zone)
      fc
    end

    # VRF terminal unit attached to an outdoor VRF unit.
    def self.add_zone_vrf_terminal(model, zone, outdoor_unit)
      always_off = model.alwaysOffDiscreteSchedule
      clg = OpenStudio::Model::CoilCoolingDXVariableRefrigerantFlow.new(model)
      clg.setName('CoilCoolingDXVariableRefrigerantFlow')
      htg = OpenStudio::Model::CoilHeatingDXVariableRefrigerantFlow.new(model)
      htg.setName('CoilHeatingDXVariableRefrigerantFlow')
      fan = OpenStudio::Model::FanOnOff.new(model)
      fan.setName('FanOnOff')
      terminal = OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow.new(model, clg, htg, fan)
      terminal.setName('ZoneHVACTerminalUnitVariableRefrigerantFlow')
      terminal.setSupplyAirFanOperatingModeSchedule(always_off)
      terminal.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-6)
      terminal.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-6)
      terminal.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(1.0e-6)
      terminal.setZoneTerminalUnitOffParasiticElectricEnergyUse(1.0e-6)
      terminal.setZoneTerminalUnitOnParasiticElectricEnergyUse(1.0e-6)
      terminal.addToThermalZone(zone)
      outdoor_unit.addTerminal(terminal)
      terminal
    end

    # Outdoor VRF unit with the ECM hs08 settings (port of add_outdoor_vrf_unit, minus the
    # defrost-EIR curve lookup — curve application is the host efficiency pass's job).
    #
    # SOURCE: every numeric below is verbatim legacy parity with ECMS add_outdoor_vrf_unit
    # (necb/ECMS/hvac_systems.rb:266-314, verified 2026-08). The legacy source carries the
    # values bare (no derivation given there either); the ECM models a
    # 'Mitsubishi_Hyper_Heating_VRF_Outdoor_Unit', so the odd-looking constants are
    # manufacturer-flavoured performance settings.
    def self.add_outdoor_vrf_unit(model, condenser_type: 'AirCooled')
      unit = OpenStudio::Model::AirConditionerVariableRefrigerantFlow.new(model)
      unit.setName('VRF Outdoor Unit')
      unit.setHeatPumpWasteHeatRecovery(true)
      unit.setRatedHeatingCOP(4.0)          # legacy hvac_systems.rb:272
      unit.setGrossRatedCoolingCOP(4.0)     # legacy hvac_systems.rb:276
      unit.setMinimumOutdoorTemperatureinHeatingMode(-25.0)   # cold-climate cutoff, legacy :278
      unit.setHeatingPerformanceCurveOutdoorTemperatureType('WetBulbTemperature')
      unit.setMasterThermostatPriorityControlType('ThermostatOffsetPriority')
      unit.setDefrostControl('OnDemand')
      unit.setDefrostStrategy('ReverseCycle')
      unit.autosizeResistiveDefrostHeaterCapacity
      # -0.00019231 piping height correction: legacy verbatim (:284-285), no derivation
      # given in the legacy source (~ -1/5200 per metre of height).
      unit.setPipingCorrectionFactorforHeightinHeatingModeCoefficient(-0.00019231)
      unit.setPipingCorrectionFactorforHeightinCoolingModeCoefficient(-0.00019231)
      unit.setMinimumOutdoorTemperatureinHeatRecoveryMode(-5.0)   # legacy :286
      unit.setMaximumOutdoorTemperatureinHeatRecoveryMode(26.2)   # legacy verbatim :287, no derivation given there
      # Heat-recovery startup fractions/time constants: legacy verbatim :288-294.
      unit.setInitialHeatRecoveryCoolingCapacityFraction(0.5)
      unit.setHeatRecoveryCoolingCapacityTimeConstant(0.15)
      unit.setInitialHeatRecoveryCoolingEnergyFraction(1.0)
      unit.setHeatRecoveryCoolingEnergyTimeConstant(0.0)
      unit.setInitialHeatRecoveryHeatingCapacityFraction(1.0)
      unit.setHeatRecoveryHeatingCapacityTimeConstant(0.15)
      unit.setInitialHeatRecoveryHeatingEnergyFraction(1.0)
      unit.setMinimumHeatPumpPartLoadRatio(0.5)   # legacy :296
      unit.setCondenserType(condenser_type)
      unit.setCrankcaseHeaterPowerperCompressor(1.0e-6)
      unit.setMinimumOutdoorTemperatureinCoolingMode(-10)   # legacy :299
      unit
    end
  end
end
