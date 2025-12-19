require_relative 'helpers/dcv_test_helper'

class NECB_DCV_FSR_2011_Tests < Minitest::Test
  include DCVTestHelper

  def setup
    setup_dcv_test
  end

  def test_dcv_occ_fsr_necb2011
    run_dcv_test('NECB2011', 'FullServiceRestaurant', 'Occupancy_based_DCV')
  end
end