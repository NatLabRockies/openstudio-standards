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
