require_relative 'helpers/insuite_central_doas_test_helper'

class NECB_InsuiteCentralDOAS_LargeHotel_OneSysPerDwellingUnit_Tests < Minitest::Test
  include InsuiteCentralDOASTestHelper

  def setup
    setup_insuite_doas_test
  end

  def test_insuite_central_doas_largehotel_one_sys_per_dwelling_unit
    run_insuite_doas_test('LargeHotel', 'one_sys_per_dwelling_unit')
  end
end