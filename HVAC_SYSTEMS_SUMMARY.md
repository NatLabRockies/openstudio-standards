# OpenStudio-Standards HVAC Systems Summary

## Overview

OpenStudio-Standards supports a **very large number** of HVAC system configurations. The exact count depends on how you define "a system":

### Base System Types: ~43 distinct system types

These are the fundamental system types in `model_add_hvac_system()`:

1. **PTAC** - Packaged Terminal Air Conditioner
2. **PTHP** - Packaged Terminal Heat Pump
3. **PSZ-AC** - Packaged Single Zone Air Conditioner
4. **PSZ-HP** - Packaged Single Zone Heat Pump
5. **PSZ-VAV** - Packaged Single Zone VAV
6. **Window AC** - Window Air Conditioner
7. **Residential AC** - Residential Air Conditioner
8. **Forced Air Furnace** - Commercial Forced Air Furnace
9. **Residential Forced Air Furnace**
10. **Residential Forced Air Furnace with AC**
11. **Residential Air Source Heat Pump**
12. **Residential Minisplit Heat Pumps**
13. **VAV Reheat** - Variable Air Volume with Reheat
14. **VAV No Reheat** - Variable Air Volume without Reheat
15. **VAV Gas Reheat** - VAV with Gas Reheat
16. **VAV PFP Boxes** - VAV with Parallel Fan Powered Boxes
17. **PVAV Reheat** - Packaged VAV with Reheat
18. **PVAV PFP Boxes** - Packaged VAV with Parallel Fan Powered Boxes
19. **VRF** - Variable Refrigerant Flow
20. **Water Source Heat Pumps** - WSHP with fluid cooler or cooling tower
21. **Ground Source Heat Pumps** - GSHP
22. **Fan Coil** - Fan Coil Units (2-pipe or 4-pipe)
23. **Radiant Slab** - Radiant Floor/Ceiling
24. **Baseboards** - Baseboard Heating (electric or hydronic)
25. **Unit Heaters** - Gas or Electric Unit Heaters
26. **High Temp Radiant** - High Temperature Radiant Heaters
27. **DOAS** - Dedicated Outdoor Air System
28. **DOAS with DCV** - DOAS with Demand Control Ventilation
29. **DOAS with Economizing** - DOAS with Economizer
30. **DOAS Cold Supply** - DOAS with cold supply air
31. **Evaporative Cooler** - Direct Evaporative Cooling
32. **ERVs** - Energy Recovery Ventilators (standalone)
33. **Residential ERVs** - Residential ERVs
34. **Residential Ventilators** - Residential Ventilators
35. **Ideal Air Loads** - Ideal loads for testing
36. **DistrictHeating** - District heating connection only
37. **DistrictCooling** - District cooling connection only

### CBECS System Combinations: 136 system types

The `cbecs_hvac.rb` module defines **136 different HVAC system combinations** based on the CBECS (Commercial Buildings Energy Consumption Survey) database. These represent real-world system configurations found in commercial buildings.

Examples of CBECS system combinations:
- Baseboard electric
- Baseboard gas boiler
- Baseboard central air source heat pump
- Baseboard district hot water
- Direct evap coolers with baseboard electric
- DOAS with fan coil chiller with boiler
- DOAS with fan coil air-cooled chiller with boiler
- DOAS with water source heat pumps
- DOAS with VRF
- Fan coil chiller with various heating options
- PTAC with various heating options
- PSZ-AC with various heating/cooling plant options
- VAV with various reheat and plant options
- Water source heat pumps with various plant options
- VRF with various supplemental heating options

Each base system can be combined with different:
- **Heating sources**: Natural gas, electricity, fuel oil, propane, district heating, heat pump
- **Cooling sources**: Electric DX, chilled water, district cooling, evaporative
- **Plant configurations**: Air-cooled vs water-cooled chillers, cooling towers vs fluid coolers
- **Terminal configurations**: Hot water reheat, electric reheat, gas reheat, parallel fan powered boxes

### NECB System Types: 8 standard + variations

NECB (Canadian) defines **8 primary system types** with single-speed and multi-speed variants:

1. **NECB System 1** - Residential/Small Commercial (≤ 600 m²)
   - Single zone makeup air unit OR
   - Packaged terminal units (PTAC/PTHP)
   - Single-speed and multi-speed variants

2. **NECB System 2** - Multi-zone VAV with reheat (non-residential)
   - Electric reheat terminals
   - Hot water or steam boilers for heating

3. **NECB System 3** - Single-zone heat pumps
   - Air source heat pumps
   - Used for residential, hotels, some offices
   - Single-speed and multi-speed variants

4. **NECB System 4** - VAV with reheat (large buildings > 14,000 m²)
   - Similar to System 2 but for larger buildings
   - Hot water or steam reheat

5. **NECB System 5** - Packaged VAV with reheat
   - Packaged rooftop units with VAV
   - Electric reheat

6. **NECB System 6** - VAV with PFP boxes and reheat
   - Parallel fan powered boxes
   - Hot water or electric reheat

7. **NECB System 7** - VAV with hot water reheat
   - Central boiler plant
   - Hot water reheat coils at terminals

8. **NECB System 8** - VAV with electric reheat
   - Electric resistance reheat at terminals

