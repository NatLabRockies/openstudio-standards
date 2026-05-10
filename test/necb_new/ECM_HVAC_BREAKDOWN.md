# ECM HVAC Systems - Testing Breakdown

**Date:** 2026-05-06  
**Purpose:** Break down 4,050-line ECM HVAC file into testable components

---

## You're Right - These ARE Extensively Used!

ECM HVAC systems are critical for:
- ✅ **Net-zero buildings** (heat pumps required)
- ✅ **NECB2020 compliance** (performance path with efficient systems)
- ✅ **High-performance buildings** (above-code targets)
- ✅ **Decarbonization** (electrification via heat pumps)
- ✅ **Energy modeling competitions** (ASHRAE building design competitions)

**Apologies for initial underestimation - let's test these properly!**

---

## Available ECM HVAC Systems (8 systems)

### Heat Pump Systems (Most Common - Priority 1)

#### HS11: ASHP + PTHP (Packaged Terminal Heat Pumps)
**Lines:** ~150 lines (add method + efficiency method)  
**Description:**
- Constant volume DOAS with air-source heat pump (heating/cooling) + electric backup
- Packaged-terminal air-source heat pumps with electric backup
- **Most common ECM** - used extensively in hotels, apartments, offices

**Complexity:** MEDIUM  
**Priority:** **HIGHEST** (most common heat pump ECM)

#### HS09: Cold-Climate ASHP + Baseboards
**Lines:** ~100 lines  
**Description:**
- Constant-volume reheat (single zone) or VAV with reheat (multi-zone)
- Cold-climate air-source heat pump (heating/cooling) + electric backup
- Electric or hot-water baseboards
- **Common in cold climates** (NECB Zones 6-8)

**Complexity:** MEDIUM  
**Priority:** **HIGH** (cold-climate applications)

#### HS12: Standard ASHP + Baseboards
**Lines:** ~100 lines  
**Description:**
- Constant-volume reheat (single zone) or VAV with reheat (multi-zone)
- Air-source heat pump (heating/cooling) + electric backup
- Electric or hot-water baseboards
- **Similar to HS09 but standard ASHP** (not cold-climate)

**Complexity:** MEDIUM  
**Priority:** MEDIUM-HIGH

---

### VRF Systems (Variable Refrigerant Flow - Priority 2)

#### HS08: Central Cooling ASHP + VRF
**Lines:** ~150 lines  
**Description:**
- Constant-volume DOAS with ASHP (heating/cooling) + electric backup
- Zonal terminal VRF units connected to outdoor VRF condenser
- Zonal electric or hot-water backup
- **Common in commercial offices**

**Complexity:** HIGH (VRF piping calculations)  
**Priority:** MEDIUM-HIGH

#### HS13: ASHP + VRF
**Lines:** ~100 lines  
**Description:**
- Constant-volume DOAS
- ASHP for heating/cooling + electric backup
- Zonal VRF terminal units + electric baseboards
- **Similar to HS08 with different DOAS config**

**Complexity:** HIGH  
**Priority:** MEDIUM

---

### Ground-Source Systems (Priority 3)

#### HS14: CGSHP + Fan Coils (Central Ground-Source Heat Pump)
**Lines:** ~200 lines (includes ground loop calculations)  
**Description:**
- Central ground-source heat pump (water loop)
- Four-pipe fan coils in zones
- Ground heat exchanger (GHX) loop
- **Complex but highly efficient** - used in institutional buildings

**Complexity:** VERY HIGH (GHX sizing, water loops)  
**Priority:** MEDIUM

#### HS15: CAWHP + Fan Coils (Condenser-Assisted Water Heating)
**Lines:** ~200 lines  
**Description:**
- Central air-to-water heat pump
- Four-pipe fan coils
- Condenser heat recovery for domestic hot water
- **Newer technology** - gaining popularity

**Complexity:** VERY HIGH (multi-loop coordination)  
**Priority:** MEDIUM-LOW

#### HS16: ASHP + CAWHP + Fan Coils
**Lines:** ~100 lines  
**Description:**
- Combination of HS12 and HS15 concepts
- Air-source heat pump + condenser-assisted water heating
- Four-pipe fan coils

**Complexity:** VERY HIGH  
**Priority:** LOW (less common)

---

## ECM Testing Strategy - Phased Approach

### Phase 8A: Most Common Heat Pump ECM (~3-4 hours)

**Test HS11 - ASHP + PTHP** (most widely used)

**Why start here:**
- ✅ Most common ECM in practice
- ✅ Medium complexity (not too simple, not too complex)
- ✅ Similar to Phase 6 System 1 (PTAC) tests - leverage existing patterns
- ✅ Clear success criteria

