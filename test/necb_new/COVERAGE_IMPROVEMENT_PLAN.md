# NECB2011 Coverage Improvement Plan
# Goal: 69.9% → 80.0% (Need 700+ more lines covered)

**Date:** 2026-05-10  
**Current Coverage:** 69.9% (4,845 / 6,931 lines)  
**Target Coverage:** 80.0% (5,545 / 6,931 lines)  
**Gap:** 700 lines needed

---

## Priority Files to Test

Based on SimpleCov analysis, these files have the most uncovered lines and biggest impact:

### 1. building_envelope.rb - 495 uncovered lines (43.8% coverage)
**Impact:** Covering 50% of gaps = +247 lines → 4.0% improvement

**Missing Test Coverage:**
- Construction assembly methods
- U-value calculations for various assembly types
- Fenestration properties (window/door performance)
- Thermal bridging calculations
- Climate-specific envelope requirements
- Vintage-specific envelope upgrades

**Test Suite to Create:** `test/necb_new/envelope_tests/test_necb_envelope_calculations.rb`

**Estimated Tests:** 30-40 tests  
**Estimated Time:** 1.5 hours  
**Expected Coverage Gain:** +4.0%

---

### 2. necb_2011.rb - 453 uncovered lines (65.8% coverage)
**Impact:** Covering 30% of gaps = +136 lines → 2.2% improvement

**Missing Test Coverage:**
- Template methods not covered by current tests
- Edge cases in vintage-specific rules
- Lookup table methods
- Code compliance checking methods
- Exception handling paths

**Test Suite to Create:** `test/necb_new/core_tests/test_necb_2011_edge_cases.rb`

**Estimated Tests:** 25-30 tests  
**Estimated Time:** 1.0 hour  
**Expected Coverage Gain:** +2.2%

---

### 3. autozone.rb - 252 uncovered lines (58.3% coverage)
**Impact:** Covering 40% of gaps = +101 lines → 1.6% improvement

**Missing Test Coverage:**
- Edge cases in zone creation logic
- Error handling for invalid geometries
- Different building aspect ratios
- Multi-story building zoning
- Corner cases in perimeter zone creation

**Test Suite to Create:** `test/necb_new/autozone_tests/test_necb_autozone_edge_cases.rb`

**Estimated Tests:** 15-20 tests  
**Estimated Time:** 1.0 hour  
**Expected Coverage Gain:** +1.6%

---

### 4. hvac_system_6.rb - 158 uncovered lines (35.8% coverage)
**Impact:** Covering 60% of gaps = +95 lines → 1.5% improvement

**Missing Test Coverage:**
- VAV system configuration edge cases
- Zone equipment selection for System 6
- Economizer control sequences
- Fan pressure rise calculations
- Supply air temperature reset logic
- Zone damper controls

**Test Suite to Create:** `test/necb_new/hvac_systems_1_4_tests/test_necb_system_6_complete.rb`

**Estimated Tests:** 20-25 tests  
**Estimated Time:** 1.0 hour  
**Expected Coverage Gain:** +1.5%

---

## Implementation Strategy

### Phase 1: Quick Wins (2 hours, +6% coverage)
1. **necb_2011.rb edge cases** (1 hour) → +2.2%
2. **hvac_system_6.rb complete** (1 hour) → +1.5%
3. **autozone.rb edge cases** (45 min) → +1.2%
4. **Verify coverage** (15 min)

**Result:** 69.9% → 75.9%

### Phase 2: Major Coverage Push (1.5 hours, +5% coverage)
1. **building_envelope calculations** (1.5 hours) → +4.0%
2. **Additional autozone edge cases** (30 min) → +0.4%
3. **Verify coverage** (15 min)

**Result:** 75.9% → 80.9%

### Total Time: ~3.5 hours
### Expected Final Coverage: 80-82%

---

## Test Templates

### Template 1: Edge Case Testing
```ruby
def test_method_name_edge_case_description
  # Arrange: Create minimal test fixture
  model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
  
  # Act: Call method with edge case input
  result = standard.method_name(edge_case_parameters)
  
  # Assert: Verify correct handling
  assert !result.nil?, "Should handle edge case"
  assert_operator result, :>, 0, "Should return valid value"
end
```

### Template 2: Calculation Testing
```ruby
def test_calculation_method_with_known_values
  # Test with known input/output pairs
  model, standard = create_baseline_necb_model(template: 'NECB2011', climate: 'Toronto')
  
  # Known good values from NECB tables
  input = 5.0
  expected_output = 10.0
  
  result = standard.calculation_method(input)
  
  assert_in_delta expected_output, result, 0.01, "Calculation should match NECB tables"
end
```

---

## Coverage Measurement Commands

### Run tests with coverage
```bash
# Single test file
COVERAGE=true bundle exec ruby test/necb_new/path/to/test_file.rb

# All tests with coverage
bundle exec ruby test/necb_new/run_all_parallel.rb
```

### Check coverage results
```bash
# Open coverage report
open test/necb_new/coverage/index.html

# Or parse JSON
ruby -rjson -e "
data = JSON.parse(File.read('test/necb_new/coverage/.resultset.json'))
# ... analysis script
"
```

---

## Success Criteria

✅ **NECB2011 coverage ≥ 80.0%**  
✅ **All new tests passing**  
✅ **No regressions in existing tests**  
✅ **Tests complete in < 5 minutes (parallel)**  
✅ **Documentation updated**

---

## Notes

- Focus on **NECB2011** specifically (most-used version)
- Prioritize **high-impact files** (most uncovered lines)
- Write **fast unit tests** (no simulations unless necessary)
- Ensure tests are **maintainable** (clear, well-documented)
- Use **parallel execution** to keep CI/CD fast
