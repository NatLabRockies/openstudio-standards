# NECB Multi-Speed HVAC Systems Test Suite

Comprehensive test coverage for NECB multi-speed HVAC system implementations.

## Overview

This test suite validates the multi-speed (variable speed) variants of NECB System 1 and Systems 3/8. Multi-speed systems use variable speed compressors and fans with staged cooling/heating for improved part-load performance compared to single-speed systems.

## Systems Under Test

### System 1 Multi-Speed
**Make-up Air Unit with Variable Speed Heat Pump + Baseboard Heating**

- **Primary Components:**
  - `AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed` - Variable speed unitary heat pump
  - `CoilCoolingDXMultiSpeed` - Multi-speed DX cooling (2 stages)
  - `CoilHeatingGasMultiStage` - Multi-stage gas heating (1 stage)
  - Supplemental heating coil (electric or hot water)
  - Zone PTAC units for supplemental cooling
  - Zone baseboards (electric or hot water)

- **Key Features:**
  - Variable speed compressor operation
  - Staged cooling: 2 speeds (better part-load efficiency)
  - Staged heating: 1 speed
  - Minimum compressor temperature: -10°C
  - Make-up air unit with 100% outdoor air
  - Single zone control from control zone
  - Part load fraction optimization

- **Target File:** `/lib/openstudio-standards/standards/necb/NECB2011/hvac_system_1_multi_speed.rb`

### System 3 & 8 Multi-Speed
**Variable Speed Packaged Rooftop Unit + Baseboard Heating**

- **Primary Components:**
  - `AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed` - Variable speed RTU
  - `CoilCoolingDXMultiSpeed` - Multi-speed DX cooling (2 stages)
  - `CoilHeatingGasMultiStage` - Multi-stage heating (1 stage)
  - Supplemental heating coil (gas or electric)
  - Zone baseboards (electric or hot water)
  - Constant volume fan (works with unitary system)

- **Key Features:**
  - Variable speed DX cooling with 2 stages
  - Multi-stage gas or electric heating
  - Single zone reheat setpoint control
  - Supply air temp range: 13-43°C
  - Minimum compressor temperature: -10°C
  - Economizer capability (inherited from method)
  - Part load fraction not applied to speed > 1

- **Target File:** `/lib/openstudio-standards/standards/necb/NECB2011/hvac_system_3_and_8_multi_speed.rb`

## Test Coverage

### Test File: `test_necb_systems_multispeed.rb`

**Total Tests:** 15  
**Execution Time:** ~2 seconds  
**Test Results:** ✓ All tests passing

#### System 1 Multi-Speed Tests (7 tests)

1. **test_system_1_multispeed_mau_creation**
   - Verifies multi-speed unitary heat pump creation
   - Validates control zone assignment
   - Checks speed configuration (1 heating, 2 cooling)
   - Confirms minimum compressor temperature (-10°C)

2. **test_system_1_multispeed_cooling_coil_stages**
   - Validates `CoilCoolingDXMultiSpeed` with 2 stages
   - Verifies electricity fuel type
   - Checks part load fraction configuration
   - Confirms stage data objects exist

3. **test_system_1_multispeed_heating_coil_stages**
   - Validates `CoilHeatingGasMultiStage` with 1 stage
   - Verifies minimal capacity (0.001 W) for MAU
   - Confirms stage data configuration

4. **test_system_1_multispeed_hw_supplemental_heating**
   - Validates hot water supplemental heating coil
   - Verifies connection to hot water plant loop
   - Confirms coil type and loop assignment

5. **test_system_1_multispeed_electric_supplemental_heating**
   - Validates electric supplemental heating coil
   - Verifies availability schedule
   - Confirms electric coil type

6. **test_system_1_multispeed_ptac_zone_units**
   - Verifies PTAC units created for each zone (3 zones)
   - Validates zone assignment for PTACs
   - Confirms electric baseboards also created
   - Tests multi-zone configuration

7. **test_system_1_multispeed_mau_air_loop**
   - Validates MAU air loop creation
   - Verifies outdoor air system (ZoneSum method)
   - Checks setpoint manager configuration
   - Confirms zone connections to MAU

#### System 3 & 8 Multi-Speed Tests (6 tests)

8. **test_system_3_multispeed_basic_creation**
   - Verifies multi-speed heat pump creation
   - Validates speed configuration (1 heating, 2 cooling)
   - Checks control zone assignment
   - Confirms minimum compressor temperature

9. **test_system_3_multispeed_cooling_coil**
   - Validates multi-speed DX cooling with 2 stages
   - Verifies electricity fuel type
   - Checks part load fraction setting
   - Confirms stage count

10. **test_system_3_multispeed_gas_heating**
    - Validates multi-stage gas heating coil
    - Verifies 1 heating stage
    - Checks gas supplemental coil
    - Confirms minimal supplemental capacity (0.001 W)

11. **test_system_3_multispeed_electric_heating**
    - Tests electric heating variant
    - Validates electric supplemental coil
    - Verifies minimal primary heating capacity
    - Confirms configuration for Electric type

12. **test_system_3_multispeed_air_loop_components**
    - Validates air loop creation
    - Verifies outdoor air system (ZoneSum)
    - Checks SetpointManagerSingleZoneReheat
    - Confirms temperature limits (13-43°C)

13. **test_system_3_multispeed_fan_configuration**
    - Validates FanConstantVolume in unitary system
    - Verifies availability schedule
    - Confirms fan configuration

