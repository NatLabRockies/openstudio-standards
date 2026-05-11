require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/create_doe_prototype_helper'
require_relative '../../../helpers/compare_models_helper'
require_relative '../../building_regression_tests/resources/regression_helper'

class Test_FullServiceRestaurant_With_ECM < NECBRegressionHelper
  def setup()
    super()
  end
  def test_BTAP1980TO2010_FullServiceRestaurant_regression_Electricity()
    result, diff = create_model_and_regression_test(building_type: 'FullServiceRestaurant',primary_heating_fuel: 'Electricity', ecm_system_name: 'HS11_ASHP_PTHP', epw_file:  'CAN_BC_Vancouver.Intl.AP.718920_CWEC2020.epw',template: 'NECB2011', run_simulation: false)
    if result == false
      puts "JSON terse listing of diff-errors."
      puts diff
      puts "Pretty listing of diff-errors for readability."
      puts JSON.pretty_generate( diff )
      puts diff["diffs-errors"] if result == false
    end
    assert(result, diff)
  end
end