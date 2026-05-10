# Complete ECM HVAC Coverage Plan

**Date:** 2026-05-06  
**File:** `/lib/openstudio-standards/standards/necb/ECMS/hvac_systems.rb` (4,050 lines)

---

## Answer: No, we would only cover ~8.6% of the file

My original proposal only covered **3 out of 8 heat pump systems**, plus it **missed entire categories** of functionality.

Here's what's **actually** in the 4,050-line file:

---

## Complete Method Breakdown (42 methods total)

### Category 1: ECM System Creation (8 systems - "add_ecm_hs*" methods)

These are the user-facing ECM systems:

| System | Method | Lines | Description | Priority |
|--------|--------|-------|-------------|----------|
| **HS08** | `add_ecm_hs08_ccashp_vrf` | ~150 | Central cooling ASHP + VRF | HIGH |
| **HS09** | `add_ecm_hs09_ccashp_baseboard` | ~100 | Cold-climate ASHP + baseboards | HIGHEST |
| **HS11** | `add_ecm_hs11_ashp_pthp` | ~150 | ASHP + PTHP (most common) | HIGHEST |
| **HS12** | `add_ecm_hs12_ashp_baseboard` | ~100 | Standard ASHP + baseboards | HIGH |
| **HS13** | `add_ecm_hs13_ashp_vrf` | ~100 | ASHP + VRF | MEDIUM |
| **HS14** | `add_ecm_hs14_cgshp_fancoils` | ~200 | Ground-source HP + fan coils | MEDIUM |
| **HS15** | `add_ecm_hs15_cawhp_fancoils` | ~200 | Air-to-water HP + fan coils | MEDIUM |
| **HS16** | `add_ecm_hs16_ashp_cawhp_fancoils` | ~100 | ASHP + CAWHP + fan coils | LOW |
| **Baseboards** | `add_ecm_remove_airloops_add_zone_baseboards` | ~50 | Remove HVAC, add baseboards only | LOW |

**Subtotal:** ~1,150 lines (28% of file)

---

### Category 2: ECM Efficiency Application (8 methods - "apply_efficiency_ecm_hs*")

These apply efficiency curves and COP values to the equipment:

| System | Method | Lines | Description |
|--------|--------|-------|-------------|
| **HS08** | `apply_efficiency_ecm_hs08_ccashp_vrf` | ~40 | Apply VRF curves/COP |
| **HS09** | `apply_efficiency_ecm_hs09_ccashp_baseboard` | ~100 | Apply cold-climate ASHP curves |
| **HS11** | `apply_efficiency_ecm_hs11_ashp_pthp` | ~80 | Apply PTHP curves/COP |
| **HS12** | `apply_efficiency_ecm_hs12_ashp_baseboard` | ~80 | Apply standard ASHP curves |
| **HS13** | `apply_efficiency_ecm_hs13_ashp_vrf` | ~20 | Apply VRF curves |
| **HS14** | `apply_efficiency_ecm_hs14_cgshp_fancoils` | ~120 | Apply GSHP curves + GHX sizing |
| **HS15** | `apply_efficiency_ecm_hs15_cawhp_fancoils` | ~100 | Apply CAWHP curves |
| **HS16** | `apply_efficiency_ecm_hs16_ashp_cawhp_fancoils` | ~20 | Apply combined curves |

**Subtotal:** ~560 lines (14% of file)

---

### Category 3: Component Creation Methods (11 methods - "create_*")

Low-level component builders used by ECM systems:

