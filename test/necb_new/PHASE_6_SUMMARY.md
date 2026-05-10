# Phase 6: Integration Tests - Quick Summary

**Goal:** Increase coverage from 12% to 30-40% using parallel fixture generation + pre-sized models

---

## The Strategy

### Problem
Integration tests with EnergyPlus sizing are slow:
- Each sizing run: 3-5 minutes
- 88 tests × 3-5 min = 4-7 hours (unacceptable!)

### Solution: Parallel Fixture Generation + Pre-Sized Models

1. **Generate fixtures once in parallel** (6-12 minutes one-time)
   - Create ~12 pre-sized models for common configurations
   - Use 4-8 parallel workers to speed up generation
   - Thread-safe Ruby implementation

2. **Load fixtures instantly in tests** (<1 second)
   - No EnergyPlus sizing needed in tests
   - Verify components and sizing results from SQL
   - 88 tests run in ~28 minutes instead of 4-7 hours

---

## Quick Start

### Step 1: Generate Fixtures (One-Time, 6-12 min)

```bash
# Recommended: 4 workers (~12 minutes)
bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --workers 4

# Faster: 8 workers on powerful machine (~6 minutes)
bundle exec ruby test/necb_new/fixtures/generate_integration_fixtures.rb --workers 8

# Check what was generated
ls -lh test/necb_new/fixtures/sized_models/
```

**Creates:**
- system_4_hw_toronto.osm (System 4 with hot water heating)
- system_4_electric_toronto.osm (System 4 with electric heating)
- system_5_tpfc_toronto.osm (System 5 two-pipe fan coil)
- system_6_vav_hw_toronto.osm (System 6 VAV with hot water)
- system_1_vancouver.osm (System 1 in Vancouver climate)
- system_1_edmonton.osm (System 1 in Edmonton climate)
- ... and 6 more fixtures

### Step 2: Implement Integration Tests

Use pre-sized fixtures in tests:

```ruby
def test_system_4_hw_components
  # Load pre-sized fixture (instant!)
  model = BTAP::FileIO.load_osm('test/necb_new/fixtures/sized_models/system_4_hw_toronto.osm')
  
  # Verify components exist and are sized
  air_loops = model.getAirLoopHVACs
  assert air_loops.size > 0, "Should have MAU air loops"
  
  baseboards = model.getZoneHVACBaseboardConvectiveWaters
  assert baseboards.size > 0, "Should have HW baseboards"
  
  # Verify sizing results from SQL
  sql_file = model.sqlFile
  assert sql_file.is_initialized, "Should have sizing results"
end
```

Only size when testing new configurations:

```ruby
def test_system_4_propane_heating
  # Not in fixtures - need to create and size
  standard = Standard.build('NECB2011')
  model = create_simple_box()  # 10m×10m×3m
  
  standard.add_sys4_single_zone_make_up_air_unit_with_baseboard_heating(
    model: model, zones: model.getThermalZones,
    heating_coil_type: 'PropaneGas', baseboard_type: 'PropaneGas', hw_loop: nil
  )
  
  result = standard.model_run_sizing_run(model, "#{Dir.pwd}/output/sys4_propane")
  assert result, "Sizing should succeed"
end
```

---

## Parallel Fixture Generation Details

### How It Works

1. **Work Queue Pattern**
   - Main thread creates a queue of fixture configurations
   - Spawns N worker threads (default: 4)
   - Each worker pulls configs from queue and generates fixtures
   - Thread-safe result collection with Mutex

2. **Progress Reporting**
   ```
   [1/12] → Starting system_4_hw_toronto...
   [2/12] → Starting system_5_tpfc_toronto...
   [3/12] → Starting system_6_vav_hw_toronto...
   [4/12] → Starting system_1_vancouver...
   [1/12] ✓ Completed system_4_hw_toronto (1.2 MB)
   [5/12] → Starting system_1_edmonton...
   [2/12] ✓ Completed system_5_tpfc_toronto (1.4 MB)
   ...
   ```

3. **Error Handling**
   - Individual fixture failures don't stop other workers
   - Results summary shows success/failure counts
   - Failed fixtures can be regenerated with --force

### Command-Line Options

```bash
# Parallel (default)
ruby generate_integration_fixtures.rb
ruby generate_integration_fixtures.rb --workers 8

# Sequential (for debugging)
ruby generate_integration_fixtures.rb --sequential

# Force regeneration
ruby generate_integration_fixtures.rb --force

# Help
ruby generate_integration_fixtures.rb --help
```

