module OpenStudioHVAC
  # SDK-only coil factories. DX coils carry the NECB reference curves from data/curves.json
  # (ported from openstudio-standards add_onespeed_DX_coil / add_onespeed_htg_DX_coil).
  module Coils
    # Single-speed DX cooling coil with NECB reference curves.
    #
    # @param model [OpenStudio::Model::Model]
    # @param schedule [OpenStudio::Model::Schedule] availability schedule
    # @return [OpenStudio::Model::CoilCoolingDXSingleSpeed]
    def self.dx_cooling_single_speed(model, schedule, name: 'CoilCoolingDXSingleSpeed_dx')
      coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(
        model,
        schedule,
        Curves.build(model, 'DXCOOL-NECB2011-REF-CAPFT'),
        Curves.build(model, 'DXCOOL-NECB2011-REF-CAPFFLOW'),
        Curves.build(model, 'DXCOOL-NECB2011-REF-COOLEIRFT'),
        Curves.build(model, 'DXCOOL-NECB2011-REF-EIRFFLOW'),
        Curves.build(model, 'DXCOOL-NECB2011-REF-COOLPLFFPLR')
      )
      coil.setName(name)
      coil
    end

    # Single-speed DX heating coil with NECB reference curves.
    #
    # @param model [OpenStudio::Model::Model]
    # @param schedule [OpenStudio::Model::Schedule] availability schedule
    # @return [OpenStudio::Model::CoilHeatingDXSingleSpeed]
    def self.dx_heating_single_speed(model, schedule, name: 'CoilHeatingDXSingleSpeed_dx')
      coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(
        model,
        schedule,
        Curves.build(model, 'DXHEAT-NECB2011-REF-CAPFT'),
        Curves.build(model, 'DXHEAT-NECB2011-REF-CAPFFLOW'),
        Curves.build(model, 'DXHEAT-NECB2011-REF-EIRFT'),
        Curves.build(model, 'DXHEAT-NECB2011-REF-EIRFFLOW'),
        Curves.build(model, 'DXHEAT-NECB2011-REF-PLFFPLR')
      )
      coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-10.0)
      coil.setName(name)
      coil
    end

    # Multi-speed DX cooling coil with the NECB reference curves on EVERY stage
    # (8.4.4.10.(8) / 2025 8.4.5.10.(8) staged DX). Stage capacities and flows are
    # AUTOSIZED — E+ sizes stage k to k/N of the top stage through the containing
    # unitary's UnitarySystemPerformanceMultispeed flow ratios, which is what
    # realizes the code's equal capacity increments without hard-setting anything
    # (hard-set capacities would break 8.4.1.2.(5) capacity auto-iteration).
    #
    # @param stages [Integer] initial stage count (the efficiency pass adjusts it post-sizing)
    # @return [OpenStudio::Model::CoilCoolingDXMultiSpeed]
    def self.dx_cooling_multi_speed(model, _schedule, stages: 2, name: 'CoilCoolingDXMultiSpeed_dx')
      coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(model)
      coil.setName(name)
      coil.setFuelType('Electricity')
      # legacy hvac_system_3_and_8_multi_speed.rb:118 — the PLF cycling penalty
      # belongs to the lowest stage only
      coil.setApplyPartLoadFractiontoSpeedsGreaterthan1(false)
      stages.times { coil.addStage(dx_cooling_stage(model)) }
      coil
    end

    # One CoilCoolingDXMultiSpeedStageData carrying the NECB reference curves.
    # @return [OpenStudio::Model::CoilCoolingDXMultiSpeedStageData]
    def self.dx_cooling_stage(model)
      stage = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(model)
      stage.setTotalCoolingCapacityFunctionofTemperatureCurve(Curves.build(model, 'DXCOOL-NECB2011-REF-CAPFT'))
      stage.setTotalCoolingCapacityFunctionofFlowFractionCurve(Curves.build(model, 'DXCOOL-NECB2011-REF-CAPFFLOW'))
      stage.setEnergyInputRatioFunctionofTemperatureCurve(Curves.build(model, 'DXCOOL-NECB2011-REF-COOLEIRFT'))
      stage.setEnergyInputRatioFunctionofFlowFractionCurve(Curves.build(model, 'DXCOOL-NECB2011-REF-EIRFFLOW'))
      stage.setPartLoadFractionCorrelationCurve(Curves.build(model, 'DXCOOL-NECB2011-REF-COOLPLFFPLR'))
      stage.autosizeGrossRatedTotalCoolingCapacity
      stage.autosizeGrossRatedSensibleHeatRatio
      stage.autosizeRatedAirFlowRate
      stage
    end

    # Multi-stage gas furnace coil (8.4.4.9.(7) / 2025 8.4.5.9.(7)). Stage
    # capacities stay AUTOSIZED for the same reason as the DX stages above.
    # @return [OpenStudio::Model::CoilHeatingGasMultiStage]
    def self.gas_heating_multi_stage(model, _schedule, stages: 2, name: 'CoilHeatingGasMultiStage_gas')
      coil = OpenStudio::Model::CoilHeatingGasMultiStage.new(model)
      coil.setName(name)
      stages.times { coil.addStage(gas_heating_stage(model)) }
      coil
    end

    # @return [OpenStudio::Model::CoilHeatingGasMultiStageStageData]
    def self.gas_heating_stage(model)
      stage = OpenStudio::Model::CoilHeatingGasMultiStageStageData.new(model)
      stage.autosizeNominalCapacity
      stage
    end

    # Multi-speed DX HEATING coil (reference ASHP staging). Same autosizing
    # contract; the -10 degC compressor cutoff is applied by the reference
    # transform, matching the single-speed coil.
    # @return [OpenStudio::Model::CoilHeatingDXMultiSpeed]
    def self.dx_heating_multi_speed(model, _schedule, stages: 2, name: 'CoilHeatingDXMultiSpeed_ashp')
      coil = OpenStudio::Model::CoilHeatingDXMultiSpeed.new(model)
      coil.setName(name)
      coil.setFuelType('Electricity') if coil.respond_to?(:setFuelType)
      coil.setApplyPartLoadFractiontoSpeedsGreaterthan1(false)
      coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-10.0)
      stages.times { coil.addStage(dx_heating_stage(model)) }
      coil
    end

    # @return [OpenStudio::Model::CoilHeatingDXMultiSpeedStageData]
    def self.dx_heating_stage(model)
      stage = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(model)
      stage.setHeatingCapacityFunctionofTemperatureCurve(Curves.build(model, 'DXHEAT-NECB2011-REF-CAPFT'))
      stage.setHeatingCapacityFunctionofFlowFractionCurve(Curves.build(model, 'DXHEAT-NECB2011-REF-CAPFFLOW'))
      stage.setEnergyInputRatioFunctionofTemperatureCurve(Curves.build(model, 'DXHEAT-NECB2011-REF-EIRFT'))
      stage.setEnergyInputRatioFunctionofFlowFractionCurve(Curves.build(model, 'DXHEAT-NECB2011-REF-EIRFFLOW'))
      stage.setPartLoadFractionCorrelationCurve(Curves.build(model, 'DXHEAT-NECB2011-REF-PLFFPLR'))
      stage.autosizeGrossRatedHeatingCapacity
      stage.autosizeRatedAirFlowRate
      stage
    end

    # Supply-path components of an air loop with every AirLoopHVACUnitarySystem
    # container REPLACED by the fan and coils it holds.
    #
    # Staged reference systems (8.4.4.9.(7)/8.4.4.10.(8)) put the fan and coils
    # INSIDE an AirLoopHVACUnitarySystem — a multispeed coil cannot sit bare on
    # an air loop — so a plain `supplyComponents` scan silently stops finding
    # them. Every consumer that looks for coils or fans on a supply path must go
    # through here.
    #
    # @param air_loop [OpenStudio::Model::AirLoopHVAC]
    # @return [Array<OpenStudio::Model::ModelObject>]
    def self.supply_components(air_loop)
      air_loop.supplyComponents.flat_map do |comp|
        unitary = comp.to_AirLoopHVACUnitarySystem
        unitary.is_initialized ? unitary_children(unitary.get) : [comp]
      end
    end

    # Rewrite a unitary's UnitarySystemPerformanceMultispeed supply-airflow
    # ratios from the CURRENT stage counts of its coils: stage k of N gets
    # ratio k/N, per mode, so E+ autosizes stage k to k/N of the top stage
    # (the equal capacity increments of 8.4.4.9.(7)/8.4.4.10.(8)).
    #
    # Heating and cooling stage counts are independent — the SDK writes each
    # mode's speed count from its own coil, and the shorter mode's trailing
    # ratios are pinned at 1.0. Single-stage (or absent) coils count as 1.
    #
    # @param unitary [OpenStudio::Model::AirLoopHVACUnitarySystem]
    # @return [Integer, nil] number of ratio fields written, nil without a performance object
    def self.set_stage_flow_ratios(unitary)
      performance = unitary.designSpecificationMultispeedObject
      return nil if performance.empty?

      performance = performance.get
      heating = stage_count(unitary.heatingCoil)
      cooling = stage_count(unitary.coolingCoil)
      fields = (1..[heating, cooling].max).map do |k|
        OpenStudio::Model::SupplyAirflowRatioField.new([k.to_f / heating, 1.0].min,
                                                       [k.to_f / cooling, 1.0].min)
      end
      performance.setSupplyAirflowRatioFields(fields)
      fields.size
    end

    # @return [Integer] stage count of a (possibly absent) multispeed coil; 1 otherwise
    def self.stage_count(optional_coil)
      coil = multispeed(optional_coil)
      coil.nil? ? 1 : [coil.stages.size, 1].max
    end

    # The three staged coil types share no SDK base class, and a unitary's
    # coil accessors hand back an abstract HVACComponent — cast down or the
    # `stages` collection is invisible.
    #
    # @param optional_coil [OpenStudio::Model::OptionalHVACComponent, OpenStudio::Model::ModelObject, nil]
    # @return [OpenStudio::Model::ModelObject, nil] the concrete multispeed coil
    def self.multispeed(optional_coil)
      return nil if optional_coil.nil?

      coil = optional_coil.respond_to?(:is_initialized) ? (optional_coil.is_initialized ? optional_coil.get : nil) : optional_coil
      return nil if coil.nil?
      return coil if coil.respond_to?(:stages)

      %i[to_CoilCoolingDXMultiSpeed to_CoilHeatingDXMultiSpeed to_CoilHeatingGasMultiStage].each do |cast|
        next unless coil.respond_to?(cast)

        concrete = coil.send(cast)
        return concrete.get if concrete.is_initialized
      end
      nil
    end

    # Fan + coils held by a unitary system, in supply-path order.
    # @return [Array<OpenStudio::Model::ModelObject>]
    def self.unitary_children(unitary)
      [unitary.supplyFan, unitary.coolingCoil, unitary.heatingCoil, unitary.supplementalHeatingCoil]
        .filter_map { |opt| opt.is_initialized ? opt.get : nil }
    end

    # Air-loop heating coil by fuel keyword. Hot-water coils are attached to hw_loop.
    #
    # @param heating_coil_type [String] 'Electric', 'Gas'/'NaturalGas', 'Hot Water', 'DX'
    # @return [OpenStudio::Model::HVACComponent]
    def self.heating_coil(model, heating_coil_type, schedule, hw_loop: nil)
      case heating_coil_type
      when 'Electric', 'Electricity', 'FuelOilNo2'
        OpenStudio::Model::CoilHeatingElectric.new(model, schedule)
      when 'Gas', 'NaturalGas'
        OpenStudio::Model::CoilHeatingGas.new(model, schedule)
      when 'Hot Water', 'HotWater'
        raise(ArgumentError, 'a hot water loop is required for a Hot Water heating coil') if hw_loop.nil?

        coil = OpenStudio::Model::CoilHeatingWater.new(model, schedule)
        hw_loop.addDemandBranchForComponent(coil)
        coil
      when 'DX'
        dx_heating_single_speed(model, schedule)
      else
        raise(ArgumentError, "'#{heating_coil_type}' is not a valid heating coil type")
      end
    end
  end
end
