# NECB New Test Suite

This directory contains the reorganized NECB test suite with improved structure and coverage tracking.

## Running Tests

### Default Behavior

By default, tests run in **parallel with coverage enabled** and automatically use **CPU-2 workers** for optimal speed while keeping the system responsive.

The runner tracks and displays:
- Individual test execution times (sorted longest-first)
- Pass/fail status for each test
- Aggregate statistics (tests, assertions, failures, errors, skips)
- Wall clock time vs sequential time (speedup factor)

### Quick Start

```bash
# Run all tests (parallel with coverage, auto-detects CPU count)
# DEFAULT: Uses CPU-2 workers with coverage enabled
ruby test/necb_new/run_all_tests.rb

# Run all tests without coverage (slightly faster)
ruby test/necb_new/run_all_tests.rb --no-coverage

# Run serially with coverage (for debugging)
ruby test/necb_new/run_all_tests.rb --serial

# Run a single test file
bundle exec ruby test/necb_new/unit/equipment/test_boiler_efficiency.rb
```

### Command Line Options

```bash
# Show help
ruby test/necb_new/run_all_tests.rb --help

# Serial execution with coverage (default when --serial)
ruby test/necb_new/run_all_tests.rb --serial

# Parallel execution (default, 8 workers)
ruby test/necb_new/run_all_tests.rb --parallel

# Parallel with custom worker count (default is CPU-2)
ruby test/necb_new/run_all_tests.rb --workers 16

# Disable coverage for maximum speed
ruby test/necb_new/run_all_tests.rb --no-coverage
```

## Test Organization

```
test/necb_new/
├── unit/                    # Unit tests (no sizing/simulation)
│   ├── equipment/          # Boiler, chiller, pump, fan efficiency tests
│   ├── envelope/           # U-value lookups, FDWR calculations
│   ├── systems/            # Fuel selection logic
│   └── dhw/                # Service water heating calculations
├── functional/             # Component tests (may use fixtures)
│   ├── envelope/           # FDWR/SRR application tests
│   ├── schedules/          # Schedule creation tests
│   ├── autozone/           # Autozone algorithm tests
│   ├── hvac_components/    # Terminal units, plant loops, zone equipment
│   └── service_water_heating/  # DHW system tests
├── integration/            # Integration tests (require sizing)
│   ├── hvac_systems/       # System 1-6 reference systems, HS08-HS16 ECM systems
│   ├── building/           # Complete building workflow tests
│   └── compliance/         # NECB compliance tests
├── edge_cases/             # Edge case and error handling tests
├── fixtures/               # Test fixtures (geometry, sized models)
│   ├── geometry/           # OSM geometry files
│   └── necb_fixture_manager.rb  # Fixture management
└── test_helper.rb          # Test setup with SimpleCov coverage
```

## Coverage Reporting

Code coverage is tracked using SimpleCov and focuses on the `/lib/openstudio-standards/standards/necb` folder.

Coverage works in **both parallel and serial modes**. SimpleCov automatically merges results from parallel processes.

**To view coverage:**
```bash
# Run tests with coverage (parallel - fastest)
ruby test/necb_new/run_all_tests.rb

# Run tests with coverage (serial - if needed)
ruby test/necb_new/run_all_tests.rb --serial

# Open coverage report
open test/necb_new/coverage/index.html  # macOS
xdg-open test/necb_new/coverage/index.html  # Linux
```

**Coverage groups:**
- NECB2011, NECB2015, NECB2017, NECB2020
- NECB Common
- NECB ECMS
- Component Standards

**Current coverage:** See `test/necb_new/coverage/index.html` after running with `--serial`

## Test Categories

### Unit Tests (Fast)
- Pure logic tests, no OpenStudio sizing
- Efficiency lookups, calculations, data validation
- Run time: < 5 minutes

### Functional Tests (Medium)
- Use fixtures or simple models
- May include component-level tests
- Run time: 10-30 minutes

### Integration Tests (Slow)
- Full system tests with sizing runs
- Complete building workflows
- Run time: 1-2 hours

## CI/CD Integration

For continuous integration, parallel mode gives you both speed AND coverage:

```bash
# Fast test run with coverage
ruby test/necb_new/run_all_tests.rb --parallel --workers 16

# Fast test run without coverage (slightly faster)
ruby test/necb_new/run_all_tests.rb --parallel --workers 16 --no-coverage
```

## Test Results Summary

Current test status:
- **Total tests:** ~1,018
- **Passing:** ~938 (92.1%)
- **Failures:** ~1
- **Errors:** ~5
- **Skips:** ~74

## Writing New Tests

1. Place tests in the appropriate directory (unit/functional/integration)
2. Use `test_helper.rb` for SimpleCov setup
3. Follow naming convention: `test_<feature>.rb`
4. Include descriptive comments at the top

Example:
```ruby
require_relative '../../test_helper'

# Test NECB Boiler Efficiency Rules
# Tests boiler efficiency lookup and application per NECB tables
class TestBoilerEfficiency < Minitest::Test
  def test_natural_gas_boiler_efficiency
    standard = Standard.build('NECB2011')
    # Test implementation...
  end
end
```

## Troubleshooting

**SimpleCov not generating coverage:**
- Make sure coverage is enabled (default): don't use `--no-coverage`
- Check that `DISABLE_SIMPLECOV` environment variable is not set
- For parallel runs, SimpleCov merges results at the end

**Parallel tests hanging:**
- Check for long-running tests with sizing/simulation
- Reduce worker count: `--workers 4`

**Memory issues:**
- Run fewer workers: `--workers 4`
- Run specific test categories instead of all tests
- Disable coverage temporarily: `--no-coverage`

## Legacy Files (Deprecated)

The following files are superseded by `run_all_tests.rb`:
- `run_all_for_coverage.rb` - Use `run_all_tests.rb --serial`
- `run_all_necb_new_tests.rb` - Use `run_all_tests.rb --serial`
- `run_all_parallel.rb` - Use `run_all_tests.rb --parallel`
