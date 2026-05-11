require_relative '../helpers/minitest_helper'
require_relative './prm_check'
require_relative './prm_test_model_generator'
# Part of the ASHRAE 90.1 Appendix G Performance Rating Method (PRM) baseline automation implementation test suite
# @author Doug Maddox (PNNL), Jeremy Lerond (PNNL), and Yunyang Ye (PNNL)
class AppendixGPRMTests < Minitest::Test
  def test_f_c_factors
    model_hash = prm_test_helper('f_c_factors', require_prototype = false, require_baseline = true)
    check_f_c_factors(model_hash['baseline'])
  end
end
