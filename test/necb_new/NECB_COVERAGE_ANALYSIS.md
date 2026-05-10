# NECB Code Coverage Analysis

**Date:** 2026-05-06  
**Purpose:** Determine what NECB code is tested and identify highest-priority gaps

---

## Executive Summary

**Total NECB Code:** 27,493 lines in 50 files

**Current Coverage Estimate:** ~12.7% (3,500 / 27,493 lines)
- Integration tests: ~5.5% (1,500 lines)
- Unit tests: ~7.3% (2,000 lines)

**Untested:** ~87.3% (23,993 lines)

**Biggest Gaps:**
1. NECB2020 Performance Compliance (1,704 lines) - **Brand new feature, 0% tested**
2. Building Envelope (1,520 lines) - **Core compliance, mostly untested**
3. QAQC Reporting (1,947 lines) - **Quality checks, untested**
4. Autozone (1,656 lines) - **Model prep, untested**
5. ECMs (4,050 lines) - **Optional features, untested**

---

## NECB Code Structure

### By Directory

| Directory | Files | Lines | Purpose |
|-----------|-------|-------|---------|
| **NECB2011** | 19 | 14,693 | Core NECB 2011 implementation |
| **ECMS** | 6 | 4,562 | Energy Conservation Measures |
| **common** | 3 | 3,390 | Shared NECB utilities |
| **NECB2020** | 9 | 2,542 | NECB 2020 + Performance Compliance |
| **BTAPPRE1980** | 6 | 1,428 | Pre-1980 vintage buildings |
| **NECB2015** | 4 | 703 | NECB 2015 overrides |
| **NECB2017** | 2 | 125 | NECB 2017 overrides |
| **BTAP1980TO2010** | 1 | 50 | 1980-2010 vintage buildings |
| **Total** | **50** | **27,493** | |

### Largest Files (Top 10)

| File | Lines | Tested? | Priority |
|------|-------|---------|----------|
| ECMS/hvac_systems.rb | 4,050 | ❌ No | Medium |
| NECB2011/necb_2011.rb | 2,953 | ⚠️ Partial | HIGH |
| common/btap_data.rb | 2,657 | ❌ No | Low |
| NECB2011/hvac_systems.rb | 2,456 | ⚠️ Partial | HIGH |
| NECB2011/qaqc/necb_qaqc.rb | 1,947 | ❌ No | Medium |
| NECB2011/autozone.rb | 1,656 | ❌ No | HIGH |
| NECB2011/building_envelope.rb | 1,520 | ❌ No | **HIGH** |
| NECB2011/service_water_heating.rb | 705 | ❌ No | Low |
| common/btap_datapoint.rb | 654 | ❌ No | Low |
| NECB2011/data/standards_data.rb | 515 | ✅ Yes | N/A |

---

## What's Currently Tested

### ✅ Integration Tests (Phase 6)

**HVAC System Creation (~1,500 lines covered):**
- System 1 creation (PTAC + baseboards) - 285 + 169 = 454 lines
- System 3 creation (PSZ RTU) - 267 + 180 = 447 lines  
- System 4 creation (MAU + baseboards) - 225 lines
- System 6 creation (VAV) - 445 lines
- Plant loop setup (hot water, chilled water) - ~200 lines
- `try_sizing_run` method - ~100 lines

**Files with coverage:**
- ✅ `NECB2011/hvac_system_1_single_speed.rb` - Well tested
- ✅ `NECB2011/hvac_system_3_and_8_single_speed.rb` - Well tested
- ✅ `NECB2011/hvac_system_4.rb` - Well tested
- ✅ `NECB2011/hvac_system_6.rb` - Well tested
- ⚠️ `NECB2011/hvac_systems.rb` - Partially tested (system selection logic)
- ⚠️ `NECB2011/necb_2011.rb` - Partially tested (setup methods, ~500/2953 lines)

### ✅ Existing Unit Tests (~2,000 lines covered)

**Equipment Efficiency Rules:**
- Boiler efficiency lookups
- Chiller efficiency lookups
- Furnace efficiency lookups
- Cooling tower rules
- Fan power rules