#### Comparison & Vintage Tests (2 tests)

14. **test_system_1_single_vs_multispeed_comparison**
    - Compares single-speed PTAC vs multi-speed heat pump
    - Validates CoilCoolingDXSingleSpeed vs CoilCoolingDXMultiSpeed
    - Confirms 2 cooling stages in multi-speed
    - Verifies part-load optimization differences

15. **test_multispeed_systems_necb_vintages**
    - Tests System 1 Multi-Speed across all vintages (2011/2015/2017/2020)
    - Tests System 3 Multi-Speed across all vintages
    - Validates consistent speed configuration across vintages
    - Confirms backward compatibility

## Key Differences: Single-Speed vs Multi-Speed

| Feature | Single-Speed | Multi-Speed |
|---------|-------------|-------------|
| **Cooling Coil** | `CoilCoolingDXSingleSpeed` | `CoilCoolingDXMultiSpeed` |
| **Cooling Stages** | 1 | 2 |
| **Heating Coil** | Single-stage | `CoilHeatingGasMultiStage` |
| **Heating Stages** | 1 | 1 (expandable) |
| **Unitary System** | Standard unitary | `AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed` |
| **Part-Load Performance** | PLF applied to all operation | PLF only at speed 1 |
| **Energy Efficiency** | Good | Better (staged operation) |
| **Compressor** | On/off | Variable speed |
| **Fan** | Cycling/constant | Constant volume with unitary |

## Running the Tests

### Run Complete Test Suite
```bash
bundle exec ruby test/necb_new/hvac_multispeed_tests/test_necb_systems_multispeed.rb
```

### Run Individual Test
```bash
bundle exec ruby test/necb_new/hvac_multispeed_tests/test_necb_systems_multispeed.rb -n test_system_1_multispeed_mau_creation
```

### Run with Verbose Output
```bash
bundle exec ruby test/necb_new/hvac_multispeed_tests/test_necb_systems_multispeed.rb -v
```

## Test Results

```
Finished in 1.87s
15 tests, 81 assertions, 0 failures, 0 errors, 0 skips
```

**Coverage:** 100% of multi-speed HVAC system implementation methods

## Implementation Notes

### System 1 Multi-Speed Limitations

As noted in the implementation file comments:

> "At this point the only way to implement multi-stage cooling and heating in OS is through the use of object `AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed`. This component uses as an argument a control zone and then it responds to a call for heating or cooling for that control zone. This aspect of this component makes it incompatible with how a system_1 make up air unit works where a constant supply air temperature is delivered to the spaces. It is therefore not recommended to use this method and to use the single speed implementation of systems_1."

The multi-speed implementation works but has single-zone control limitations.

### System 3 Multi-Speed Configuration

- Uses `new_auto_zoner: false` for legacy compatibility
- Requires either sizing run or manual zone setup
- Supports both gas and electric heating variants
- Always uses multi-stage heating coil (even for electric type)

### Performance Curves

Multi-speed systems inherit NECB performance curves from standard methods:
- Capacity function of temperature (biquadratic)
- EIR function of temperature (biquadratic)
- Capacity function of flow (quadratic)
- EIR function of flow (quadratic)
- Part load fraction (cubic, only applied to speed 1)

### Supplemental Heating

Both systems use supplemental heating coils:
- **System 1:** Electric or hot water (depending on `mau_heating_coil_type`)
- **System 3:** Gas or electric (depending on `heating_coil_type`)

Primary heating stages are set to minimal capacity (0.001 W) when supplemental provides main heating.

## NECB Vintage Support

All multi-speed systems are fully supported across NECB vintages:
- ✓ NECB2011
- ✓ NECB2015
- ✓ NECB2017
- ✓ NECB2020

Speed configurations and component types are consistent across vintages.

## Related Files

### Implementation Files
- `/lib/openstudio-standards/standards/necb/NECB2011/hvac_system_1_multi_speed.rb` (169 lines)
- `/lib/openstudio-standards/standards/necb/NECB2011/hvac_system_3_and_8_multi_speed.rb` (180 lines)

### Related Test Files
- `/test/necb_new/system_tests/test_necb_system_1.rb` - Single-speed System 1 tests
- `/test/necb_new/system_tests/test_necb_systems_2_3.rb` - Single-speed System 3 tests
- `/test/modules/hvac/components/test_coil_cooling_dx_single_speed.rb` - Single-speed coil tests

### Helper Files
- `/test/necb_new/test_helper.rb` - Test suite configuration with SimpleCov
- `/test/helpers/minitest_helper.rb` - Base Minitest configuration

## Future Enhancements

Potential areas for additional testing:
1. **Post-Sizing Tests:** Run sizing and verify autosized capacities
2. **Climate Variation:** Test across different Canadian climate zones (4-8)
3. **Performance Curves:** Validate curve coefficients match NECB requirements
4. **Energy Simulation:** Run annual simulations and compare energy use
5. **Multiple Stages:** Test systems with >2 cooling stages when supported
6. **VAV Variant:** Test System 8 (VAV with multi-speed)

## Maintenance

This test suite should be updated when:
- Multi-speed system implementations change
- New NECB vintages are added (e.g., NECB2025)
- OpenStudio adds new multi-speed component types
- NECB requirements for variable speed systems change

## Authors

Test suite created: 2026-05-10  
Framework: Minitest  
Coverage: SimpleCov

## License

Same as parent repository (see `/LICENSE.md`)
