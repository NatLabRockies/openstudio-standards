require_relative '../../../helpers/minitest_helper'
require_relative '../resources/parametric_test_creator'

# Sample test to demonstrate how to call the test creator
class ECM_HS09_CCASHP_Baseboard_Test < ParametricTestCreator
  params =
    {
      template:
        [
          "BTAP1980TO2010",
          #"NECB2011",
          # "NECB2015",
          #"NECB2017",
          "NECB2020"
        ],
      primary_heating_fuel:
        [
          "Electricity",
          "NaturalGas"
        ],
      ecm_system_name:
        [
          "HS09_CCASHP_Baseboard"
        ]
    }
  self.generate_tests(params)
end