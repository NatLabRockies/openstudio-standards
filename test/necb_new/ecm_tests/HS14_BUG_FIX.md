# HS14 GSHP Efficiency Bug Fix

**Date:** 2026-05-08  
**Status:** ✅ FIXED  
**Issue:** HS14 efficiency test was failing due to bug in ECM code

---

## Problem

The `apply_efficiency_ecm_hs14_cgshp_fancoils` method in `/lib/openstudio-standards/standards/necb/ECMS/hvac_systems.rb` had a bug at lines 2001-2003 that caused a `NoMethodError`:

```
NoMethodError: undefined method 'strip' for nil:NilClass
```

---

## Root Cause

The original code attempted to remove the last 3 words from a chiller name (e.g., "ChillerWaterCooled Hermetic Screw 500kW" → "ChillerWaterCooled") by using `chomp!`:

```ruby
# BUGGY CODE (lines 2001-2003)
new_chlr_name = chiller_water_cooled.name.to_s.chomp!(chiller_water_cooled.name.to_s.split.last).strip
new_chlr_name = new_chlr_name.chomp!(new_chlr_name.split.last).strip
new_chlr_name = new_chlr_name.chomp!(new_chlr_name.split.last).strip
```

**The problem:** 
- `chomp!` is a **mutating** method that modifies the string in-place
- It returns `nil` if no changes were made
- When the first `chomp!` returns `nil`, calling `.strip` on `nil` causes the error

---

## Solution

Replaced the buggy code with a cleaner, array-based approach:

```ruby
# FIXED CODE
# Remove last 3 words from chiller name (e.g., "ChillerWaterCooled Hermetic Screw 500kW" → "ChillerWaterCooled")
name_parts = chiller_water_cooled.name.to_s.split
new_chlr_name = name_parts[0...-3].join(' ').strip
# If name has fewer than 3 parts, just use the first word
new_chlr_name = name_parts[0] if new_chlr_name.empty? && !name_parts.empty?
chiller_water_cooled.setName(new_chlr_name)
```

**How it works:**
1. Split the name into words: `["ChillerWaterCooled", "Hermetic", "Screw", "500kW"]`
2. Take all but last 3 elements: `["ChillerWaterCooled"]`
3. Join back together: `"ChillerWaterCooled"`
4. Fallback: if name has < 3 parts, use first word

---

## Files Changed

### Modified
- `/lib/openstudio-standards/standards/necb/ECMS/hvac_systems.rb` (lines 1998-2004)
  - Fixed buggy `chomp!` chain
  - Added comment explaining the logic

### Test Updated
- `/test/necb_new/ecm_tests/test_ecm_hvac_systems.rb`
  - Removed `skip` from `test_hs14_efficiency_application`
  - Test now fully enabled with sizing run

---

## Test Results

### Before Fix
```
32 tests, 139 assertions, 0 failures, 0 errors, 1 skips
Runtime: ~126 seconds

test_hs14_efficiency_application - SKIP (bug in ECM code)
```

### After Fix
```
32 tests, 141 assertions, 0 failures, 0 errors, 0 skips
Runtime: ~134 seconds

test_hs14_efficiency_application - PASS (6.70s)
```

**Result:** 100% test pass rate achieved! ✅

---

## Why This Bug Existed

The original developer likely intended to use `chomp` (non-mutating) or `sub` (substitution), but used `chomp!` (mutating) instead. The mutating version returns `nil` when no changes occur, which breaks method chaining.

**Ruby gotcha:**
```ruby
# Non-mutating (safe for chaining)
"hello".chomp("x").strip  # => "hello" (chomp returns the string)

# Mutating (dangerous for chaining)
"hello".chomp!("x").strip  # => NoMethodError (chomp! returns nil)
```

---

## Verification

The test now verifies:
1. ✅ HS14 system creation (ground-source heat pump + fan coils)
2. ✅ Sizing simulation runs successfully
3. ✅ Efficiency application completes without error
4. ✅ Chiller name is updated correctly
5. ✅ Plant loops and fan coils exist after efficiency application

---

## Impact

- **Bug severity:** High (blocked testing of HS14 efficiency application)
- **Fix complexity:** Low (simple code replacement)
- **Test impact:** +1 test passing (31/32 → 32/32)
- **Coverage impact:** +~80 lines tested (HS14 efficiency method)
- **Time to fix:** ~30 minutes

---

## Lessons Learned

1. **Avoid mutating methods in chains:** Use non-mutating versions (`chomp` not `chomp!`)
2. **Prefer explicit code over clever tricks:** Array manipulation is clearer than string chomping
3. **Add comments for non-obvious logic:** The "remove last 3 words" intent wasn't obvious
4. **Test coverage catches bugs early:** This bug would have been caught in production without tests

---

## Related Tests

All HS14 tests now passing:
- ✅ test_hs14_system_creation (2.52s)
- ✅ test_hs14_ground_heat_exchanger (2.81s)
- ✅ test_hs14_fan_coils_configuration (2.63s)
- ✅ test_hs14_cold_climate (2.59s)
- ✅ test_hs14_efficiency_application (6.70s) - **FIXED**

---

## Complete!

Phase 8 ECM HVAC testing is now 100% complete with all 32 tests passing and 0 bugs remaining.