**Geometry:**
- FDWR calculations
- SRR calculations
- Zoning rules

**Schedules & Loads:**
- Schedule generation
- DHW sizing (partial)

**Files with partial coverage:**
- ⚠️ `NECB2011/necb_2011.rb` - Equipment efficiency methods
- ⚠️ Various system files - Efficiency lookup methods

---

## Critical Untested Areas (>1,000 lines)

### 1. 🚨 NECB2020 Performance Compliance (1,704 lines)

**Status:** Brand new NECB2020 feature - **0% tested**

**Files:**
- `NECB2020/performance_compliance/proposed_builder.rb` (438 lines)
- `NECB2020/performance_compliance/compliance_report.rb` (401 lines)
- `NECB2020/performance_compliance/reference_builder.rb` (334 lines)
- `NECB2020/performance_compliance/compliance_logger.rb` (319 lines)
- `NECB2020/performance_compliance/compliance_validator.rb` (212 lines)

**What it does:**
- Creates proposed building model
- Creates reference building (NECB baseline)
- Runs both simulations
- Compares energy performance
- Validates compliance (proposed ≤ reference)
- Generates compliance report

**Why it matters:**
- **NEW in NECB2020** - Performance compliance path
- Alternative to prescriptive compliance
- Allows trade-offs (better envelope for worse HVAC, etc.)
- Critical for code compliance verification
- Used by building designers and code officials

**Testing priority:** **HIGHEST**
- Core new feature
- Complex workflow
- High-value target

---

### 2. 🚨 Building Envelope (1,520 lines)

**Status:** Core NECB functionality - **mostly untested**

**File:** `NECB2011/building_envelope.rb`

**What it does:**
- Applies NECB envelope requirements
- Calculates assembly U-values
- Applies constructions to surfaces
- FDWR calculations and adjustments
- SRR (skylight-to-roof ratio) calculations
- Fenestration properties (SHGC, U-value)

**Why it matters:**
- **Envelope = 30-50% of building energy**
- Core NECB compliance requirement
- Complex calculations (FDWR, SRR, U-values)
- Interacts with geometry and climate zones

**What's NOT tested:**
- Construction application to surfaces
- FDWR adjustment logic
- Climate-specific envelope requirements
- Skylight sizing rules
- Below-grade envelope treatment

**Testing priority:** **HIGHEST**
- Core compliance feature
- Complex calculations
- High impact on results

---

### 3. QAQC Reporting (1,947 lines)

**Status:** Quality checks - **untested**

**File:** `NECB2011/qaqc/necb_qaqc.rb`

**What it does:**
- Quality assurance checks on models
- Validation of NECB requirements
- Report generation (JSON, HTML)
- Compliance verification
- Error detection and warnings

**Why it matters:**
- Catches modeling errors
- Verifies NECB compliance before submission
- Used by BTAP and other NECB tools
- Important for quality assurance

**What's NOT tested:**
- All QAQC checks
- Report generation
- Validation logic
- Error detection

**Testing priority:** MEDIUM
- Important for quality
- But not core simulation
- Mostly reporting/validation

---

### 4. Autozone (1,656 lines)

**Status:** Model preparation - **untested**

**File:** `NECB2011/autozone.rb`

**What it does:**
- Automatic thermal zone creation
- Groups spaces into zones based on NECB rules
- Applies zoning criteria (orientation, use, floors)
- Used in `model_apply_standard` workflow
- Critical for creating NECB-compliant models

**Why it matters:**
- Part of standard NECB workflow
- Used by `model_apply_standard`
- Complex logic for zone grouping
- Affects HVAC system sizing

**What's NOT tested:**
- Zoning algorithms
- Space grouping logic
- Orientation-based zoning
- Multi-floor zoning

**Testing priority:** MEDIUM-HIGH
- Used in standard workflow
- Relatively isolated (easy to test)
- Affects system sizing

---

### 5. ECMs - Energy Conservation Measures (4,050 lines)

**Status:** Optional features - **untested**

