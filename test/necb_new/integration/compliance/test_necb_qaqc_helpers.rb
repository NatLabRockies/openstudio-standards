require_relative '../../test_helper'

# Pure-Ruby unit tests for QAQC helper methods that do not require a sized model
# or SQL file. Targets lib/openstudio-standards/standards/necb/NECB2011/qaqc/necb_qaqc.rb
class TestNecbQaqcHelpers < Minitest::Test
  def setup
    @standard = Standard.build('NECB2011')
  end

  # ===== necb_section_test =====

  def test_necb_section_test_records_pass
    qaqc = { information: [], errors: [], unique_errors: [] }
    @standard.necb_section_test(qaqc, 10.0, '==', 10.0, '1.1.1.1', 'identity check')
    assert_equal 1, qaqc[:information].size
    assert qaqc[:information].first.include?('TEST-PASS')
    assert_equal 0, qaqc[:errors].size
  end

  def test_necb_section_test_records_failure
    qaqc = { information: [], errors: [], unique_errors: [] }
    @standard.necb_section_test(qaqc, 10.0, '==', 11.0, '1.1.1.1', 'mismatch')
    assert_equal 0, qaqc[:information].size
    assert_equal 1, qaqc[:errors].size
    assert qaqc[:errors].first.include?('TEST-FAIL')
    assert_equal 1, qaqc[:unique_errors].size
  end

  def test_necb_section_test_skips_unique_for_minus_one
    qaqc = { information: [], errors: [], unique_errors: [] }
    @standard.necb_section_test(qaqc, 5.0, '==', -1.0, '1.1.1.1', 'sentinel')
    # Still recorded in errors, but not in unique_errors (which the convention
    # uses to suppress known-skip sentinels).
    assert_equal 1, qaqc[:errors].size
    assert_equal 0, qaqc[:unique_errors].size
  end

  def test_necb_section_test_applies_tolerance
    qaqc = { information: [], errors: [], unique_errors: [] }
    # 1.231 and 1.232 both round to 1.23 at 2 decimals
    @standard.necb_section_test(qaqc, 1.231, '==', 1.232, '1.1.1.1', 'tol check', 2)
    assert_equal 1, qaqc[:information].size, 'Values rounded to 2 decimals should compare equal'
  end

  def test_necb_section_test_supports_string_comparison
    qaqc = { information: [], errors: [], unique_errors: [] }
    @standard.necb_section_test(qaqc, 'NaturalGas', '==', 'NaturalGas', '1.1.1.1', 'string match')
    assert_equal 1, qaqc[:information].size
  end

  def test_necb_section_test_supports_inequality_operator
    qaqc = { information: [], errors: [], unique_errors: [] }
    @standard.necb_section_test(qaqc, 10.0, '<', 20.0, '1.1.1.1', 'lt check')
    assert_equal 1, qaqc[:information].size
  end

  # ===== check_boolean_value =====

  def test_check_boolean_value_accepts_true_strings
    %w[true t yes y 1].each do |val|
      assert_equal true, @standard.check_boolean_value(val, 'x'), "Expected '#{val}' to map to true"
    end
    assert_equal true, @standard.check_boolean_value('TRUE', 'x'), 'should be case insensitive'
  end

  def test_check_boolean_value_accepts_false_strings
    %w[false f no n 0].each do |val|
      assert_equal false, @standard.check_boolean_value(val, 'x'), "Expected '#{val}' to map to false"
    end
    assert_equal false, @standard.check_boolean_value('', 'x'), 'empty string should be false'
  end

  def test_check_boolean_value_raises_on_invalid
    assert_raises(ArgumentError) { @standard.check_boolean_value('maybe', 'x') }
  end

  # ===== merge_recursively =====
  # Note: merge_recursively only deep-merges hashes; on overlapping scalar keys
  # it recurses into the scalar and raises. Tests here only exercise the
  # well-defined (hash-only, non-overlapping scalar) cases.

  def test_merge_recursively_keeps_disjoint_keys
    a = { x: 1, only_in_a: 'a' }
    b = { y: 2, only_in_b: 'b' }
    result = @standard.merge_recursively(a, b)
    assert_equal 1, result[:x]
    assert_equal 2, result[:y]
    assert_equal 'a', result[:only_in_a]
    assert_equal 'b', result[:only_in_b]
  end

  def test_merge_recursively_combines_nested_disjoint_hashes
    a = { config: { left: 1 } }
    b = { config: { right: 2 } }
    result = @standard.merge_recursively(a, b)
    assert_equal({ left: 1, right: 2 }, result[:config])
  end
end