Each NECB system can have:
- Single-speed or multi-speed equipment
- Different heating fuels (gas, oil, propane, electric, district)
- Different plant configurations

## Total System Count Estimate

**Conservative estimate: 200-300 distinct system configurations**

When you account for all variations:
- 43 base system types
- × fuel type options (5-6 per system)
- × plant configurations (2-4 per system)
- × terminal equipment options (2-4 for VAV systems)
- × control variations (economizer, DCV, ERV, etc.)

**Realistic usable count: 50-75 common system types**

For typical building modeling work, most users work with a subset of ~50-75 commonly-used system configurations that cover 90%+ of real-world buildings.

## System Categories

### By Application
- **Small Commercial** (<600 m²): System 1, PTAC, PTHP, PSZ-AC, PSZ-HP, Residential systems
- **Medium Commercial** (600-14,000 m²): VAV systems, packaged rooftop units, fan coils
- **Large Commercial** (>14,000 m²): VAV with reheat, chilled water plants
- **Residential**: Residential furnaces, heat pumps, minisplits
- **Industrial**: Unit heaters, high-temp radiant, evaporative coolers

### By Complexity
- **Zone-level only**: PTAC, PTHP, Window AC, Baseboards, Unit Heaters
- **Single zone air systems**: PSZ-AC, PSZ-HP, Residential furnace
- **Multi-zone air systems**: VAV, PVAV, Fan Coil (multiple zones)
- **Complex systems**: VRF, WSHP, GSHP (zone equipment + plant)
- **Hybrid systems**: DOAS + zone equipment

### By Climate Suitability
- **Cold climates**: Heat pumps with auxiliary heat, hot water reheat, ERV
- **Hot-dry climates**: Evaporative cooling, economizers
- **Hot-humid climates**: Dehumidification, enthalpy economizers
- **All climates**: VAV systems, fan coils, VRF

## Key Features

### Fuel Flexibility
Every system supports multiple fuel types:
- **Heating**: Natural gas, propane, fuel oil #1/#2, electricity, district heating/steam, heat pump
- **Cooling**: Electric DX, chilled water, district cooling, evaporative

### Plant Equipment Options
- **Heating plants**: Boilers (condensing/non-condensing), heat pumps, district connections
- **Cooling plants**: Air-cooled chillers, water-cooled chillers, cooling towers, fluid coolers, district connections
- **Heat rejection**: Cooling towers (single/two-speed/variable), fluid coolers, evaporative fluid coolers

### Control Options
- Economizers (dry-bulb, enthalpy, differential)
- Demand control ventilation (DCV)
- Energy recovery ventilators (ERV)
- Static pressure reset
- Supply air temperature reset
- Night cycle control
- Optimal start/stop

### Terminal Equipment Options
- VAV boxes with reheat (hot water, electric, gas)
- Parallel fan powered boxes (constant/variable volume)
- Series fan powered boxes
- Fan coils (2-pipe, 4-pipe)
- Radiant panels
- Chilled beams

## Comparison with Simple API Design

The Simple API design document proposes organizing these into **manageable domain-based methods**:

### Simple API would provide:
- **~5-10 methods per domain** instead of 200+ system variants
- **Automatic system selection** based on building characteristics
- **Sensible defaults** based on standards (NECB, ASHRAE 90.1)
- **Progressive complexity** - simple cases are simple, complex cases possible

### Example mapping:
Instead of choosing from 136 CBECS systems, users would call:

```ruby
# Simple API - LLM-friendly
AirLoops.add_necb_system(model, standard: 'NECB2011', zones: :all, system_type: :autoselect)

# vs Current API - expert-level
model_add_cbecs_hvac_system(model, '90.1-2013', 'PVAV with PFP boxes and gas boiler reheat', zones)
```

The Simple API would internally map to the appropriate base system configuration.

## Recommendations for Simple API

### Must Support (High Priority)
1. **NECB Systems 1-8** - Required for Canadian work
2. **VAV with reheat** - Most common large commercial
3. **Packaged rooftop units** - Most common small/medium commercial
4. **PTACs/PTHPs** - Hotels, motels, residential
5. **Fan coils** - Common in existing buildings
6. **Baseboards + DOAS** - High-performance buildings
7. **VRF** - Increasingly popular

### Should Support (Medium Priority)
8. **Water source heat pumps** - Some commercial applications
9. **Ground source heat pumps** - High-performance buildings
10. **Radiant systems** - Specialty applications
11. **Unit heaters** - Warehouses, industrial
12. **Residential systems** - Multi-family modeling

### Nice to Have (Lower Priority)
13. **Evaporative cooling** - Specific climates
14. **High-temp radiant** - Industrial
15. **Window AC** - Existing building modeling
16. **Ideal loads** - Early design, testing

## Conclusion

OpenStudio-Standards is **extremely comprehensive** with 200-300+ system configurations possible. The Simple API should:

1. **Focus on the top 15-20 systems** that cover 90% of use cases
2. **Provide auto-selection** for NECB compliance (Systems 1-8)
3. **Support common variants** (fuel types, plant configs) through parameters
4. **Allow advanced users** to access full complexity when needed
5. **Make simple cases simple** through sensible defaults

This approach would make the library much more accessible to LLMs while preserving the full power of the underlying implementation.