**File:** `ECMS/hvac_systems.rb` (4,050 lines!)

**What it does:**
- Energy Recovery Ventilators (ERV)
- Natural Ventilation (NV)
- Ground-mounted PV systems
- Load reductions
- Optional NECB measures

**Why it matters:**
- Optional, not required for basic NECB
- Used for above-code performance
- Large codebase (4,050 lines)

**Testing priority:** MEDIUM
- Not core NECB requirement
- Optional features
- Large effort required
- Lower impact than envelope/compliance

---

### 6. Service Water Heating (705 lines)

**Status:** Equipment sizing - **partially tested**

**File:** `NECB2011/service_water_heating.rb`

**What it does:**
- Water heater sizing
- Efficiency requirements
- DHW system creation
- Temperature setpoints

**Why it matters:**
- DHW = 10-15% of building energy
- Relatively straightforward
- Equipment efficiency already tested

**Testing priority:** LOW
- Small codebase
- Simple logic
- Partial coverage exists

---

## Other Significant Untested Files

### NECB2011/necb_2011.rb (partially tested)

**Total:** 2,953 lines  
**Tested:** ~500 lines (~17%)  
**Untested:** ~2,450 lines (~83%)

**What's tested:**
- `try_sizing_run` 
- `setup_hw_loop_with_components`
- Equipment efficiency lookups

**What's NOT tested:**
- `model_apply_standard` (main workflow, ~1,000 lines)
- `apply_envelope`
- `apply_loads`
- `apply_standard_construction_properties`
- Numerous helper methods

---

### NECB2011/hvac_systems.rb (partially tested)

**Total:** 2,456 lines  
**Tested:** ~400 lines (~16%)  
**Untested:** ~2,056 lines (~84%)

**What's tested:**
- System 1, 3, 4, 6 creation methods (via integration tests)

**What's NOT tested:**
- System 2 (Four-Pipe Fan Coil)
- System 5 (Two-Pipe Fan Coil) - attempted but skipped
- System 7 (VAV with PFP Boxes)
- System selection logic
- Multi-system assignment
- System type determination

---

## Coverage by NECB Feature

| Feature | Total Lines | Tested Lines | Coverage % | Priority |
|---------|-------------|--------------|------------|----------|
| **HVAC Systems** | ~5,000 | ~1,500 | 30% | ✅ Good |
| **Equipment Efficiency** | ~500 | ~400 | 80% | ✅ Good |
| **Geometry/Zoning** | ~2,000 | ~200 | 10% | 🔴 Poor |
| **Building Envelope** | ~1,520 | ~50 | 3% | 🔴 **Critical** |
| **Plant Loops** | ~500 | ~200 | 40% | ✅ Good |
| **Service Water** | ~705 | ~100 | 14% | 🟡 Fair |
| **QAQC** | ~1,947 | 0 | 0% | 🔴 Poor |
| **ECMs** | ~4,562 | 0 | 0% | 🟡 Fair |
| **Performance Compliance** | ~1,704 | 0 | 0% | 🔴 **Critical** |
| **Autozone** | ~1,656 | 0 | 0% | 🟡 Fair |
| **Schedules/Loads** | ~500 | ~200 | 40% | ✅ Good |

---

## Recommended Next Steps

### Phase 7: Building Envelope Testing (HIGH PRIORITY)

**Goal:** Test envelope compliance calculations

**Estimated impact:** +5-6% coverage (1,520 / 27,493)

**Tests to create:**
1. Test envelope construction application
2. Test FDWR calculations and adjustments
3. Test SRR calculations
4. Test climate-specific envelope requirements
5. Test U-value calculations
6. Test fenestration properties (SHGC, U-value)

**Effort:** ~1 day  
**Value:** Very high - core compliance feature

---

### Phase 8: NECB2020 Performance Compliance (HIGH PRIORITY)

**Goal:** Test new NECB2020 performance path

**Estimated impact:** +6-7% coverage (1,704 / 27,493)

**Tests to create:**
1. Test proposed model builder
2. Test reference model builder
3. Test compliance comparison logic
4. Test report generation
5. Test validation rules
6. Integration test: full compliance check

