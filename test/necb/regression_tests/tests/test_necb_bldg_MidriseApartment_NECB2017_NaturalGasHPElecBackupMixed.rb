require_relative '../../../helpers/minitest_helper'
require_relative '../resources/regression_helper'

class Test_MidriseApartment_NECB2017_NaturalGasHPElecBackupMixed < NECBRegressionHelper
  def setup()
    super()
  end

  def test_NECB2017_MidriseApartment_regression_NaturalGasHPElecBackupMixed()
    result, diff = create_model_and_regression_test(
      building_type:        'MidriseApartment',
      primary_heating_fuel: 'NaturalGasHPElecBackupMixed', 
      epw_file:             'CAN_AB_Calgary.Intl.AP.718770_CWEC2020.epw',
      template:             'NECB2017', 
      run_simulation:       false
    )
    if result == false
      puts "JSON terse listing of diff-errors."
      puts diff
      puts "Pretty listing of diff-errors for readability."
      puts JSON.pretty_generate( diff )
      puts "You can find the saved json diff file here test/necb/regression_tests/expected/MidriseApartment-NECB2017-NaturalGasHPElecBackupMixed_CAN_AB_Calgary_diffs.json"
      puts "outputing errors here. "
      puts diff["diffs-errors"] if result == false
    end
    assert(result, diff)
  end
end
