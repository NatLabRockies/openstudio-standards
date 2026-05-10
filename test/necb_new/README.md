# NECB New Test Suite

This directory contains the **new, redesigned NECB test suite** built from scratch with proper organization and performance optimization.

## Why a New Directory?

The new test suite is fundamentally different from the existing `/test/necb/` tests:

- **Different organization**: Tests grouped by sizing requirements (pure_unit, geometry_tests, etc.)
- **Different philosophy**: Unit tests, not integration tests
- **Different execution**: Fast (<30 min) vs slow (hours)
- **Different fixtures**: Cached pre-sized models to avoid repeated sizing runs

Keeping them separate makes it easy to:
- Compare old vs new approaches
- Run both suites in parallel during development
- Gradually transition without breaking existing CI
- Archive old tests when new suite proves complete

## Directory Structure

```
test/necb_new/
├── README.md                           # This file
├── TEST_PLAN.md                        # Complete test design document
├── PROGRESS.md                         # Implementation progress tracking
│
├── pure_unit/                          # ~150 tests, NO geometry, <2 min
│   ├── test_boiler_efficiency.rb
│   ├── test_chiller_efficiency.rb
│   ├── test_furnace_efficiency.rb
│   ├── test_dx_equipment_efficiency.rb
│   ├── test_cooling_tower_calculations.rb
│   ├── test_envelope_lookups.rb
│   ├── test_fdwr_limits.rb
│   ├── test_fuel_selection.rb
│   ├── test_dhw_calculations.rb
│   └── test_vintage_inheritance.rb
│
├── geometry_tests/                     # ~50 tests, simple geometry, <10 min
│   ├── test_constructions.rb
│   ├── test_fdwr_application.rb
│   ├── test_srr_application.rb
│   ├── test_autozone.rb
│   └── test_space_type_assignment.rb
│
├── component_tests/                    # ~40 tests, with loads, <15 min
│   ├── test_dhw_systems.rb
│   ├── test_zone_equipment.rb
│   └── test_schedules.rb
│
├── system_tests/                       # ~60 tests, system-sized, <45 min
│   ├── test_system_1_single_speed.rb
│   ├── test_system_1_multi_speed.rb
│   ├── test_system_2_vav.rb
│   ├── test_system_3_8_single_speed.rb
│   ├── test_system_3_8_multi_speed.rb
│   ├── test_system_4_mau.rb
│   ├── test_system_5_vav.rb
│   ├── test_system_6_built_up.rb
│   └── test_system_selection.rb
│
├── plant_tests/                        # ~30 tests, full sizing, <30 min
│   ├── test_boiler_staging.rb
│   ├── test_hw_plant.rb
│   ├── test_chw_plant.rb
│   └── test_cooling_tower_plant.rb
│
├── ecm_tests/                          # ~20 tests, varies, <20 min
│   ├── test_erv_ecm.rb
│   ├── test_nv_ecm.rb
│   └── test_pv_ecm.rb
│
├── vintage_tests/                      # ~40 tests, varies, <30 min
│   ├── test_necb2015_overrides.rb
│   ├── test_necb2017_overrides.rb
│   ├── test_necb2020_overrides.rb
│   └── test_btap_vintages.rb
│
├── integration_tests/                  # ~15 tests, full simulation, hours
│   ├── test_qaqc_compliance.rb
│   └── test_prototype_buildings.rb
│
├── fixtures/                           # Test fixtures and management
│   ├── necb_fixture_manager.rb        # Fixture cache management
│   ├── generate_fixtures.rb           # Generate sized model fixtures
│   ├── create_static_geometry.rb      # Create simple geometry fixtures
│   ├── geometry/                       # Static geometry files (git)
│   ├── with_loads/                     # Geometry + loads files (git)
│   └── sized_models/                   # Pre-sized models (generated)
│       └── .gitignore                  # Don't commit sized models
│
└── benchmark/                          # Performance measurement
    ├── baseline_timing.rb              # Old test timing
    ├── improved_timing.rb              # New test timing
    └── compare_results.rb              # Comparison report
```

## Test Categories

### 1. Pure Unit Tests (~150 tests, <2 minutes)
**No OpenStudio model needed** - Just Ruby code testing lookups and calculations

- Equipment efficiency lookups (boilers, chillers, furnaces, DX, fans, pumps)
- Envelope U-value lookups
- FDWR/SRR limit lookups
- Fuel selection logic
- DHW/pump calculations
- Thermal efficiency conversions
- Vintage inheritance verification

