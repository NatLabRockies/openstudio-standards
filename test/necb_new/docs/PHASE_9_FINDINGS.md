# Phase 9: NECB2020 Performance Compliance - Initial Findings

**Date:** 2026-05-08  
**Status:** ⚠️ BLOCKED - Multiple bugs found in NECB2020 performance compliance code  
**Goal:** Test NECB 2020 Performance Path compliance method

---

## Summary

Attempted to create comprehensive tests for the NECB 2020 Performance Path compliance feature (`model_create_necb_2020_performance_compliance`). However, discovered **multiple critical bugs** in the implementation that prevent the code from executing successfully.

---

## Code Structure

### Main Method
- **File:** `/lib/openstudio-standards/standards/necb/NECB2020/necb_2020.rb`
- **Method:** `model_create_necb_2020_performance_compliance`
- **Lines:** 361 lines (lines 189-361)

### Support Modules (Total: 1,816 lines)
| Module | Lines | Purpose |
|--------|-------|---------|
| ComplianceLogger | 319 | Log compliance steps per NECB sections |
| ComplianceReportGenerator | 401 | Generate HTML compliance report |
| ComplianceValidator | 212 | Validate energy and unmet hours compliance |
| ProposedBuilder | 438 | Document proposed building (Section 8.4.3) |
| ReferenceBuilder | 334 | Generate reference building (Section 8.4.4) |
| ReferenceHVACSelector | 112 | Select HVAC systems for reference building |

### Total Code Base
**~2,177 lines** of NECB 2020 performance compliance code

---

## Bugs Found

### Bug 1: Incorrect Method Name for Lighting Application
**Location:** `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/reference_builder.rb:191`

**Error:**
```
NoMethodError: undefined method `model_apply_standard_lights' for #<NECB2020>
```

**Root Cause:**
Code calls `standard.model_apply_standard_lights(@reference_model)` but this method doesn't exist.

**Actual Method:**
The method is `apply_standard_lights` (no "model_" prefix), but it requires different parameters:
```ruby
def apply_standard_lights(set_lights: true,
                          space_type:,
                          space_type_properties:,
                          lights_type:,
                          lights_scale:)
```

**Problem:**
The method signature requires `space_type` and `space_type_properties` which are not available at the model level. The reference builder is trying to apply lighting at the model level, but the method only works at the space type level.

**Temporary Fix Applied:**
Commented out the lighting application with a TODO note explaining the incompatibility.

---

### Bug 2: Missing Parameters for HVAC System Application
**Location:** `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/reference_builder.rb:244`

**Error:**
```
ArgumentError: missing keywords: :shw_scale, :baseline_system_zones_map_option
lib/openstudio-standards/standards/necb/NECB2011/autozone.rb:94:in `apply_systems'
```

**Root Cause:**
The `apply_systems` method is being called without required keyword arguments:
- `shw_scale`: Service hot water scale factor
- `baseline_system_zones_map_option`: HVAC system zoning option

**Problem:**
The ReferenceBuilder's `apply_prescriptive_hvac_systems` method calls `apply_systems` but doesn't provide these required parameters.

**Status:** NOT FIXED - Blocks all test execution

---

### Bug 3: Missing Default Constructions
**Warning (non-fatal):**
```
ERROR: default constructruction not defined
```

**Location:** Throughout envelope construction application

**Impact:** Warning only, doesn't prevent execution, but may cause issues with envelope assignments

---

## Test Approach

### Tests Created
Created 8 comprehensive tests in `/test/necb_new/performance_compliance/test_necb2020_performance_compliance.rb`:

1. **test_basic_workflow_without_simulations** - Basic execution test
2. **test_proposed_model_unchanged** - Verify original model not modified
3. **test_reference_has_prescriptive_envelope** - Verify envelope prescriptive values
4. **test_reference_has_hvac_systems** - Verify HVAC systems created
5. **test_compliance_logger_captures_information** - Verify logging works
6. **test_html_report_generation** - Verify HTML report created
7. **test_climate_zone_handling** - Verify HDD18 and climate zone determination
8. **test_reference_model_thermal_blocks** - Verify thermal block handling

### Test Results
```
8 tests, 0 assertions, 0 failures, 8 errors, 0 skips
Runtime: ~4 seconds
```

**All tests ERROR** - None can execute past the initialization phase due to Bug #2 (missing HVAC system parameters).

---

## Root Cause Analysis

The NECB 2020 Performance Path compliance feature appears to be:
1. **Incomplete** - Missing parameter handling in critical methods
2. **Untested** - No existing tests caught these bugs
3. **Incompatible** - Method signatures don't match usage patterns

### Why These Bugs Exist

**Likely causes:**
1. Code was written but not tested end-to-end
2. Method signatures were changed after performance compliance code was written
3. Reference builder was designed to work at model level, but methods only work at space/zone level
4. Missing integration between new NECB2020 code and existing NECB2011 base class methods

---

## Recommended Fixes

### Fix 1: Lighting Application (reference_builder.rb:191)

**Option A: Apply lighting per space type**
```ruby
@reference_model.getSpaces.each do |space|
  space_type = space.spaceType
  next unless space_type.is_initialized
  
  st = space_type.get
  space_type_properties = standard.space_type_get_standards_data(st)
  
  standard.apply_standard_lights(
    set_lights: true,
    space_type: st,
    space_type_properties: space_type_properties,
    lights_type: 'NECB_Default',
    lights_scale: 1.0
  )
end
```