| Method | Lines | Description | Tested by ECM system tests? |
|--------|-------|-------------|-----------------------------|
| `create_airloop` | ~50 | Create air loop | ✅ Indirectly |
| `create_air_sys_spm` | ~30 | Create air system setpoint manager | ✅ Indirectly |
| `create_air_sys_fan` | ~30 | Create supply fan | ✅ Indirectly |
| `create_air_sys_clg_eqpt` | ~40 | Create cooling coil | ✅ Indirectly |
| `create_air_sys_htg_eqpt` | ~50 | Create heating coil | ✅ Indirectly |
| `create_zone_diffuser` | ~30 | Create zone diffuser | ✅ Indirectly |
| `create_zone_htg_eqpt` | ~50 | Create zone heating equipment | ✅ Indirectly |
| `create_zone_clg_eqpt` | ~30 | Create zone cooling equipment | ✅ Indirectly |
| `create_zone_container_eqpt` | ~80 | Create zone container (PTHP, fan coil) | ✅ Indirectly |
| `create_plantloop_pump` | ~30 | Create pump | ✅ Indirectly |
| `create_plantloop_htg_eqpt` | ~40 | Create heating plant equipment | ✅ Indirectly |
| `create_plantloop_clg_eqpt` | ~40 | Create cooling plant equipment | ✅ Indirectly |
| `create_plantloop_spm` | ~30 | Create plant setpoint manager | ✅ Indirectly |
| `create_plantloop_heat_rej_eqpt` | ~40 | Create heat rejection equipment | ✅ Indirectly |

**Subtotal:** ~570 lines (14% of file)

**Testing strategy:** These are **automatically tested** when we test ECM systems - no separate tests needed

---

### Category 4: High-Level Assembly Methods (3 methods)

Methods that orchestrate component creation:

| Method | Lines | Description | Tested by ECM system tests? |
|--------|-------|-------------|-----------------------------|
| `add_air_system` | ~80 | Assemble complete air system | ✅ Indirectly |
| `add_zone_eqpt` | ~60 | Assemble complete zone equipment | ✅ Indirectly |
| `add_plantloop` | ~80 | Assemble complete plant loop | ✅ Indirectly |

**Subtotal:** ~220 lines (5% of file)

**Testing strategy:** Automatically tested by ECM system tests

---

### Category 5: Performance Curve Application (9 methods - "*_apply_curves")

Apply performance curves from JSON data files:

| Method | Lines | Description | Tested by efficiency tests? |
|--------|-------|-------------|-----------------------------|
| `coil_cooling_dx_single_speed_apply_curves` | ~90 | DX cooling curves | ✅ Indirectly |
| `coil_heating_dx_single_speed_apply_curves` | ~100 | DX heating curves | ✅ Indirectly |
| `coil_cooling_dx_variable_speed_apply_curves` | ~90 | Variable speed cooling curves | ✅ Indirectly |
| `coil_heating_dx_variable_speed_apply_curves` | ~100 | Variable speed heating curves | ✅ Indirectly |
| `airconditioner_variablerefrigerantflow_cooling_apply_curves` | ~160 | VRF cooling curves | ✅ Indirectly |
| `airconditioner_variablerefrigerantflow_heating_apply_curves` | ~160 | VRF heating curves | ✅ Indirectly |
| `chiller_electric_eir_apply_curves_and_cop` | ~70 | Chiller curves + COP | ✅ Indirectly |

**Subtotal:** ~770 lines (19% of file)

**Testing strategy:** Automatically tested when we test efficiency application

---

### Category 6: COP Application Methods (5 methods - "*_apply_cop")

Apply COP (Coefficient of Performance) values:

| Method | Lines | Description | Tested by efficiency tests? |
|--------|-------|-------------|-----------------------------|
| `coil_cooling_dx_single_speed_apply_cop` | ~90 | DX cooling COP | ✅ Indirectly |
| `coil_heating_dx_single_speed_apply_cop` | ~80 | DX heating COP | ✅ Indirectly |
| `coil_cooling_dx_variable_speed_apply_cop` | ~90 | Variable speed cooling COP | ✅ Indirectly |
| `coil_heating_dx_variable_speed_apply_cop` | ~80 | Variable speed heating COP | ✅ Indirectly |
| `airconditioner_variablerefrigerantflow_cooling_apply_cop` | ~90 | VRF cooling COP | ✅ Indirectly |
| `airconditioner_variablerefrigerantflow_heating_apply_cop` | ~90 | VRF heating COP | ✅ Indirectly |