**Effort:** ~2-3 days  
**Value:** Very high - brand new feature, completely untested

---

### Phase 9: Autozone Testing (MEDIUM PRIORITY)

**Goal:** Test automatic zoning logic

**Estimated impact:** +6% coverage (1,656 / 27,493)

**Tests to create:**
1. Test space grouping by orientation
2. Test multi-floor zoning
3. Test use-based zone separation
4. Test perimeter/core zoning
5. Integration test: full autozone workflow

**Effort:** ~4-6 hours  
**Value:** Medium - used in standard workflow, affects system sizing

---

### Phase 10: Complete model_apply_standard (MEDIUM PRIORITY)

**Goal:** Integration test of full NECB workflow

**Estimated impact:** +3-4% coverage (~1,000 / 27,493)

**Test to create:**
- Single comprehensive integration test
- Create model from scratch
- Apply envelope
- Apply loads
- Apply schedules
- Apply systems
- Run sizing
- Verify all components

**Effort:** ~4 hours  
**Value:** Medium - tests integration of all features

---

### Lower Priority Phases

**Phase 11: QAQC Testing** (~1,947 lines, +7% coverage)
- Effort: ~1 day
- Value: Medium - important but not core simulation

**Phase 12: ECM Testing** (~4,562 lines, +16% coverage)
- Effort: ~2 days
- Value: Low - optional features

**Phase 13: Service Water Heating** (~705 lines, +2.5% coverage)
- Effort: ~2 hours
- Value: Low - mostly covered

---

## Effort vs. Impact Matrix

```
High Impact ↑
            |
            |  [Envelope]     [NECB2020]
            |    1 day          2-3 days
            |
            |  [Autozone]    [model_apply]
            |   4-6 hrs         4 hrs
            |
            |                [QAQC]
            |                 1 day
            |
            |  [SWH]          [ECMs]
            |  2 hrs          2 days
            |
Low Impact  |________________________→ High Effort
                                    
Priority Order:
1. Envelope (HIGH impact, MEDIUM effort)
2. NECB2020 Compliance (HIGH impact, HIGH effort)
3. Autozone (MEDIUM impact, LOW effort)
4. model_apply_standard (MEDIUM impact, LOW effort)
5. QAQC (MEDIUM impact, MEDIUM effort)
6. ECMs (LOW impact, HIGH effort)
```

---

## Summary

**Current State:**
- 13 integration tests covering HVAC systems
- ~12.7% of NECB code tested
- Good coverage of HVAC system creation
- Good coverage of equipment efficiency rules

**Biggest Gaps:**
1. 🚨 **Building Envelope** (1,520 lines) - Core compliance, mostly untested
2. 🚨 **NECB2020 Performance** (1,704 lines) - New feature, 0% tested
3. 🟡 **Autozone** (1,656 lines) - Used in workflows, untested
4. 🟡 **QAQC** (1,947 lines) - Quality checks, untested
5. 🟡 **ECMs** (4,050 lines) - Optional features, untested

**Recommended Next Phase:**
**Phase 7: Building Envelope Testing**
- Highest value for effort
- Core NECB compliance
- 1 day of work
- +5-6% coverage increase

**Long-term Goal:**
- Phases 7-10 would add ~20% coverage
- Total coverage: ~33%
- Cover all critical NECB features
- Effort: ~1 week of focused work

---

## Conclusion

Phase 6 established a solid foundation for NECB testing with comprehensive HVAC system coverage. The next logical steps are to test the building envelope (Phase 7) and NECB2020 performance compliance (Phase 8), which are both critical, high-impact areas that are currently untested.

With Phases 7-8 complete, NECB testing would cover:
- ✅ HVAC systems (Systems 1, 3, 4, 6)
- ✅ Plant loops (hot water, chilled water)
- ✅ Equipment efficiency rules
- ✅ **Building envelope compliance** (NEW)
- ✅ **NECB2020 performance path** (NEW)

This would bring total coverage to ~25-30% and cover all critical NECB code paths.
