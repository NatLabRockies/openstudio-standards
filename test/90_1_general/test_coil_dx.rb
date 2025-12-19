require_relative '../helpers/minitest_helper'

class TestCoilDX < Minitest::Test

  def test_coil_cooling_dx_single_speed

    template = '90.1-2013'
    standard = Standard.build(template)

    # make a model
    model = OpenStudio::Model::Model.new

    # add a 7 ton DX coil
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    cap_tons = 7
    cap_watts = OpenStudio.convert(cap_tons,"ton","W").get
    coil.setRatedTotalCoolingCapacity(cap_watts)

    # run standard_minimum_cop
    min_cop = standard.coil_cooling_dx_single_speed_standard_minimum_cop(coil, template)

    # Minimum EER = 11.0
    correct_eer = 11.0
    correct_min_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(correct_eer)

    # Check the lookup against the truth
    assert_in_delta(min_cop, correct_min_cop, 0.1, "Expected #{correct_eer} EER AKA #{correct_min_cop.round(2)} COP.  Got #{min_cop} COP instead.")

  end

  def test_coil_cooling_dx_two_speed

    template = '90.1-2013'
    standard = Standard.build(template)

    # make a model
    model = OpenStudio::Model::Model.new

    # add a 7 ton DX coil
    coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
    cap_tons = 7
    cap_watts = OpenStudio.convert(cap_tons,"ton","W").get
    coil.setRatedHighSpeedTotalCoolingCapacity(OpenStudio::OptionalDouble.new(cap_watts))

    # run standard_minimum_cop
    min_cop = standard.coil_cooling_dx_two_speed_standard_minimum_cop(coil)

    # Minimum EER = 11.0
    correct_eer = 11.0
    correct_min_cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(correct_eer)

    # Check the lookup against the truth
    assert_in_delta(min_cop, correct_min_cop, 0.1, "Expected #{correct_eer} EER AKA #{correct_min_cop.round(2)} COP.  Got #{min_cop} COP instead.")

  end

  # @todo coil cooling DX multi speed

  def test_coil_heating_dx_single_speed
    template = '90.1-2013'
    standard = Standard.build(template)

    # make a model
    model = OpenStudio::Model::Model.new

    # add a 7 ton DX cooling coil
    # and a 3 ton DX heating coil
    # and an electric heating coil
    # to a unitary system
    fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)

    clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    clg_cap_tons = 7
    clg_cap_watts = OpenStudio.convert(clg_cap_tons,"ton","W").get
    clg_coil.setRatedTotalCoolingCapacity(clg_cap_watts)

    htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    htg_cap_tons = 3
    htg_cap_watts = OpenStudio.convert(htg_cap_tons,"ton","W").get
    htg_coil.setRatedTotalHeatingCapacity(htg_cap_watts)

    supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOnDiscreteSchedule)

    unitary_system = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(model,
                                                                               model.alwaysOnDiscreteSchedule,
                                                                               fan,
                                                                               htg_coil,
                                                                               clg_coil,
                                                                               supplemental_htg_coil)

    # run standard_minimum_cop
    min_cop = standard.coil_heating_dx_single_speed_standard_minimum_cop(htg_coil, true, equipment_type = true)

    # Minimum COPH = 3.3
    correct_coph = 3.3
    correct_min_cop = OpenstudioStandards::HVAC.cop_heating_to_cop_heating_no_fan(correct_coph, clg_cap_watts)

    # Check the lookup against the truth
    assert_in_delta(min_cop, correct_min_cop, 0.1, "Expected #{correct_coph} COPH AKA #{correct_min_cop.round(2)} COP.  Got #{min_cop} COP instead.")

  end

  def test_coil_heating_dx_single_speed_2019
    template = '90.1-2019'
    standard = Standard.build(template)

    # make a model
    model = OpenStudio::Model::Model.new

    # add a 1 ton DX cooling coil
    # and a 3 ton DX heating coil
    # and an electric heating coil
    # to a unitary system
    fan = OpenStudio::Model::FanOnOff.new(model, model.alwaysOnDiscreteSchedule)

    clg_coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    clg_cap_tons = 1
    clg_cap_watts = OpenStudio.convert(clg_cap_tons,"ton","W").get
    clg_coil.setRatedTotalCoolingCapacity(clg_cap_watts)

    htg_coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(model)
    htg_cap_tons = 3
    htg_cap_watts = OpenStudio.convert(htg_cap_tons,"ton","W").get
    htg_coil.setRatedTotalHeatingCapacity(htg_cap_watts)

    supplemental_htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOnDiscreteSchedule)

    unitary_system = OpenStudio::Model::AirLoopHVACUnitaryHeatPumpAirToAir.new(model,
                                                                               model.alwaysOnDiscreteSchedule,
                                                                               fan,
                                                                               htg_coil,
                                                                               clg_coil,
                                                                               supplemental_htg_coil)

    # run standard_minimum_cop
    min_eff = standard.coil_heating_dx_single_speed_standard_minimum_cop(htg_coil, true, equipment_type = true)

    # HSPF 6.7
    correct_min_eff =  OpenstudioStandards::HVAC.hspf_to_cop_no_fan(6.7)

    # Check the lookup against the truth
    assert_in_delta(min_eff, correct_min_eff, 0.1, "Expected #{correct_min_eff} COPH AKA #{correct_min_eff.round(2)} COP.  Got #{min_eff} COP instead.")

  end

  # @todo coil heating DX multi speed

end