**Tests to create:**
1. Test HS11 system creation (components exist)
2. Test HS11 DOAS with ASHP (air loop + heat pump)
3. Test HS11 PTHP in zones (packaged terminal heat pumps)
4. Test HS11 efficiency application (COP values)
5. Test HS11 in cold climate (Yellowknife)
6. Test HS11 in mild climate (Vancouver)

**Estimated time:** 3-4 hours  
**Lines tested:** ~150 lines  
**Pattern:** Leverage Phase 6 integration test patterns

---

### Phase 8B: Cold-Climate Heat Pumps (~2-3 hours)

**Test HS09 - Cold-Climate ASHP + Baseboards**

**Why next:**
- ✅ Common in Canadian applications (NECB Zones 6-8)
- ✅ Similar structure to HS11
- ✅ Builds on HS11 test patterns
- ✅ Tests cold-climate heat pump performance data

**Tests to create:**
1. Test HS09 system creation
2. Test HS09 cold-climate ASHP (special curves)
3. Test HS09 VAV with reheat (multi-zone)
4. Test HS09 baseboards (electric or hot water)
5. Test HS09 efficiency application
6. Test HS09 in Zone 7/8 climate

**Estimated time:** 2-3 hours  
**Lines tested:** ~100 lines

---

### Phase 8C: Standard ASHP (~2 hours)

**Test HS12 - Standard ASHP + Baseboards**

**Why third:**
- ✅ Similar to HS09, faster to test
- ✅ Covers standard ASHP (not cold-climate specific)
- ✅ Can reuse HS09 test patterns

**Tests to create:**
1. Test HS12 system creation
2. Test HS12 standard ASHP (different curves than HS09)
3. Test HS12 efficiency application
4. Test HS12 across climates

**Estimated time:** 2 hours  
**Lines tested:** ~100 lines

---

### Phase 8D: VRF Systems (~4-5 hours)

**Test HS08 and HS13 - VRF Systems**

**Why later:**
- ⚠️ More complex (VRF piping calculations)
- ⚠️ Requires understanding max_vrf_pipe_lengths method
- ✅ But important for commercial applications

**Tests to create:**
1. Test HS08 VRF system creation
2. Test HS08 VRF piping calculations
3. Test HS08 VRF terminal units
4. Test HS13 (similar to HS08)

**Estimated time:** 4-5 hours  
**Lines tested:** ~250 lines

---

### Phase 8E: Ground-Source Systems (Future Phase)

**Test HS14, HS15, HS16 - GSHP and Water Loop Systems**

**Why much later or skip:**
- ❌ Very high complexity (ground heat exchangers)
- ❌ Multiple plant loops coordination
- ❌ Less commonly used than air-source heat pumps
- ❌ Would require 1-2 days each

**Recommendation:** Test only if specifically needed by projects

---

## Revised Phase 8 Plan: ECM HVAC Testing

### Phase 8: Heat Pump ECM Systems (~7-10 hours total)

**Goal:** Test the 3 most common heat pump ECM systems

**Systems to test:**
1. **HS11 - ASHP + PTHP** (3-4 hours) - Most common
2. **HS09 - Cold-Climate ASHP + Baseboards** (2-3 hours) - NECB cold zones
3. **HS12 - Standard ASHP + Baseboards** (2 hours) - Standard zones

**Total estimated time:** 7-10 hours  
**Lines tested:** ~350 lines  
**Coverage increase:** +1.3% (350 / 27,493)

**Tests created:** 15-20 tests

**Value:**
- ✅ Covers most commonly used ECM HVAC systems
- ✅ Critical for NECB2020 heat pump requirements
- ✅ Supports net-zero and decarbonization projects
- ✅ Can complete in 1-2 days of focused work

---

### Phase 9: NECB2020 Performance Compliance (2-3 days)

After ECM heat pump testing, move to:
- NECB2020 performance compliance path (1,704 lines, +6% coverage)
- Critical for code compliance verification
- Brand new feature, 100% untested

---

### Future Phases (Lower Priority)

**Phase 10:** VRF ECM Systems (HS08, HS13) - 4-5 hours, +250 lines
**Phase 11:** Simple ECMs (PV, NV, Loads) - 5 hours, +423 lines  
**Phase 12+:** Ground-source systems (HS14, HS15, HS16) - Only if needed

---

## Testing Pattern for ECM HVAC

Based on Phase 6 success and the regression test pattern:

```ruby
def test_ecm_hs11_system_creation
  # 1. Create baseline NECB model
  model, standard = create_test_model_with_hvac_for_ecm
  
  # 2. Apply ECM system
  ecm = ECMS.new
  
  # Get existing systems and zones
  systems = model.getAirLoopHVACs
  map_system_to_zones, system_doas_flags = ecm.get_map_systems_to_zones(systems)
  
  # Apply HS11 ECM
  ecm.add_ecm_hs11_ashp_pthp(
    model: model,
    system_zones_map: map_system_to_zones,
    system_doas_flags: system_doas_flags,
    ecm_system_zones_map_option: 'NECB_Default',
    standard: standard
  )
  
  # 3. Verify ECM components created
  # Check DOAS with ASHP
  air_loops = model.getAirLoopHVACs
  assert air_loops.size > 0, "Should have DOAS air loop"
  
  # Check for heat pump coils on DOAS
  heating_coils = model.getCoilHeatingDXSingleSpeeds
  cooling_coils = model.getCoilCoolingDXSingleSpeeds
  assert heating_coils.size > 0, "Should have DX heating coils"
  assert cooling_coils.size > 0, "Should have DX cooling coils"
  
  # Check for PTHPs in zones
  pthps = model.getZoneHVACPackagedTerminalHeatPumps
  assert pthps.size > 0, "Should have PTHPs in zones"
  
  # 4. Run sizing (optional - can skip for speed)
  # run_dir = File.join(Dir.pwd, 'output', 'ecm_tests')
  # FileUtils.mkdir_p(run_dir)
  # standard.try_sizing_run(model: model, sizing_run_dir: run_dir, sizing_run_subdir: 'hs11')
end

def test_ecm_hs11_efficiency_application
  model, standard = create_test_model_with_hvac_for_ecm
  
  # Apply ECM and size
  ecm = ECMS.new
  systems = model.getAirLoopHVACs
  map_system_to_zones, system_doas_flags = ecm.get_map_systems_to_zones(systems)
  
  ecm.add_ecm_hs11_ashp_pthp(
    model: model,
    system_zones_map: map_system_to_zones,
    system_doas_flags: system_doas_flags,
    ecm_system_zones_map_option: 'NECB_Default',
    standard: standard
  )
  
  # Apply efficiency
  ecm.apply_efficiency_ecm_hs11_ashp_pthp(model, standard)
  
  # Verify COP values are set
  heating_coils = model.getCoilHeatingDXSingleSpeeds
  cooling_coils = model.getCoilCoolingDXSingleSpeeds
  
  heating_coils.each do |coil|
    # Check that COP is within expected range for heat pumps
    # (will vary by capacity and climate)
    assert coil.ratedCOP.is_initialized, "Heating coil should have COP set"
    cop = coil.ratedCOP.get
    assert cop > 2.0 && cop < 5.0, "Heat pump heating COP should be 2-5, got #{cop}"
  end
  
  cooling_coils.each do |coil|
    assert coil.ratedCOP.is_initialized, "Cooling coil should have COP set"
    cop = coil.ratedCOP.get
    assert cop > 2.5 && cop < 6.0, "Heat pump cooling COP should be 2.5-6, got #{cop}"
  end
end
```

---

## Comparison: ECM Heat Pumps vs NECB2020 Compliance

| Factor | ECM Heat Pumps (Phase 8) | NECB2020 Compliance (Phase 9) |
|--------|--------------------------|-------------------------------|
| **Effort** | 7-10 hours | 2-3 days |
| **Coverage** | +1.3% (350 lines) | +6% (1,704 lines) |
| **Tests** | 15-20 tests | 5-8 tests |
| **Complexity** | Medium | High |
| **Priority** | High (widely used) | Highest (core feature) |
| **Risk** | Low-Medium | Medium-High |
| **Value** | Practical ECMs for real projects | Critical code compliance |

---

## Recommendation: Do Both in Sequence

**Phase 8:** ECM Heat Pump Systems (HS11, HS09, HS12) - 7-10 hours
- Start with HS11 (most common)
- Build momentum with successful tests
- Practical value for heat pump projects

**Phase 9:** NECB2020 Performance Compliance - 2-3 days
- Higher complexity but critical feature
- 100% untested brand new code
- Essential for NECB2020 compliance path

**Total time:** 3-4 days for both  
**Total coverage:** +7.3% (2,054 lines)  
**Total tests:** 20-28 tests

---

## Next Steps

**Immediate:** Start Phase 8A - Test HS11 (ASHP + PTHP)
1. Create test file `/test/necb_new/ecm_tests/test_ecm_heat_pumps.rb`
2. Create helper to set up baseline NECB model with zones
3. Write first test: HS11 system creation
4. Verify DOAS + PTHP components created
5. Add efficiency test for HS11
6. Add climate variation tests

**Estimated first session:** 3-4 hours to complete HS11 testing
