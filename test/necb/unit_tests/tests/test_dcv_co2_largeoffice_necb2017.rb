require_relative 'helpers/dcv_test_helper'

class NECB_DCV_LargeOffice_2017_Tests < Minitest::Test
  include DCVTestHelper

  def setup
    setup_dcv_test
  end

  def test_dcv_co2_largeoffice_necb2017
    run_dcv_test('NECB2017', 'LargeOffice', 'CO2_based_DCV')
  end
end