**Run with:**
```bash
cd /workspaces/openstudio-standards
bundle exec ruby test/necb_new/pure_unit/test_boiler_efficiency.rb
```

### 2. Geometry Tests (~50 tests, <10 minutes)
**Simple geometry fixtures** - Test envelope and zoning without HVAC

- Construction assignment
- FDWR enforcement
- SRR enforcement
- Auto-zoning logic
- Space type assignment

**Fixtures:** 2-5 simple geometry files (checked into git)

### 3. Component Tests (~40 tests, <15 minutes)
**Geometry + loads fixtures** - Test HVAC components in isolation

- DHW systems
- Zone equipment (PTACs, fan coils)
- Terminal units
- Schedules

**Fixtures:** 10-15 with-loads models (checked into git)

### 4. System Tests (~60 tests, <45 minutes)
**System-sized fixtures** - Test complete HVAC systems

- All 8 NECB system types
- System selection logic
- Economizer controls
- ERV requirements

**Fixtures:** 30-40 system-sized models (generated as needed)

### 5. Plant Tests (~30 tests, <30 minutes)
**Plant-sized fixtures** - Test plant equipment and controls

- Boiler staging rules
- Hot water plants
- Chilled water plants
- Cooling towers

**Fixtures:** 15-20 plant-sized models (generated as needed)

### 6. ECM Tests (~20 tests, <20 minutes)
**Various fixtures** - Test energy conservation measures

- ERV packages
- Natural ventilation
- Ground-mounted PV

### 7. Vintage Tests (~40 tests, <30 minutes)
**Various fixtures** - Test NECB vintage differences

- NECB2015/2017/2020 overrides
- BTAP vintage standards
- Inheritance verification

### 8. Integration Tests (~15 tests, hours)
**Complete buildings** - Full simulation tests (run nightly)

- QAQC compliance
- BEPS path
- Prototype buildings

## Running Tests

### Fast Suite (Pure Unit + Geometry + Component)
```bash
# Run all fast tests (~27 minutes)
cd /workspaces/openstudio-standards
TEST_CATEGORY=fast bundle exec rake test:necb_new_fast

# Or individually
bundle exec ruby test/necb_new/pure_unit/test_boiler_efficiency.rb
bundle exec ruby test/necb_new/geometry_tests/test_constructions.rb
bundle exec ruby test/necb_new/component_tests/test_dhw_systems.rb
```

### Full Suite (Add System + Plant)
```bash
# Run full suite without integration (~2.5 hours)
bundle exec rake test:necb_new_full
```

### Integration Tests (Nightly)
```bash
# Run integration tests (hours)
bundle exec rake test:necb_new_integration
```

### Individual Test Categories
```bash
TEST_CATEGORY=pure_unit bundle exec rake test:necb_new
TEST_CATEGORY=geometry_tests bundle exec rake test:necb_new
TEST_CATEGORY=system_tests bundle exec rake test:necb_new
# etc.
```

## Fixture Management

### Generate Static Geometry Fixtures
```bash
cd /workspaces/openstudio-standards
bundle exec ruby test/necb_new/fixtures/create_static_geometry.rb
```

Creates simple geometry files in `test/necb_new/fixtures/geometry/`:
- `simple_box.osm` - Single zone box with window
- `simple_box_with_skylight.osm` - Box with window and skylight

**These are checked into git** (small, stable files)

### Generate Dynamic Sized Fixtures
```bash
cd /workspaces/openstudio-standards
bundle exec ruby test/necb_new/fixtures/generate_fixtures.rb

# Options:
bundle exec ruby test/necb_new/fixtures/generate_fixtures.rb --dry-run
bundle exec ruby test/necb_new/fixtures/generate_fixtures.rb --force
bundle exec ruby test/necb_new/fixtures/generate_fixtures.rb --sequential
bundle exec ruby test/necb_new/fixtures/generate_fixtures.rb --workers 4
```

Creates sized models in `test/necb_new/fixtures/sized_models/`:
- `NECB2011_SmallOffice_Toronto_sys2_xxxxx.osm`
- `NECB2011_MediumOffice_Toronto_sys2_xxxxx.osm`
- etc.

**These are NOT checked into git** (large, auto-generated as needed)

### Fixture Cache Management
```ruby
require_relative 'fixtures/necb_fixture_manager'

# List all fixtures
NecbFixtureManager.list_fixtures

# Get fixture stats
stats = NecbFixtureManager.fixture_stats
puts "Total: #{stats[:total_fixtures]} fixtures, #{stats[:total_size_mb]} MB"

# Clear fixtures
NecbFixtureManager.clear_fixtures(pattern: 'NECB2011_*')
NecbFixtureManager.clear_all_fixtures
```