**Subtotal:** ~520 lines (13% of file)

**Testing strategy:** Automatically tested when we test efficiency application

---

### Category 7: Utility/Helper Methods (11 methods)

Supporting calculations and geometry:

| Method | Lines | Description | Tested indirectly? |
|--------|-------|-------------|--------------------|
| `get_map_systems_to_zones` | ~20 | Map existing systems to zones | ✅ Yes |
| `get_zone_clg_eqpt_type` | ~20 | Get cooling equipment type | ✅ Yes |
| `get_storey_avg_clg_zcoords` | ~40 | Get floor ceiling heights | ✅ Yes |
| `get_lowest_floor_ext_wall_centroid_coords` | ~40 | Find exterior wall centroid | ⚠️ VRF only |
| `get_space_centroid_coords` | ~20 | Calculate space centroid | ⚠️ VRF only |
| `get_roof_centroid_coords` | ~30 | Calculate roof centroid | ⚠️ VRF only |
| `get_max_vrf_pipe_lengths` | ~60 | Calculate VRF piping lengths | ⚠️ VRF only |
| `add_outdoor_vrf_unit` | ~120 | Create VRF outdoor unit | ⚠️ VRF only |
| `zone_with_no_vrf_eqpt?` | ~20 | Check if zone has VRF | ⚠️ VRF only |
| `get_zone_storey` | ~20 | Get storey for zone | ✅ Yes |
| `get_storey_zones_map` | ~20 | Map storeys to zones | ✅ Yes |
| `update_system_zones_map` | ~30 | Update zone mapping | ✅ Yes |
| `update_system_zones_map_keys` | ~40 | Update zone map keys | ✅ Yes |
| `get_hvac_comp_init_name` | ~20 | Get component initial name | ✅ Yes |
| `air_sys_comps_assumptions` | ~50 | Get system assumptions | ✅ Yes |
| `coil_cooling_dx_variable_speed_find_capacity` | ~20 | Find coil capacity | ✅ Yes |
| `coil_heating_dx_variable_speed_find_capacity` | ~30 | Find coil capacity | ✅ Yes |
| `set_ghx_loop_district_cap` | ~80 | Size ground heat exchanger | ⚠️ GSHP only |

**Subtotal:** ~680 lines (17% of file)

---

### Category 8: Equipment Efficiency Modification (6 methods - "modify_*")

Modify efficiency of existing equipment (non-ECM use case):

| Method | Lines | Description | Priority |
|--------|-------|-------------|----------|
| `modify_boiler_efficiency` | ~60 | Modify boiler efficiency | MEDIUM |
| `reset_boiler_efficiency` | ~60 | Reset boiler efficiency | MEDIUM |
| `modify_furnace_efficiency` | ~60 | Modify furnace efficiency | MEDIUM |
| `reset_furnace_efficiency` | ~50 | Reset furnace efficiency | MEDIUM |
| `modify_shw_efficiency` | ~60 | Modify water heater efficiency | MEDIUM |
| `reset_shw_efficiency` | ~50 | Reset water heater efficiency | MEDIUM |
| `modify_unitary_cop` | ~140 | Modify unitary equipment COP | MEDIUM |
| `modify_chiller_efficiency` | ~30 | Modify chiller efficiency | MEDIUM |
| `find_chiller_set` | ~50 | Find chiller from database | MEDIUM |
| `reset_chiller_efficiency` | ~80 | Reset chiller efficiency | MEDIUM |

**Subtotal:** ~640 lines (16% of file)

**Note:** These are for **parametric studies**, not standard ECM workflow

---

### Category 9: Additional Features (2 methods)

