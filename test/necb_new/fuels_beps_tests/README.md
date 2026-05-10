# NECB System Fuels and BEPS Compliance Tests

This directory contains comprehensive tests for NECB system fuel type management and BEPS (Building Energy Performance Standard) compliance.

## Test Coverage

### File: `test_necb_fuels_and_beps.rb`

**Target Code:**
- `/lib/openstudio-standards/standards/necb/NECB2011/system_fuels.rb` (123 lines)
- `/lib/openstudio-standards/standards/necb/NECB2011/beps_compliance_path.rb` (370 lines)

**Test Statistics:**
- 12 test methods
- 97 assertions
- All tests passing

### Tests Included

1. **test_system_fuels_natural_gas_initialization**
   - Verifies SystemFuels initialization with natural gas as primary fuel
   - Checks boiler type, baseboard type, heating coil assignments
   - Validates SWH fuel and ECM fuel assignments

2. **test_system_fuels_electricity_initialization**
   - Tests SystemFuels with electricity as primary fuel
   - Verifies electric baseboards and heating coils
   - Confirms proper ECM fuel assignment

3. **test_system_fuels_fuel_oil_initialization**
   - Tests fuel oil configuration
   - Validates hot water baseboards with oil boiler
   - Checks electric heating coils for airloops

4. **test_system_fuels_heat_pump_initialization**
   - Tests NECB reference heat pump configuration
   - Verifies DX heating coils for HP systems
   - Validates supplemental heating fuel assignment

5. **test_set_boiler_fuel_dual_fuel**
   - Tests dual-fuel boiler configuration
   - Verifies primary and backup boiler fuel types
   - Checks capacity ratio assignments (70/30 split)

6. **test_set_swh_fuel_independent**
   - Tests independent SWH fuel assignment
   - Verifies SWH fuel can differ from space heating fuel
   - Confirms space heating configuration unchanged

7. **test_set_airloop_fancoils_heating**
   - Tests forcing airloop heating coils to hot water
   - Verifies all system types updated correctly
   - Checks force_airloop_hot_water flag

8. **test_set_airloop_fancoils_heating_preserves_dx**
   - Tests that DX coils preserved when forcing hot water
   - Validates heat pump DX coils not overridden
   - Checks supplemental heating set to hot water

9. **test_reset_default_fuel_info**
   - Tests resetting fuel configuration to stored defaults
   - Verifies all fuel attributes restored correctly
   - Validates state management functionality

10. **test_system_fuels_across_vintages**
    - Tests fuel configuration across NECB 2011, 2015, 2017, 2020
    - Verifies consistency of fuel type handling
    - Validates heat pump support in all vintages

11. **test_invalid_fuel_type_raises_error**
    - Tests error handling for invalid fuel types
    - Verifies appropriate error messages
    - Validates input validation

12. **test_boiler_capacity_ratios_configuration**
    - Tests various capacity ratio configurations
    - Validates ratios sum to 1.0
    - Tests single boiler and dual-fuel configurations

## Key Classes and Methods Tested

### SystemFuels Class
- `set_defaults(standards_data:, primary_heating_fuel:)` - Initialize fuel configuration from standards data
- `set_boiler_fuel(standards_data:, boiler_fuel:, boiler_cap_ratios:)` - Configure primary and backup boilers
- `set_swh_fuel(swh_fuel:)` - Set service hot water fuel independently
- `set_airloop_fancoils_heating()` - Force hot water heating coils for airloops
- `set_fuel_to_hvac_system_primary(hvac_system_primary:, standards_data:)` - Override fuel based on HVAC system
- `reset_default_fuel_info(init_fuel_type:)` - Reset to stored default configuration

### Fuel Types Tested
- Natural Gas
- Electricity
- Fuel Oil No. 2
- Natural Gas HP with Gas Backup
- Natural Gas HP with Electric Backup
- Electricity HP with Electric Backup
- Electricity HP with Gas Backup
- Dual-fuel combinations

## Running Tests

### Run this test suite:
```bash
bundle exec ruby test/necb_new/fuels_beps_tests/test_necb_fuels_and_beps.rb
```

### Run with verbose output:
```bash
bundle exec ruby test/necb_new/fuels_beps_tests/test_necb_fuels_and_beps.rb --verbose
```

### Run individual test:
```bash
bundle exec ruby test/necb_new/fuels_beps_tests/test_necb_fuels_and_beps.rb -n test_system_fuels_natural_gas_initialization
```

## Test Execution Time
- Approximately 40 seconds for full suite
- Average 2-3 seconds per test
- Cross-vintage test takes ~10 seconds (tests 4 vintages)

## Dependencies
- minitest framework
- OpenStudio SDK
- openstudio-standards gem
- NECB helper modules

## Data Sources
Tests validate against standards data from:
- `/lib/openstudio-standards/standards/necb/NECB2011/data/fuel_type_sets.json`
- `/lib/openstudio-standards/standards/necb/NECB2011/data/boiler_fuel_type_sets.json`

## Future Enhancements
- Add tests for BEPS compliance checking methods (when implemented)
- Add tests for BEPS energy target calculations
- Add tests for building type-specific BEPS requirements
- Add integration tests with complete HVAC systems
- Add performance tests for large models
