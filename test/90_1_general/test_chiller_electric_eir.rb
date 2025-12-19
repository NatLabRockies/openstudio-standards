require_relative '../helpers/minitest_helper'

class TestChillerElectricEir < Minitest::Test

  def test_chiller_electric_eir

    template = '90.1-2013'
    standard = Standard.build(template)

    # make a model
    model = OpenStudio::Model::Model.new

    # add a 75 ton air cooled chiller
    chiller = OpenStudio::Model::ChillerElectricEIR.new(model)
    target_cap_tons = 75
    target_cap_watts = OpenStudio.convert(target_cap_tons,"ton","W").get
    chiller.setReferenceCapacity(target_cap_watts)
    chiller.setName("#{target_cap_tons} ton WithoutCondenser Chiller")

    # run standard_minimum_cop
    min_full_load_cop = standard.chiller_electric_eir_standard_minimum_full_load_efficiency(chiller)

    # Minimum kW/ton = 1.188
    correct_kw_per_ton = 1.188
    correct_min_cop = OpenstudioStandards::HVAC.kw_per_ton_to_cop(correct_kw_per_ton)

    # Check the lookup against the truth
    assert_in_delta(min_full_load_cop, correct_min_cop, 0.1, "Expected #{correct_kw_per_ton} kW/ton AKA #{correct_min_cop.round(2)} COP.  Got #{min_full_load_cop} COP instead.")

  end

end