---

## Expected Results

### Before Phase 6
- **Tests:** 524
- **Coverage:** 12.18%
- **Runtime:** 65 seconds
- **Integration tests:** 23 skipped

### After Phase 6
- **Tests:** 612 (524 + 88)
- **Coverage:** 30-40% (+18-28%)
- **Runtime:** 
  - Fast suite: 65 seconds (Phases 1-5)
  - Integration suite: 28 minutes (Phase 6)
  - Total: ~29 minutes
- **Integration tests:** 88 passing

### Fixture Generation
- **One-time setup:**
  - Sequential: 45 minutes
  - Parallel (4 workers): 12 minutes ⚡
  - Parallel (8 workers): 6 minutes ⚡⚡
- **Speedup:** 4-8x faster with parallelization

---

## Phase 6 Tasks Breakdown

| Task | Tests | Development | Fixture Gen | Test Runtime |
|------|-------|-------------|-------------|--------------|
| 0. Create fixture script | - | 1 hour | 6-12 min | - |
| 1. Unskip System 4/5/6 | 23 | 2 hours | - | 5 min |
| 2. Full system tests | 30 | 3 hours | - | 10 min |
| 3. Envelope tests | 20 | 2 hours | - | 8 min |
| 4. BEPS compliance | 15 | 3 hours | - | 5 min |
| **TOTAL** | **88** | **11 hours** | **6-12 min** | **28 min** |

---

## Coverage Gain Breakdown

| Area | Current | Phase 6 | Gain |
|------|---------|---------|------|
| Pure unit tests | 12% | 12% | - |
| System creation (with sizing) | ~2% | ~12% | +10% |
| Envelope application (with sizing) | ~1% | ~6% | +5% |
| BEPS compliance | 0% | ~3% | +3% |
| Integration workflows | ~2% | ~12% | +10% |
| **TOTAL** | **12%** | **30-40%** | **+18-28%** |

---

## Why This Approach Works

### Traditional Approach (Slow)
```
Test 1: Create model → Add HVAC → Size (3-5 min) → Verify
Test 2: Create model → Add HVAC → Size (3-5 min) → Verify
Test 3: Create model → Add HVAC → Size (3-5 min) → Verify
...
Total: N tests × 3-5 min = VERY SLOW
```

### Fixture Approach (Fast)
```
One-time (parallel):
  Worker 1: Create + Size fixture 1 (3 min)
  Worker 2: Create + Size fixture 2 (3 min)  } Simultaneous!
  Worker 3: Create + Size fixture 3 (3 min)
  Worker 4: Create + Size fixture 4 (3 min)
Total fixture gen: ~12 min with 4 workers

Tests (using fixtures):
  Test 1: Load fixture (<1s) → Verify
  Test 2: Load fixture (<1s) → Verify
  Test 3: Load fixture (<1s) → Verify
  ...
Total test time: Seconds per test!
```

### Combined Benefits
- **Fixture generation:** 45 min → 6-12 min (4-8x speedup via parallelization)
- **Test execution:** 4-7 hours → 28 min (10x speedup via pre-sized fixtures)
- **Reproducibility:** Fixtures checked into git
- **CI-friendly:** Tests run fast, fixtures don't need regeneration

---

## Implementation Checklist

- [ ] Create `generate_integration_fixtures.rb` with parallel support
- [ ] Run fixture generation with 4-8 workers
- [ ] Verify all 12 fixtures generated successfully
- [ ] Add fixtures to git (or .gitignore if too large)
- [ ] Unskip 23 System 4/5/6 tests
- [ ] Implement fixture loading in tests
- [ ] Create 30 full system tests
- [ ] Create 20 envelope tests
- [ ] Create 15 BEPS tests
- [ ] Verify coverage increased to 30-40%
- [ ] Update CI configuration for fast + integration suites
- [ ] Document fixture usage in README

---

## Next Steps

1. **Review PHASE_6_PLAN.md** for detailed implementation
2. **Create parallel fixture generation script**
3. **Run fixture generation** (6-12 minutes one-time)
4. **Implement integration tests** (~11 hours development)
5. **Verify coverage increase** to 30-40%

See `PHASE_6_PLAN.md` for complete code examples and detailed instructions.