| Method | Lines | Description | Priority |
|--------|-------|-------------|----------|
| `add_airloop_economizer` | ~30 | Add economizer to air loop | MEDIUM |
| `add_hotwater_loop` | ~50 | Add hot water loop | MEDIUM |

**Subtotal:** ~80 lines (2% of file)

---

## Complete Coverage Summary

| Category | Lines | % of File | Testing Strategy |
|----------|-------|-----------|------------------|
| **1. ECM System Creation (8 systems)** | 1,150 | 28% | **Direct tests needed** |
| **2. ECM Efficiency Application (8 systems)** | 560 | 14% | **Direct tests needed** |
| **3. Component Creation (14 methods)** | 570 | 14% | ✅ Tested indirectly by #1 |
| **4. Assembly Methods (3 methods)** | 220 | 5% | ✅ Tested indirectly by #1 |
| **5. Performance Curves (7 methods)** | 770 | 19% | ✅ Tested indirectly by #2 |
| **6. COP Application (6 methods)** | 520 | 13% | ✅ Tested indirectly by #2 |
| **7. Utility/Helper Methods (18 methods)** | 680 | 17% | ✅ Tested indirectly by #1 |
| **8. Equipment Efficiency Modification (10 methods)** | 640 | 16% | ⚠️ Optional, lower priority |
| **9. Additional Features (2 methods)** | 80 | 2% | ⚠️ Optional |
| **Total** | **5,190** | **128%** | (overlap in estimates) |

**Note:** Actual file is 4,050 lines - my line estimates have overlap

---

## What We Need to Test Directly

### Must Test (Core ECM Functionality)

**8 ECM Systems + their efficiency application = 16 tests minimum**

| System | Add Test | Efficiency Test | Total Effort |
|--------|----------|-----------------|--------------|
| HS08 - Central cooling ASHP + VRF | 1 test | 1 test | 4-5 hours |
| HS09 - Cold-climate ASHP + baseboards | 1 test | 1 test | 2-3 hours |
| HS11 - ASHP + PTHP | 1 test | 1 test | 3-4 hours |
| HS12 - Standard ASHP + baseboards | 1 test | 1 test | 2 hours |
| HS13 - ASHP + VRF | 1 test | 1 test | 3-4 hours |
| HS14 - GSHP + fan coils | 1 test | 1 test | 5-6 hours |
| HS15 - CAWHP + fan coils | 1 test | 1 test | 5-6 hours |
| HS16 - ASHP + CAWHP + fan coils | 1 test | 1 test | 3-4 hours |
| **Total** | **8 tests** | **8 tests** | **28-37 hours** |

### Everything Else Gets Tested Automatically

- **Component creation methods** (570 lines) - Tested when ECM systems create components
- **Assembly methods** (220 lines) - Tested when ECM systems assemble equipment
- **Performance curves** (770 lines) - Tested when efficiency is applied
- **COP application** (520 lines) - Tested when efficiency is applied
- **Utility methods** (680 lines) - Tested when ECM systems use them

**Automatic coverage:** ~2,760 lines (68% of file)

---

## Revised Testing Plan: Complete ECM Coverage

### Phase 8A: Priority 1 Heat Pumps (~7-9 hours)

**Most common, highest impact:**

1. **HS11 - ASHP + PTHP** (3-4 hours)
   - Most widely used
   - Hotels, apartments, offices
   
2. **HS09 - Cold-Climate ASHP** (2-3 hours)
   - Critical for NECB Zones 6-8
   
3. **HS12 - Standard ASHP** (2 hours)
   - Standard zones

**Result:** 6 tests, ~350 lines direct + ~800 lines indirect = 1,150 lines covered

---

### Phase 8B: VRF Systems (~7-9 hours)

**Commercial applications:**

4. **HS08 - Central cooling ASHP + VRF** (4-5 hours)
   - Includes VRF piping calculations
   