## Implementation Status

See `PROGRESS.md` for current implementation status.

**Current Phase:** Phase 0 (Setup)
- ✅ Directory structure created
- ✅ Fixture management system complete
- ✅ Test plan documented
- 🔄 Validation running (baseline test timing)
- ⏳ Phase 1: Pure unit tests (next)

## Comparison with Old Tests

### Old Tests (`/test/necb/`)
```
test/necb/
├── unit_tests/tests/              # 63 files, mixed granularity
│   ├── test_necb_boiler_rules.rb  # 30+ minutes
│   ├── test_necb_furnace_rules.rb # 20+ minutes
│   └── test_necb_activities.rb    # 60+ minutes
├── system_tests/                  # 133 files, full simulations
├── regression_tests/              # 635 files, hours to run
└── simulation_qaqc_regression_tests/
```

**Characteristics:**
- ❌ Integration-heavy (create full buildings to test components)
- ❌ Slow (repeated sizing runs)
- ❌ Hard to debug (failures don't pinpoint root cause)
- ❌ Limited edge case coverage (too expensive to add tests)
- ❌ Mixed concerns (one test file does too much)

### New Tests (`/test/necb_new/`)
```
test/necb_new/
├── pure_unit/                     # 15 files, NO models
├── geometry_tests/                # 6 files, simple fixtures
├── component_tests/               # 4 files, component fixtures
├── system_tests/                  # 9 files, system fixtures
├── plant_tests/                   # 4 files, plant fixtures
├── ecm_tests/                     # 3 files, varies
├── vintage_tests/                 # 4 files, varies
└── integration_tests/             # 2 files, full simulations
```

**Characteristics:**
- ✅ Unit-focused (test methods in isolation)
- ✅ Fast (fixture cache, no repeated sizing)
- ✅ Easy to debug (failures pinpoint exact method)
- ✅ Comprehensive edge cases (cheap to add tests)
- ✅ Single responsibility (one test = one thing)

## Design Principles

### 1. Test Pyramid
```
     /\
    /  \  Integration (15 tests, hours)
   /____\
  /      \  System+Plant (90 tests, 1-2 hours)
 /________\
/__________\  Pure Unit+Geometry+Component (240 tests, <30 min)
```

Most tests should be fast unit tests at the bottom.

### 2. Fixture Reuse
Don't create models in tests - load pre-generated fixtures:
```ruby
# ❌ DON'T: Create and size in every test
model = standard.model_create_prototype_model(...)  # 3+ minutes

# ✅ DO: Load pre-sized fixture
model = load_fixture('NECB2011_SmallOffice_Toronto_sys2.osm')  # <1 second
```

### 3. Test One Thing
Each test method should test exactly one behavior:
```ruby
# ❌ DON'T: Test multiple things
def test_boiler_rules
  test_efficiency
  test_staging
  test_capacity
  test_fuel_type
end

# ✅ DO: Separate tests
def test_boiler_efficiency_natural_gas_50kw; end
def test_boiler_staging_200kw_requires_two_boilers; end
def test_boiler_capacity_calculation; end
```

### 4. No Model When Possible
If you can test without an OpenStudio model, do it:
```ruby
# ✅ Best: No model needed
def test_max_fdwr_hdd_5000
  standard = Standard.build('NECB2011')
  assert_in_delta 0.40, standard.max_fwdr(5000), 0.01
end

# ⚠️ Only if necessary: Use model
def test_fdwr_enforcement_on_building
  model = load_fixture('simple_box.osm')
  standard.apply_standard_window_to_wall_ratio(model, fdwr_set: 0.4)
  # verify actual FDWR
end
```

## Migration Timeline

**Weeks 1-4:** Build new test suite (parallel to old tests)
**Week 5:** Validate coverage (compare old vs new)
**Week 6:** Transition CI to new tests
**Week 7+:** Archive old tests (keep for reference)

## Success Metrics

**Target:**
- Fast suite: <30 minutes (pure + geometry + component)
- Full suite: <3 hours (add system + plant)
- Integration: Run nightly (hours)
- Coverage: >85% line coverage, >70% branch coverage
- Defect localization: Test name indicates exact failure

**Compare with old:**
- Old tests: 4-8 hours total, poor defect localization
- New tests: <30 min fast suite, precise failure identification

## Questions?

See `TEST_PLAN.md` for complete design details.