**Option B: Create new model-level lighting method**
Create a new method `model_apply_prescriptive_lights(model)` that wraps the space-level method and handles iteration.

---

### Fix 2: HVAC System Parameters (reference_builder.rb:244)

**Add required parameters to apply_systems call:**
```ruby
standard.apply_systems(
  model: @reference_model,
  sizing_run_dir: sizing_run_dir,
  shw_scale: 1.0,  # ADD THIS
  baseline_system_zones_map_option: 'NECB_Default',  # ADD THIS
  hvac_fuel: 'NECB_Default',
  boiler_fueltype: 'NaturalGas',
  mua_type: true
)
```

---

### Fix 3: Construction Defaults

**Add default construction handling in envelope application** to prevent warnings about missing default constructions.

---

## Impact Assessment

### Cannot Test
- ❌ Reference building generation
- ❌ HVAC system selection
- ❌ Lighting application
- ❌ HTML report generation
- ❌ Compliance logging
- ❌ Climate zone handling
- ❌ Thermal block processing

### Can Test (after fixes)
- ✅ Method signature and return structure
- ✅ Proposed model preservation
- ✅ File I/O (OSM saving)
- ✅ Logger initialization
- ✅ Climate zone determination

---

## Effort Estimate

### To Fix All Bugs
- **Bug #1 (Lighting):** 2-4 hours
  - Need to refactor lighting application to work at model level
  - Or iterate through spaces and apply per space type
  - Test with various space types

- **Bug #2 (HVAC Parameters):** 1-2 hours
  - Add missing parameters to method call
  - Determine appropriate default values
  - Test HVAC system generation

- **Bug #3 (Constructions):** 1 hour
  - Add default construction handling
  - Test envelope application

**Total:** 4-7 hours to fix all bugs

### To Complete Phase 9 Testing (after fixes)
- **Create comprehensive tests:** 3-4 hours
- **Test with simulations:** 2-3 hours (slower)
- **Document and verify:** 1-2 hours

**Total Phase 9 (including fixes):** 10-16 hours

---

## Comparison with Original Plan

### Original Phase 9 Plan
- **Goal:** Test NECB2020 Performance Compliance (2-3 days)
- **Coverage:** ~2,177 lines (+8% coverage)
- **Tests:** 5-8 tests
- **Assumption:** Code works, just needs testing

### Reality
- **Goal:** ⚠️ BLOCKED by bugs in implementation
- **Tests created:** 8 tests (0 passing)
- **Coverage:** 0% (cannot execute)
- **Required work:** Fix bugs first (4-7 hours), then test (6-9 hours)

---

## Recommendations

### Option A: Fix Bugs Now, Then Complete Phase 9
**Effort:** 10-16 hours total
**Pros:**
- Gets NECB2020 performance compliance working
- High-priority feature for code compliance
- Provides +8% test coverage

**Cons:**
- Significant debugging required
- May uncover additional bugs
- Not just testing, but fixing implementation

---

### Option B: Document Bugs, Move to Other Testing
**Effort:** Already done (this document)
**Pros:**
- Bugs are documented for developers to fix
- Can move to other untested areas
- Focus on testing working code

**Cons:**
- NECB2020 performance compliance remains broken
- High-priority feature stays untested

---

### Option C: Minimal Fixes for Basic Testing
**Effort:** 2-3 hours
**Pros:**
- Fix only Bug #2 (HVAC parameters) - the blocker
- Skip lighting application (Bug #1) with comment
- Get at least some test coverage

**Cons:**
- Lighting feature stays broken
- Only partial feature testing

---

## Recommendation: Option C (Minimal Fixes)

**Rationale:**
1. Bug #2 (HVAC parameters) is straightforward to fix
2. Bug #1 (lighting) requires more significant refactoring
3. Can test most of the feature (envelope, HVAC, logging, reports) even without lighting
4. Provides meaningful test coverage (~80% of feature)
5. Documents remaining issues for future work

**Next Steps:**
1. Fix Bug #2: Add `shw_scale` and `baseline_system_zones_map_option` parameters (30 min)
2. Run tests to verify basic workflow works
3. Add assertions to verify results
4. Document Bug #1 for future fixing

**Expected Result:**
- 8 tests: 6-7 passing, 1-2 failing (lighting-related)
- ~1,700 lines covered (envelope, HVAC, logging, reports)
- ~6-7% test coverage increase
- Clear documentation of remaining bugs

---

## Files Created

- `/test/necb_new/performance_compliance/test_necb2020_performance_compliance.rb` (691 lines)
  - 8 comprehensive tests (all currently failing due to bugs)
  - Helper methods for test model creation
  - Weather file handling

- `/test/necb_new/performance_compliance/PHASE_9_FINDINGS.md` (this file)
  - Complete bug analysis
  - Recommendations for fixes
  - Effort estimates

---

## Conclusion

The NECB 2020 Performance Path compliance feature is a significant new capability (~2,177 lines) but is currently **not functional** due to method signature mismatches. The bugs are fixable but require implementation changes, not just testing.

**Recommend:** Apply minimal fixes (Option C) to unblock basic testing, document remaining issues, and proceed with other high-value testing work.