5. **HS13 - ASHP + VRF** (3-4 hours)
   - Similar to HS08

**Result:** 4 tests, ~250 lines direct + ~600 lines indirect = 850 lines covered

---

### Phase 8C: Ground-Source & Water Loop (~13-16 hours)

**Institutional/high-performance buildings:**

6. **HS14 - GSHP + fan coils** (5-6 hours)
   - Ground heat exchanger sizing
   - Most complex

7. **HS15 - CAWHP + fan coils** (5-6 hours)
   - Air-to-water heat pump
   - Condenser heat recovery

8. **HS16 - ASHP + CAWHP** (3-4 hours)
   - Combination system

**Result:** 6 tests, ~500 lines direct + ~800 lines indirect = 1,300 lines covered

---

### Phase 8D: Equipment Modification Methods (~4-6 hours)

**Parametric study features:**

9. Test equipment efficiency modification methods
   - Boiler, furnace, SHW, chiller, unitary
   
10. Test economizer addition
11. Test hot water loop addition

**Result:** 3-5 tests, ~750 lines covered

---

## Complete ECM HVAC Testing Summary

**Total Phases:** 8A, 8B, 8C, 8D  
**Total Time:** ~31-40 hours (4-5 days of focused work)  
**Total Tests:** 19-23 tests  
**Total Coverage:** ~4,050 lines (100% of ECM HVAC file)  
**Coverage increase:** +14.7% of total NECB code (4,050 / 27,493)

---

## Comparison: Original Proposal vs Complete Coverage

| Approach | Time | Tests | Lines | % of NECB |
|----------|------|-------|-------|-----------|
| **Original (3 heat pumps only)** | 7-10 hours | 6 tests | 350 direct | +1.3% |
| **Complete ECM HVAC** | 31-40 hours | 19-23 tests | 4,050 total | +14.7% |
| **Complete ECMs + NECB2020** | 5-6 days | 24-31 tests | 5,754 lines | +20.9% |

---

## Recommended Approach: Staged Rollout

### Option A: Do All ECM HVAC (4-5 days)
- Complete coverage of ECM HVAC systems
- 19-23 tests
- +14.7% coverage
- Then do NECB2020 Compliance (2-3 days, +6%)
- **Total:** 6-8 days, +20.9% coverage

### Option B: Priority Heat Pumps Only (1-2 days)
- Phase 8A only (HS11, HS09, HS12)
- 6 tests
- +4.2% coverage (1,150 lines including indirect)
- Then do NECB2020 Compliance (2-3 days, +6%)
- Then VRF and GSHP later
- **Total:** 3-5 days for first pass, +10.2% coverage

### Option C: Skip to NECB2020, Circle Back
- Do NECB2020 Compliance first (2-3 days, +6%)
- Then do ECM HVAC (4-5 days, +14.7%)
- **Total:** 6-8 days, +20.9% coverage

---

## My Recommendation: Option B (Staged)

**Start with:** Phase 8A - Priority heat pumps (HS11, HS09, HS12)
- 1-2 days of work
- 6 tests
- Most commonly used systems
- +4.2% coverage

**Then:** NECB2020 Performance Compliance (2-3 days, +6%)

**Then:** Phase 8B, 8C, 8D - Remaining ECM systems (2-3 days, +10.5%)

**Why staged:**
- ✅ Quick wins first (maintain momentum)
- ✅ Test most common systems first (practical value)
- ✅ Validate approach before committing to all 8 systems
- ✅ Can reassess priority after NECB2020 is done

---

## Next Steps

**Question for you:** Which approach?

1. **Complete ECM HVAC** (4-5 days, all 8 systems) - Most thorough
2. **Priority Heat Pumps** (1-2 days, 3 systems) - Balanced approach ✅ Recommended
3. **Skip to NECB2020** (2-3 days) - Highest priority feature first

Once you decide, I'll start creating tests immediately.
