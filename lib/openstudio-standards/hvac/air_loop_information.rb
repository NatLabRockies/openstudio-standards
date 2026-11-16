module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group AirLoop:Information
    # Methods to get information on AirLoop objects

    # Returns whether air loop HVAC has direct evaporative cooling
    #
    # @param air_loop_hvac [<OpenStudio::Model::AirLoopHVAC>] OpenStudio AirLoopHVAC object
    # @return [Boolean] returns true if successful, false if not
    def self.air_loop_hvac_direct_evap?(air_loop_hvac)
      # check if direct evap
      is_direct_evap = false
      air_loop_hvac.supplyComponents.each do |component|
        # Get the object type
        obj_type = component.iddObjectType.valueName.to_s
        case obj_type
        when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial'
          is_direct_evap = true
        end
      end
      return is_direct_evap
    end

    # Determine if the airloop includes cooling coils
    #
    # @return [Boolean] returns true if cooling coils are included on the airloop
    def self.air_loop_hvac_cooling_coil?(air_loop_hvac)
      air_loop_hvac.supplyComponents.each do |comp|
        return true if comp.to_CoilCoolingWater.is_initialized
        return true if comp.to_CoilCoolingWater.is_initialized
        return true if comp.to_CoilCoolingCooledBeam.is_initialized
        return true if comp.to_CoilCoolingDXMultiSpeed.is_initialized
        return true if comp.to_CoilCoolingDXSingleSpeed.is_initialized
        return true if comp.to_CoilCoolingDXTwoSpeed.is_initialized
        return true if comp.to_CoilCoolingDXTwoStageWithHumidityControlMode.is_initialized
        return true if comp.to_CoilCoolingDXVariableRefrigerantFlow.is_initialized
        return true if comp.to_CoilCoolingDXVariableSpeed.is_initialized
        return true if comp.to_CoilCoolingFourPipeBeam.is_initialized
        return true if comp.to_CoilCoolingLowTempRadiantConstFlow.is_initialized
        return true if comp.to_CoilCoolingLowTempRadiantVarFlow.is_initialized
        return true if comp.to_CoilCoolingWater.is_initialized
        return true if comp.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
        return true if comp.to_CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit.is_initialized

        if comp.to_AirLoopHVACUnitarySystem.is_initialized
          unitary_system = comp.to_AirLoopHVACUnitarySystem.get
          if unitary_system.coolingCoil.is_initialized
            cooling_coil = unitary_system.coolingCoil.get
            return true if cooling_coil.to_CoilCoolingWater.is_initialized
            return true if cooling_coil.to_CoilCoolingWater.is_initialized
            return true if cooling_coil.to_CoilCoolingCooledBeam.is_initialized
            return true if cooling_coil.to_CoilCoolingDXMultiSpeed.is_initialized
            return true if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
            return true if cooling_coil.to_CoilCoolingDXTwoSpeed.is_initialized
            return true if cooling_coil.to_CoilCoolingDXTwoStageWithHumidityControlMode.is_initialized
            return true if cooling_coil.to_CoilCoolingDXVariableRefrigerantFlow.is_initialized
            return true if cooling_coil.to_CoilCoolingDXVariableSpeed.is_initialized
            return true if cooling_coil.to_CoilCoolingFourPipeBeam.is_initialized
            return true if cooling_coil.to_CoilCoolingLowTempRadiantConstFlow.is_initialized
            return true if cooling_coil.to_CoilCoolingLowTempRadiantVarFlow.is_initialized
            return true if cooling_coil.to_CoilCoolingWater.is_initialized
            return true if cooling_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
            return true if cooling_coil.to_CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit.is_initialized
          end
        end
      end
      return false
    end

    # Determine if the air loop has DX cooling
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if uses DX cooling, false if not
    def self.air_loop_hvac_dx_cooling?(air_loop_hvac)
      dx_clg = false

      # Check for all DX coil types
      dx_types = [
        'OS_Coil_Cooling_DX_MultiSpeed',
        'OS_Coil_Cooling_DX_SingleSpeed',
        'OS_Coil_Cooling_DX_TwoSpeed',
        'OS_Coil_Cooling_DX_TwoStageWithHumidityControlMode',
        'OS_Coil_Cooling_DX_VariableRefrigerantFlow',
        'OS_Coil_Cooling_DX_VariableSpeed',
        'OS_CoilSystem_Cooling_DX_HeatExchangerAssisted'
      ]

      air_loop_hvac.supplyComponents.each do |component|
        # Get the object type, getting the internal coil
        # type if inside a unitary system.
        obj_type = component.iddObjectType.valueName.to_s
        case obj_type
        when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
          component = component.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
          obj_type = component.coolingCoil.iddObjectType.valueName.to_s
        when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
          component = component.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
          obj_type = component.coolingCoil.iddObjectType.valueName.to_s
        when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
          component = component.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
          obj_type = component.coolingCoil.iddObjectType.valueName.to_s
        when 'OS_AirLoopHVAC_UnitarySystem'
          component = component.to_AirLoopHVACUnitarySystem.get
          if component.coolingCoil.is_initialized
            obj_type = component.coolingCoil.get.iddObjectType.valueName.to_s
          end
        end
        # See if the object type is a DX coil
        if dx_types.include?(obj_type)
          dx_clg = true
          break # Stop if find a DX coil
        end
      end

      return dx_clg
    end

    # Determine if the system has an air-side economizer
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if required, false if not
    def self.air_loop_hvac_economizer?(air_loop_hvac)
      # Get the OA system and OA controller
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      return false unless oa_sys.is_initialized

      oa_sys = oa_sys.get
      oa_control = oa_sys.getControllerOutdoorAir
      economizer_type = oa_control.getEconomizerControlType

      # Return false if no economizer is present
      return false if economizer_type == 'NoEconomizer'

      return true
    end

    # Determine if the system has energy recovery already
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if an ERV is present, false if not
    def self.air_loop_hvac_energy_recovery?(air_loop_hvac)
      has_erv = false

      # Get the OA system
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      return false unless oa_sys.is_initialized

      # Find any ERV on the OA system
      oa_sys = oa_sys.get
      oa_sys.oaComponents.each do |oa_comp|
        if oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized
          has_erv = true
        end
      end

      return has_erv
    end

    # Determine how many humidifies are on the airloop
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Integer] the number of humidifiers
    def self.air_loop_hvac_humidifier_count(air_loop_hvac)
      humidifiers = 0
      air_loop_hvac.supplyComponents.each do |cmp|
        if cmp.to_HumidifierSteamElectric.is_initialized
          humidifiers += 1
        end
      end
      return humidifiers
    end

    # Determine if the airloop has hydronic cooling coils
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if hydronic cooling coils are included on the airloop
    def self.air_loop_hvac_hydronic_cooling?(air_loop_hvac)
      air_loop_hvac.supplyComponents.each do |comp|
        return true if comp.to_CoilCoolingWater.is_initialized
      end
      return false
    end

    # Determine if the air loop has multi-stage DX cooling
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if uses multi-stage DX cooling, false if not
    def self.air_loop_hvac_multi_stage_dx_cooling?(air_loop_hvac)
      dx_clg = false

      # Check for all DX coil types
      dx_types = [
        'OS_Coil_Cooling_DX_MultiSpeed',
        'OS_Coil_Cooling_DX_TwoSpeed',
        'OS_Coil_Cooling_DX_TwoStageWithHumidityControlMode'
      ]

      air_loop_hvac.supplyComponents.each do |component|
        # Get the object type, getting the internal coil
        # type if inside a unitary system.
        obj_type = component.iddObjectType.valueName.to_s
        case obj_type
        when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
          component = component.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
          obj_type = component.coolingCoil.iddObjectType.valueName.to_s
        when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
          component = component.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
          obj_type = component.coolingCoil.iddObjectType.valueName.to_s
        when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
          component = component.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
          obj_type = component.coolingCoil.iddObjectType.valueName.to_s
        when 'OS_AirLoopHVAC_UnitarySystem'
          component = component.to_AirLoopHVACUnitarySystem.get
          if component.coolingCoil.is_initialized
            obj_type = component.coolingCoil.get.iddObjectType.valueName.to_s
          end
        end
        # See if the object type is a DX coil
        if dx_types.include?(obj_type)
          dx_clg = true
          break # Stop if find a DX coil
        end
      end

      return dx_clg
    end

    # Determine if the air loop serves parallel PIU air terminals
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    def self.air_loop_hvac_parallel_piu_air_terminals?(air_loop_hvac)
      has_parallel_piu_terminals = false
      air_loop_hvac.thermalZones.each do |zone|
        zone.equipment.each do |equipment|
          # Get the object type
          obj_type = equipment.iddObjectType.valueName.to_s
          if obj_type == 'OS_AirTerminal_SingleDuct_ParallelPIU_Reheat'
            return true
          end
        end
      end

      return has_parallel_piu_terminals
    end

    # Checks if zones served by the air loop use zone exhaust fans as a simplified approach to model transfer air
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] OpenStudio AirLoopHVAC object
    # @return [Boolean] true if simple transfer air is modeled, false otherwise
    def self.air_loop_hvac_simple_transfer_air?(air_loop_hvac)
      simple_transfer_air = false
      zones = air_loop_hvac.thermalZones
      zones_name = []
      zones.each do |zone|
        zones_name << zone.name.to_s
      end
      air_loop_hvac.model.getFanZoneExhausts.sort.each do |exhaust_fan|
        if (zones_name.include? exhaust_fan.thermalZone.get.name.to_s) && exhaust_fan.balancedExhaustFractionSchedule.is_initialized
          simple_transfer_air = true
        end
      end
      return simple_transfer_air
    end

    # Determine if the system has terminal reheat
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if has one or more reheat terminals, false if it doesn't
    def self.air_loop_hvac_terminal_reheat?(air_loop_hvac)
      has_term_rht = false
      air_loop_hvac.demandComponents.each do |sc|
        if sc.to_AirTerminalSingleDuctConstantVolumeReheat.is_initialized ||
           sc.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized ||
           sc.to_AirTerminalSingleDuctSeriesPIUReheat.is_initialized ||
           sc.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.is_initialized ||
           sc.to_AirTerminalSingleDuctVAVReheat.is_initialized
          has_term_rht = true
          break
        end
      end

      return has_term_rht
    end

    # Determine whether air loop HVAC is a unitary system
    #
    # @param air_loop_hvac [<OpenStudio::Model::AirLoopHVAC>] OpenStudio AirLoopHVAC object
    # @return [Boolean] returns true if air_loop_hvac is a unitary system, false if not
    def self.air_loop_hvac_unitary_system?(air_loop_hvac)
      # check if unitary system
      is_unitary_system = false
      air_loop_hvac.supplyComponents.each do |component|
        # Get the object type
        obj_type = component.iddObjectType.valueName.to_s
        case obj_type
        when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
          is_unitary_system = true
        end
      end
      return is_unitary_system
    end

    # Determine if the system is a VAV system based on the fan which may be inside of a unitary system.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if vav system, false if not
    def self.air_loop_hvac_vav_system?(air_loop_hvac)
      is_vav = false
      air_loop_hvac.supplyComponents.reverse.each do |comp|
        if comp.to_FanVariableVolume.is_initialized
          is_vav = true
        elsif comp.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.is_initialized
          fan = comp.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get.supplyAirFan
          if fan.to_FanVariableVolume.is_initialized
            is_vav = true
          end
        elsif comp.to_AirLoopHVACUnitarySystem.is_initialized
          fan = comp.to_AirLoopHVACUnitarySystem.get.supplyFan
          if fan.is_initialized && fan.get.to_FanVariableVolume.is_initialized
            is_vav = true
          end
        end
      end

      return is_vav
    end

    # Determine if the system is a multizone VAV system
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if multizone vav, false if not
    def self.air_loop_hvac_multizone_vav_system?(air_loop_hvac)
      multizone_vav_system = false

      # Must serve more than 1 zone
      if air_loop_hvac.thermalZones.size < 2
        return multizone_vav_system
      end

      # Must be a variable volume system
      is_vav = OpenstudioStandards::HVAC.air_loop_hvac_vav_system?(air_loop_hvac)
      if is_vav == false
        return multizone_vav_system
      end

      # If here, it's a multizone VAV system
      multizone_vav_system = true

      return multizone_vav_system
    end

    # Determine if the airloop includes WSHP cooling coils
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Boolean] returns true if WSHP cooling coils are included on the airloop
    def self.air_loop_hvac_wshp?(air_loop_hvac)
      air_loop_hvac.supplyComponents.each do |comp|
        return true if comp.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized

        if comp.to_AirLoopHVACUnitarySystem.is_initialized
          clg_coil = comp.to_AirLoopHVACUnitarySystem.get.coolingCoil.get
          return true if clg_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized

        end
      end
      return false
    end

    # Get the return air plenum zone object for an air loop, if it exists
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] OpenStudio AirLoopHVAC object
    # @return [OpenStudio::Model::ThermalZone] OpenStudio thermal zone object of the return air plenum zone when an air loop uses a return air plenum, nil otherwise
    def self.air_loop_hvac_return_air_plenum(air_loop_hvac)
      # Get return air node
      return_air_node = air_loop_hvac.demandOutletNode

      # Check if node is connected to a return plenum object
      air_loop_hvac.model.getAirLoopHVACReturnPlenums.each do |return_plenum|
        air_loop_hvac.model.getAirLoopHVACZoneMixers.each do |zone_air_mixer|
          inlets = zone_air_mixer.inletModelObjects
          inlets.each do |inlet|
            if (inlet.to_Node.get == return_plenum.outletModelObject.get.to_Node.get) && (zone_air_mixer.outletModelObject.get.to_Node.get == return_air_node)
              return return_plenum.thermalZone.get
            end
          end
        end
      end

      return nil
    end

    # Get the heating coil for an air loop
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] AirLoopHVAC object
    # @return [OpenStudio::Model::HVACComponent] heating coil object, cast as its object type under the HVACComponent class
    def self.air_loop_hvac_heating_coil(air_loop_hvac)
      heating_coil = nil
      air_loop_hvac.supplyComponents.each do |comp|
        if comp.to_CoilHeatingWater.is_initialized
          heating_coil = comp.to_CoilHeatingWater.get
        elsif comp.to_CoilHeatingElectric.is_initialized
          heating_coil = comp.to_CoilHeatingElectric.get
        elsif comp.to_AirLoopHVACUnitarySystem.is_initialized
          htg_coil = comp.to_AirLoopHVACUnitarySystem.get.heatingCoil
          if htg_coil.is_initialized && htg_coil.get.to_CoilHeatingWater.is_initialized
            heating_coil = htg_coil.get.to_CoilHeatingWater.get
          elsif htg_coil.is_initialized && htg_coil.get.to_CoilHeatingElectric.is_initialized
            heating_coil = htg_coil.get.to_CoilHeatingElectric.get
          end
        end
      end

      return heating_coil
    end

    # Get the supply fan for an air loop
    #
    # @param air_loop [OpenStudio::Model::AirLoopHVAC] AirLoopHVAC object
    # @return [OpenStudio::Model::HVACComponent] fan object, cast as its object type under the HVACComponent class
    def self.air_loop_hvac_supply_fan(air_loop)
      fan = nil
      if air_loop.supplyFan.is_initialized
        # Get return fan
        fan = air_loop.supplyFan.get

        # Get fan object
        if fan.to_FanConstantVolume.is_initialized
          fan = fan.to_FanConstantVolume.get
        elsif fan.to_FanVariableVolume.is_initialized
          fan = fan.to_FanVariableVolume.get
        elsif fan.to_FanOnOff.is_initialized
          fan = fan.to_FanOnOff.get
        end

      else
        air_loop.supplyComponents.each do |comp|
          if comp.to_AirLoopHVACUnitarySystem.is_initialized
            fan = comp.to_AirLoopHVACUnitarySystem.get.supplyFan
            next if fan.empty?

            # Get fan object
            fan = fan.get
            if fan.to_FanConstantVolume.is_initialized
              fan = fan.to_FanConstantVolume.get
            elsif fan.to_FanVariableVolume.is_initialized
              fan = fan.to_FanVariableVolume.get
            elsif fan.to_FanOnOff.is_initialized
              fan = fan.to_FanOnOff.get
            end
          end
        end
      end
      return fan
    end

    # Get all of the supply, return, exhaust, and relief fans on this system
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Array] an array of FanConstantVolume, FanVariableVolume, and FanOnOff objects
    def self.air_loop_hvac_supply_return_exhaust_relief_fans(air_loop_hvac)
      # Fans on the supply side of the airloop directly, or inside of unitary equipment.
      fans = []
      sup_and_oa_comps = air_loop_hvac.supplyComponents
      sup_and_oa_comps += air_loop_hvac.oaComponents
      sup_and_oa_comps.each do |comp|
        if comp.to_FanConstantVolume.is_initialized
          fans << comp.to_FanConstantVolume.get
        elsif comp.to_FanVariableVolume.is_initialized
          fans << comp.to_FanVariableVolume.get
        elsif comp.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.is_initialized
          sup_fan = comp.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get.supplyAirFan
          if sup_fan.to_FanConstantVolume.is_initialized
            fans << sup_fan.to_FanConstantVolume.get
          elsif sup_fan.to_FanOnOff.is_initialized
            fans << sup_fan.to_FanOnOff.get
          end
        elsif comp.to_AirLoopHVACUnitarySystem.is_initialized
          sup_fan = comp.to_AirLoopHVACUnitarySystem.get.supplyFan
          next if sup_fan.empty?

          sup_fan = sup_fan.get
          if sup_fan.to_FanConstantVolume.is_initialized
            fans << sup_fan.to_FanConstantVolume.get
          elsif sup_fan.to_FanOnOff.is_initialized
            fans << sup_fan.to_FanOnOff.get
          elsif sup_fan.to_FanVariableVolume.is_initialized
            fans << sup_fan.to_FanVariableVolume.get
          end
        end
      end

      return fans
    end

    # Get supply fan power for airloop
    #
    # @param air_loop [OpenStudio::Model::AirLoopHVAC] AirLoopHVAC object
    # @return [Double] Fan power
    def self.air_loop_hvac_supply_fan_power(air_loop)
      supply_fan_power = 0

      # Get fan
      fan = OpenstudioStandards::HVAC.air_loop_hvac_supply_fan(air_loop)

      if !fan.nil?
        # Get fan power
        supply_fan_power += OpenstudioStandards::HVAC.fan_fanpower(fan)
      end

      return supply_fan_power
    end

    # Get return fan power for airloop
    #
    # @param air_loop [OpenStudio::Model::AirLoopHVAC] AirLoopHVAC object
    # @return [Double] Fan power in watts
    def self.air_loop_hvac_return_fan_power(air_loop)
      return_fan_power = 0

      if air_loop.returnFan.is_initialized
        # Get return fan
        fan = air_loop.returnFan.get

        # Get fan object
        if fan.to_FanConstantVolume.is_initialized
          fan = fan.to_FanConstantVolume.get
        elsif fan.to_FanVariableVolume.is_initialized
          fan = fan.to_FanVariableVolume.get
        elsif fan.to_FanOnOff.is_initialized
          fan = fan.to_FanOnOff.get
        end

        # Get fan power
        return_fan_power += OpenstudioStandards::HVAC.fan_fanpower(fan)
      end

      return return_fan_power
    end

    # Get relief fan power for airloop
    #
    # @param air_loop [OpenStudio::Model::AirLoopHVAC] AirLoopHVAC object
    # @return [Double] Fan power
    def self.air_loop_hvac_relief_fan_power(air_loop)
      relief_fan_power = 0

      if air_loop.reliefFan.is_initialized
        # Get return fan
        fan = air_loop.reliefFan.get

        # Get fan object
        if fan.to_FanConstantVolume.is_initialized
          fan = fan.to_FanConstantVolume.get
        elsif fan.to_FanVariableVolume.is_initialized
          fan = fan.to_FanVariableVolume.get
        elsif fan.to_FanOnOff.is_initialized
          fan = fan.to_FanOnOff.get
        end

        # Get fan power
        relief_fan_power += OpenstudioStandards::HVAC.fan_fanpower(fan)
      end

      return relief_fan_power
    end

    # Return the design supply air flow rate for an air loop
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Double] design supply air flow rate in m^3/s
    def self.air_loop_hvac_design_supply_air_flow_rate(air_loop_hvac)
      # Get the design_supply_air_flow_rate
      design_supply_air_flow_rate = nil
      if air_loop_hvac.designSupplyAirFlowRate.is_initialized
        design_supply_air_flow_rate = air_loop_hvac.designSupplyAirFlowRate.get
      elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
        design_supply_air_flow_rate = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} design supply air flow rate is not available.")
      end

      return design_supply_air_flow_rate
    end

    # Determine the total brake horsepower of the fans on the system
    # with or without the fans inside of fan powered terminals.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @param include_terminal_fans [Boolean] if true, power from fan powered terminals will be included
    # @return [Double] total brake horsepower of the fans on the system, in units of horsepower
    def self.air_loop_hvac_system_fan_brake_horsepower(air_loop_hvac, include_terminal_fans = true)
      # @todo get the template from the parent model itself?
      # Or not because maybe you want to see the difference between two standards?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name}-Determining #{template} allowable system fan power.")

      # Get all fans
      fans = []
      # Supply, exhaust, relief, and return fans
      fans += OpenstudioStandards::HVAC.air_loop_hvac_supply_return_exhaust_relief_fans(air_loop_hvac)

      # Fans inside of fan-powered terminals
      if include_terminal_fans
        air_loop_hvac.demandComponents.each do |comp|
          if comp.to_AirTerminalSingleDuctSeriesPIUReheat.is_initialized
            term_fan = comp.to_AirTerminalSingleDuctSeriesPIUReheat.get.supplyAirFan
            if term_fan.to_FanConstantVolume.is_initialized
              fans << term_fan.to_FanConstantVolume.get
            end
          elsif comp.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized
            term_fan = comp.to_AirTerminalSingleDuctParallelPIUReheat.get.fan
            if term_fan.to_FanConstantVolume.is_initialized
              fans << term_fan.to_FanConstantVolume.get
            end
          end
        end
      end

      # Loop through all fans on the system and
      # sum up their brake horsepower values.
      sys_fan_bhp = 0
      fans.sort.each do |fan|
        sys_fan_bhp += OpenstudioStandards::HVAC.fan_brake_horsepower(fan)
      end

      return sys_fan_bhp
    end

    # Get the total cooling capacity for the air loop
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Double] total cooling capacity in watts
    # @todo Change to pull water coil nominal capacity instead of design load; not a huge difference, but water coil nominal capacity not available in sizing table.
    # @todo Handle all additional cooling coil types.  Currently only handles CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, and CoilCoolingWater
    def self.air_loop_hvac_total_cooling_capacity(air_loop_hvac)
      # Sum the cooling capacity for all cooling components
      # on the airloop, which may be inside of unitary systems.
      total_cooling_capacity_w = 0
      air_loop_hvac.supplyComponents.each do |sc|
        # CoilCoolingDXSingleSpeed
        if sc.to_CoilCoolingDXSingleSpeed.is_initialized
          coil = sc.to_CoilCoolingDXSingleSpeed.get
          if coil.ratedTotalCoolingCapacity.is_initialized
            total_cooling_capacity_w += coil.ratedTotalCoolingCapacity.get
          elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
            total_cooling_capacity_w += coil.autosizedRatedTotalCoolingCapacity.get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
          end
        elsif sc.to_CoilCoolingDXTwoSpeed.is_initialized
          coil = sc.to_CoilCoolingDXTwoSpeed.get
          if coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
            total_cooling_capacity_w += coil.ratedHighSpeedTotalCoolingCapacity.get
          elsif coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
            total_cooling_capacity_w += coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
          end
          # CoilCoolingWater
        elsif sc.to_CoilCoolingWater.is_initialized
          coil = sc.to_CoilCoolingWater.get
          # error if the design coil capacity method isn't available
          if coil.model.version < OpenStudio::VersionString.new('3.6.0')
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.AirLoopHVAC', 'Required CoilCoolingWater method .autosizedDesignCoilLoad is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
          end
          if coil.autosizedDesignCoilLoad.is_initialized
            # @todo Change to pull water coil nominal capacity instead of design load
            total_cooling_capacity_w += coil.autosizedDesignCoilLoad.get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
          end
          # CoilCoolingWaterToAirHeatPumpEquationFit
        elsif sc.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
          coil = sc.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
          if coil.ratedTotalCoolingCapacity.is_initialized
            total_cooling_capacity_w += coil.ratedTotalCoolingCapacity.get
          elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
            total_cooling_capacity_w += coil.autosizedRatedTotalCoolingCapacity.get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
          end
        elsif sc.to_AirLoopHVACUnitarySystem.is_initialized
          unitary = sc.to_AirLoopHVACUnitarySystem.get
          if unitary.coolingCoil.is_initialized
            clg_coil = unitary.coolingCoil.get
            # CoilCoolingDXSingleSpeed
            if clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
              coil = clg_coil.to_CoilCoolingDXSingleSpeed.get
              if coil.ratedTotalCoolingCapacity.is_initialized
                total_cooling_capacity_w += coil.ratedTotalCoolingCapacity.get
              elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
                total_cooling_capacity_w += coil.autosizedRatedTotalCoolingCapacity.get
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
              end
            # CoilCoolingDXTwoSpeed
            elsif clg_coil.to_CoilCoolingDXTwoSpeed.is_initialized
              coil = clg_coil.to_CoilCoolingDXTwoSpeed.get
              if coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
                total_cooling_capacity_w += coil.ratedHighSpeedTotalCoolingCapacity.get
              elsif coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
                total_cooling_capacity_w += coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
              end
            # CoilCoolingWater
            elsif clg_coil.to_CoilCoolingWater.is_initialized
              coil = clg_coil.to_CoilCoolingWater.get
              # error if the design coil capacity method isn't available
              if coil.model.version < OpenStudio::VersionString.new('3.6.0')
                OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.AirLoopHVAC', 'Required CoilCoolingWater method .autosizedDesignCoilLoad is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
              end
              if coil.autosizedDesignCoilLoad.is_initialized
                # @todo Change to pull water coil nominal capacity instead of design load
                total_cooling_capacity_w += coil.autosizedDesignCoilLoad.get
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
              end
            # CoilCoolingWaterToAirHeatPumpEquationFit
            elsif clg_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
              coil = clg_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
              if coil.ratedTotalCoolingCapacity.is_initialized
                total_cooling_capacity_w += coil.ratedTotalCoolingCapacity.get
              elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
                total_cooling_capacity_w += coil.autosizedRatedTotalCoolingCapacity.get
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
              end
            end
          end
        elsif sc.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
          unitary = sc.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
          clg_coil = unitary.coolingCoil
          # CoilCoolingDXSingleSpeed
          if clg_coil.to_CoilCoolingDXSingleSpeed.is_initialized
            coil = clg_coil.to_CoilCoolingDXSingleSpeed.get
            if coil.ratedTotalCoolingCapacity.is_initialized
              total_cooling_capacity_w += coil.ratedTotalCoolingCapacity.get
            elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
              total_cooling_capacity_w += coil.autosizedRatedTotalCoolingCapacity.get
            else
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
            end
          # CoilCoolingDXTwoSpeed
          elsif clg_coil.to_CoilCoolingDXTwoSpeed.is_initialized
            coil = clg_coil.to_CoilCoolingDXTwoSpeed.get
            if coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
              total_cooling_capacity_w += coil.ratedHighSpeedTotalCoolingCapacity.get
            elsif coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
              total_cooling_capacity_w += coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
            else
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
            end
          # CoilCoolingWater
          elsif clg_coil.to_CoilCoolingWater.is_initialized
            coil = clg_coil.to_CoilCoolingWater.get
            # error if the design coil capacity method isn't available
            if coil.model.version < OpenStudio::VersionString.new('3.6.0')
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.AirLoopHVAC', 'Required CoilCoolingWater method .autosizedDesignCoilLoad is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
            end
            if coil.autosizedDesignCoilLoad.is_initialized
              # @todo Change to pull water coil nominal capacity instead of design load
              total_cooling_capacity_w += coil.autosizedDesignCoilLoad.get
            else
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
            end
          end
        elsif sc.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized
          unitary = sc.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
          clg_coil = unitary.coolingCoil
          # CoilCoolingDXMultSpeed
          if clg_coil.to_CoilCoolingDXMultiSpeed.is_initialized
            coil = clg_coil.to_CoilCoolingDXMultiSpeed.get
            total_cooling_capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_multi_speed_get_capacity(coil)
          end
        elsif sc.to_CoilCoolingDXVariableSpeed.is_initialized
          coil = sc.to_CoilCoolingDXVariableSpeed.get
          if coil.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
            # autosized capacity needs to be corrected for actual flow rate and fan power
            sys_fans = []
            air_loop_hvac.supplyComponents.each do |comp|
              if comp.to_FanConstantVolume.is_initialized
                sys_fans << comp.to_FanConstantVolume.get
              elsif comp.to_FanVariableVolume.is_initialized
                sys_fans << comp.to_FanVariableVolume.get
              end
            end
            max_pd = 0.0
            supply_fan = nil
            sys_fans.each do |fan|
              if fan.pressureRise.to_f > max_pd
                max_pd = fan.pressureRise.to_f
                supply_fan = fan # assume supply fan has higher pressure drop
              end
            end
            fan_power = supply_fan.autosizedMaximumFlowRate.to_f * supply_fan.pressureRise.to_f / supply_fan.fanTotalEfficiency.to_f
            nominal_cooling_capacity_w = coil.autosizedGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f
            nominal_flow_rate_factor = supply_fan.autosizedMaximumFlowRate.to_f / coil.autosizedRatedAirFlowRateAtSelectedNominalSpeedLevel.to_f
            fan_power_adjustment_w = fan_power / coil.speeds.last.referenceUnitGrossRatedSensibleHeatRatio.to_f
            total_cooling_capacity_w += (nominal_cooling_capacity_w * nominal_flow_rate_factor) + fan_power_adjustment_w
          elsif coil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.is_initialized
            total_cooling_capacity_w += coil.grossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel.to_f
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} capacity of #{coil.name} is not available, total cooling capacity of air loop will be incorrect when applying standard.")
          end
        elsif sc.to_CoilCoolingDXMultiSpeed.is_initialized ||
              sc.to_CoilCoolingCooledBeam.is_initialized ||
              sc.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.is_initialized ||
              sc.to_AirLoopHVACUnitarySystem.is_initialized
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} has a cooling coil named #{sc.name}, whose type is not yet covered by economizer checks.")
          # CoilCoolingDXMultiSpeed
          # CoilCoolingCooledBeam
          # CoilCoolingWaterToAirHeatPumpEquationFit
          # AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass
          # AirLoopHVACUnitaryHeatPumpAirToAir
          # AirLoopHVACUnitarySystem
        end
      end

      return total_cooling_capacity_w
    end

    # Determine if every zone on the system has an identical multiplier.
    # If so, return this number.  If not, return 1.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Integer] an integer representing the system multiplier.
    def self.air_loop_hvac_system_multiplier(air_loop_hvac)
      mult = 1

      # Get all the zone multipliers
      zn_mults = []
      air_loop_hvac.thermalZones.each do |zone|
        zn_mults << zone.multiplier
      end

      # Warn if there are different multipliers
      uniq_mults = zn_mults.uniq
      if uniq_mults.size > 1
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: not all zones on the system have an identical zone multiplier.  Multipliers are: #{uniq_mults.join(', ')}.")
      else
        mult = uniq_mults[0]
      end

      return mult
    end

    # Calculate the total floor area of all zones attached to the air loop, in m^2.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # return [Double] the total floor area of all zones attached to the air loop in m^2.
    def self.air_loop_hvac_floor_area(air_loop_hvac)
      total_area = 0.0

      air_loop_hvac.thermalZones.each do |zone|
        total_area += zone.floorArea
      end

      return total_area
    end

    # Calculate the total floor area of all zones attached to the air loop that have no exterior surfaces, in m^2.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # return [Double] the total floor area of all zones attached to the air loop in m^2.
    def self.air_loop_hvac_floor_area_interior_zones(air_loop_hvac)
      total_area = 0.0

      air_loop_hvac.thermalZones.each do |zone|
        # Skip zones that have exterior surface area
        next if zone.exteriorSurfaceArea > 0

        total_area += zone.floorArea
      end

      return total_area
    end

    # Calculate the total floor area of all zones attached to the air loop that have at least one exterior surface, in m^2.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # return [Double] the total floor area of all zones attached to the air loop in m^2.
    def self.air_loop_hvac_floor_area_exterior_zones(air_loop_hvac)
      total_area = 0.0

      air_loop_hvac.thermalZones.each do |zone|
        # Skip zones that have no exterior surface area
        next if zone.exteriorSurfaceArea.zero?

        total_area += zone.floorArea
      end

      return total_area
    end

    # Determine how much residential area the airloop serves
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Double] residential area served in m^2
    def self.air_loop_hvac_residential_area(air_loop_hvac)
      res_area = 0.0

      air_loop_hvac.thermalZones.each do |zone|
        zone.spaces.each do |space|
          # Skip spaces with no space type
          next if space.spaceType.empty?

          space_type = space.spaceType.get

          # Skip spaces with no standards space type
          next if space_type.standardsSpaceType.empty?

          standards_space_type = space_type.standardsSpaceType.get
          if standards_space_type.downcase.include?('apartment') || standards_space_type.downcase.include?('guestroom') || standards_space_type.downcase.include?('patroom')
            res_area += space.floorArea
          end
        end
      end

      return res_area
    end

    # Determine how much data center area the airloop serves.
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @return [Double] the area of data center is served in m^2.
    # @todo Add an is_data_center field to the standards space type spreadsheet instead
    #   of relying on the standards space type name to identify a data center.
    def self.air_loop_hvac_data_center_area(air_loop_hvac)
      dc_area_m2 = 0.0

      air_loop_hvac.thermalZones.each do |zone|
        zone.spaces.each do |space|
          # Skip spaces with no space type
          next if space.spaceType.empty?

          space_type = space.spaceType.get

          # Skip spaces with no standards space type
          next if space_type.standardsSpaceType.empty?

          standards_space_type = space_type.standardsSpaceType.get
          # Counts as a data center if the name includes 'data'
          if standards_space_type.downcase.include?('data center') || standards_space_type.downcase.include?('datacenter')
            dc_area_m2 += space.floorArea
          end
          std_bldg_type = space.spaceType.get.standardsBuildingType.get
          if std_bldg_type.downcase.include?('datacenter') && standards_space_type.downcase.include?('computerroom')
            dc_area_m2 += space.floorArea
          end
        end
      end

      return dc_area_m2
    end

    # Returns the unitary system minimum and maximum design temperatures
    #
    # @param unitary_system [<OpenStudio::Model::ModelObject>] OpenStudio ModelObject object
    # @return [Hash] returns as hash with 'min_temp' and 'max_temp' in degrees Fahrenheit
    def self.unitary_system_min_max_temperature_value(unitary_system)
      min_temp = nil
      max_temp = nil
      # Get the object type
      obj_type = unitary_system.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitarySystem'
        unitary_system = unitary_system.to_AirLoopHVACUnitarySystem.get
        if unitary_system.useDOASDXCoolingCoil
          min_temp = OpenStudio.convert(unitary_system.dOASDXCoolingCoilLeavingMinimumAirTemperature, 'C', 'F').get
        end
        if unitary_system.maximumSupplyAirTemperature.is_initialized
          max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperature.get, 'C', 'F').get
        end
      when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
        unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
        if unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.is_initialized
          max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.get, 'C', 'F').get
        end
      when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
        unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
        if unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.is_initialized
          max_temp = OpenStudio.convert(unitary_system.maximumSupplyAirTemperaturefromSupplementalHeater.get, 'C', 'F').get
        end
      when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        unitary_system = unitary_system.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
        min_temp = OpenStudio.convert(unitary_system.minimumOutletAirTemperatureDuringCoolingOperation, 'C', 'F').get
        max_temp = OpenStudio.convert(unitary_system.maximumOutletAirTemperatureDuringHeatingOperation, 'C', 'F').get
      end

      return { 'min_temp' => min_temp, 'max_temp' => max_temp }
    end
  end
end
