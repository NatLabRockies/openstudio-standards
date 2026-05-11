# NECB New Test Suite

This directory contains modern unit and integration tests for the NECB (National Energy Code of Canada for Buildings) implementation.

## Current Coverage

**Overall NECB Coverage: 8.7%** (1,017/11,690 lines)
- **NECB2011**: 11.21% (777/6,931 lines)
- Focus areas: Building envelope (44.89%), Autozone (15.56%), Core methods (10.95%)

**Test Status:**
- 49 tests total
- 47 passing (96% pass rate)
- 2 documented skips (incomplete conductance methods)
- 125 assertions
- 0 failures, 0 errors

## Directory Structure

```
test/necb_new/
├── README.md                 # This file
├── test_helper.rb           # Main test configuration and SimpleCov setup
│
├── fixtures/                # Test fixtures and model generators
│   ├── fixture_loader.rb
│   ├── necb_fixture_manager.rb
│   ├── generate_fixtures.rb
│   └── create_static_geometry.rb
│
├── runners/                 # Test execution scripts
│   ├── calculate_coverage.rb      # Generate coverage report
│   ├── run_all.rb                 # Run all tests sequentially
│   ├── run_all_parallel.rb        # Run tests in parallel
│   └── run_with_coverage.rb       # Run with coverage tracking
│
├── unit/                    # Pure unit tests (no model creation)
│   ├── equipment/           # Equipment efficiency lookups
│   ├── envelope/            # Envelope property lookups
│   ├── systems/             # System selection logic
│   └── dhw/                 # Domestic hot water calculations
│
├── component/               # Component tests (single components with models)
│   ├── autozone/            # Thermal zone creation and assignment ✅ 17/17 passing
│   ├── envelope/            # Building envelope ✅ 12/14 passing, 2 skipped
│   ├── hvac_components/     # Individual HVAC components
│   ├── schedules/           # Schedule creation and lookup
│   └── service_water_heating/  # Service water heating
│
├── systems/                 # Complete HVAC system tests
│   └── (NECB Systems 1-8)
│
├── integration/             # Multi-component integration tests
│
├── compliance/              # Code compliance and QAQC tests
│
├── edge_cases/              # Edge cases and robustness tests
│   └── test_necb_2011_edge_cases.rb ✅ 18/18 passing
│
└── coverage/                # Coverage reports (auto-generated)
```

## Test Categories

### Unit Tests (`unit/`)
**Purpose:** Test pure calculation methods without creating OpenStudio models
- Fast execution (< 1 second per test)
- No sizing runs required
- Test data lookups, efficiency calculations, property lookups

### Component Tests (`component/`)
**Purpose:** Test individual components with minimal OpenStudio models
- Use test fixtures or simple models
- Test component behavior in isolation
- Examples: envelope calculations, autozone logic, schedule creation

### System Tests (`systems/`)
**Purpose:** Test complete HVAC system implementations
- Test NECB Systems 1-8
- May require plant loops and complete system setup

### Integration Tests (`integration/`)
**Purpose:** Test interactions between multiple components
- System sizing workflows
- Complete building model creation

### Compliance Tests (`compliance/`)
**Purpose:** Verify code compliance and QAQC functionality
- NECB compliance checking
- Performance path calculations
- QAQC reporting

### Edge Cases (`edge_cases/`)
**Purpose:** Test robustness with unusual inputs and boundary conditions
- Invalid inputs, extreme values, missing data scenarios

## Running Tests

### Run all tests
```bash
bundle exec ruby test/necb_new/runners/run_all.rb
```

### Run with coverage
```bash
bundle exec ruby test/necb_new/runners/calculate_coverage.rb
```

### Run specific test
```bash
bundle exec ruby test/necb_new/component/autozone/test_autozone_edge_cases.rb
```

## Test Development Guidelines

### When to Create Each Type

**Unit Test** → Pure calculations, no models
**Component Test** → Single component with minimal model
**System Test** → Complete HVAC system
**Integration Test** → Multiple components together
**Compliance Test** → Code compliance verification
**Edge Case Test** → Robustness and boundary conditions

## Known Issues

1. **Conductance methods** - Missing `@standards_data['conductances']` data structure
   - See: `component/envelope/test_envelope_calculations.rb`
2. **System 6 tests** - Require complete plant loop setup (integration level)
   - See: `systems/test_system_6.rb`

## Contributing

When adding new tests:
1. Choose appropriate directory based on test type
2. Follow naming conventions (`test_*.rb`)
3. Run coverage report to verify improvements
4. Update this README with status

