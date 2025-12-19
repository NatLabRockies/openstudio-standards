require_relative 'helpers/insuite_central_doas_test_helper'

class NECB_InsuiteCentralDOAS_HighriseApartment_OneSysPerBldg_Tests < Minitest::Test
  include InsuiteCentralDOASTestHelper

  def setup
    setup_insuite_doas_test
  end

  def test_insuite_central_doas_highriseapartment_one_sys_per_bldg
    run_insuite_doas_test('HighriseApartment', 'one_sys_per_bldg')
  end
end