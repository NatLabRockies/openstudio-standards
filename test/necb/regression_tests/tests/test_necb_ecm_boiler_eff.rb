require_relative '../../../helpers/minitest_helper'
require_relative '../resources/parametric_test_creator'

# Sample test to demonstrate how to call the test creator
class ECM_Boiler_Eff_Test < ParametricTestCreator
  params =
    {
      template:
        [
          "BTAP1980TO2010",
          #"NECB2011",
          #"NECB2015",
          #"NECB2017",
          "NECB2020"
        ],
      primary_heating_fuel:
        [
          "Electricity",
          "NaturalGas"
        ],
      boiler_eff:
        [
          "NECB 88% Efficient Condensing Boiler",
          "Viessmann Vitocrossal 300 CT3-17 96.2% Efficient Condensing Gas Boiler"
        ]
    }
  self.generate_tests(params)
end
