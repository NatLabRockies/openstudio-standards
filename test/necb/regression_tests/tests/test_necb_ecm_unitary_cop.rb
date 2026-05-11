require_relative '../../../helpers/minitest_helper'
require_relative '../resources/parametric_test_creator'

# Sample test to demonstrate how to call the test creator
class ECM_Unitary_COP_Test < ParametricTestCreator
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
      unitary_cop:
        [
          "Carrier WeatherExpert",
          "Lennox Model L Ultra High Efficiency"
        ]
    }
  self.generate_tests(params)
end
