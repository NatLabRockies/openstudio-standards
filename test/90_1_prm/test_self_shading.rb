require_relative '../helpers/minitest_helper'
require_relative 'prm_check'
require_relative 'prm_test_model_generator'
# Part of the ASHRAE 90.1 Appendix G Performance Rating Method (PRM) baseline automation implementation test suite
class AppendixGPRMTests < Minitest::Test
  # Check that self-shading is disabled in the baseline models
  def test_self_shading
    model_hash = prm_test_helper('self_shading', require_prototype = false, require_baseline = true)
    check_self_shading(model_hash['baseline'])
  end
end
