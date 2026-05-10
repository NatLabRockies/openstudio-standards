# OpenStudio Standards Simple API Design

**Goal:** Create an LLM-friendly API that organizes building modeling by domain with clear methods, sensible defaults, and minimal parameters.

**Primary Focus:** NECB (National Energy Code for Buildings - Canada) with support for other standards.

## Design Principles

1. **Domain-based organization** - Mirror how building designers work
2. **Keyword arguments** - Easier for LLMs to generate than positional args
3. **Sensible defaults** - Based on NECB standards and Canadian building practices
4. **Clear naming** - No abbreviations, full words (e.g., `domestic_hot_water` not `dhw`)
5. **Return value consistency** - All methods return `{ success: true/false, warnings: [], errors: [], info: {} }`
6. **Progressive disclosure** - Simple cases are simple, complex cases are possible
7. **Validation** - Helpful error messages guide users to correct usage
8. **Canadian-first** - Climate zones, building types, and system types based on Canadian codes

---

## Module: Geometry

**Purpose:** Create building geometry, thermal zones, and spaces.

### Methods

#### `create_rectangular_building`
Creates a simple rectangular building with automatic core/perimeter zoning.

```ruby
OpenstudioStandards::SimpleAPI::Geometry.create_rectangular_building(
  model,
  length: 100.0,                    # meters, required
  width: 50.0,                      # meters, required
  num_floors: 3,                    # required
  floor_to_floor_height: 3.8,       # meters, default: 3.8
  plenum_height: 1.0,               # meters, default: 1.0 (0 = no plenum)
  perimeter_zone_depth: 4.5,        # meters, default: 4.5
  building_type: 'Office',          # NECB building type (see Building Types below)
  create_zones: true,               # create thermal zones, default: true
  create_spaces: true,              # create spaces, default: true
  orientation: 0.0                  # degrees from north, default: 0.0
)
```

**Returns:** `{ success: true, zones: [...], spaces: [...], floor_area: 15000.0 }`

#### `create_l_shaped_building`
Creates an L-shaped building.

```ruby
OpenstudioStandards::SimpleAPI::Geometry.create_l_shaped_building(
  model,
  length_1: 100.0,                  # Length of first bar (meters)
  width_1: 30.0,                    # Width of first bar (meters)
  length_2: 60.0,                   # Length of second bar (meters)
  width_2: 30.0,                    # Width of second bar (meters)
  num_floors: 3,
  floor_to_floor_height: 3.8,
  plenum_height: 1.0,
  perimeter_zone_depth: 4.5,
  building_type: 'office',
  orientation: 0.0
)
```

#### `create_courtyard_building`
Creates a building with central courtyard.

```ruby
OpenstudioStandards::SimpleAPI::Geometry.create_courtyard_building(
  model,
  length: 100.0,                    # Outer dimensions
  width: 80.0,
  courtyard_length: 40.0,           # Inner courtyard dimensions
  courtyard_width: 30.0,
  num_floors: 3,
  floor_to_floor_height: 3.8,
  plenum_height: 1.0,
  perimeter_zone_depth: 4.5,
  building_type: 'office',
  orientation: 0.0
)
```

#### `create_from_floor_plates`
Creates building from custom floor plate polygons.

```ruby
OpenstudioStandards::SimpleAPI::Geometry.create_from_floor_plates(
  model,
  floor_plates: [
    {
      vertices: [[0,0], [100,0], [100,50], [0,50]],  # x,y coordinates in meters
      num_floors: 3,
      floor_to_floor_height: 3.8,
      building_type: 'office'
    }
  ],
  perimeter_zone_depth: 4.5
)
```

#### `assign_space_types`
Assigns space types to spaces based on building type.

```ruby
OpenstudioStandards::SimpleAPI::Geometry.assign_space_types(
  model,
  standard: '90.1-2019',
  building_type: 'office',          # or hash mapping spaces to types
  space_type_ratios: nil            # optional custom ratios
)
```

**NECB Building Types:** 
- `'Office'`, `'Retail'`, `'School/university'`, `'Hospital'`, `'Hotel'`, `'Motel'`
- `'Multi-unit residential'`, `'Dormitory'`, `'Warehouse'`, `'Warehouse - refrigerated'`
- `'Manufacturing facility'`, `'Automotive facility'`, `'Workshop'`
- `'Convention centre'`, `'Sports arena'`, `'Performing arts theatre'`, `'Motion picture theatre'`
- `'Gymnasium'`, `'Exercise centre'`, `'Library'`, `'Museum'`
- `'Religious'`, `'Courthouse'`, `'Town hall'`, `'Police station'`, `'Fire station'`, `'Post office'`, `'Penitentiary'`
- `'Health-care clinic'`, `'Parking garage'`, `'Transportation'`
- `'Dining - family'`, `'Dining - bar/lounge'`, `'Dining - cafeteria'`

---

## Module: Envelope

**Purpose:** Apply constructions to walls, roofs, windows, doors, and foundation.

### Methods

#### `apply_standard_constructions`
Applies standard-compliant constructions to all surfaces.

```ruby
OpenstudioStandards::SimpleAPI::Envelope.apply_standard_constructions(
  model,
  standard: 'NECB2011',             # 'NECB2011', 'NECB2015', 'NECB2017', 'NECB2020', or '90.1-2019'
  climate_zone: 'NECB HDD Method',  # or specific zone like 'NECB 7B', see Climate Zones below
  wall_type: 'mass',                # 'mass', 'steel_framed', 'wood_framed', 'metal_building'
  roof_type: 'iead',                # 'iead' (insulation entirely above deck), 'metal_building'
  foundation_type: 'slab',          # 'slab', 'basement', 'crawlspace'
  window_type: 'fixed',             # 'fixed', 'operable'
  skylight_type: 'glass'            # 'glass', 'plastic'
)
```

**Returns:** `{ success: true, constructions_applied: {...} }`

#### `set_window_to_wall_ratio`
Sets window-to-wall ratio for specified facades.

```ruby
OpenstudioStandards::SimpleAPI::Envelope.set_window_to_wall_ratio(
  model,
  ratio: 0.40,                      # required (0.0 to 1.0)
  facades: ['north', 'south', 'east', 'west'], # default: all facades
  sill_height: 0.9,                 # meters from floor
  window_height: 1.8,               # meters
  apply_to_floors: :all             # :all, :ground, :above_ground, [1,2,3]
)
```

#### `set_skylight_to_roof_ratio`
Sets skylight-to-roof ratio for roof surfaces.

```ruby
OpenstudioStandards::SimpleAPI::Envelope.set_skylight_to_roof_ratio(
  model,
  ratio: 0.03,                      # required (0.0 to 1.0)
  pattern: 'regular_grid'           # 'regular_grid', 'rows', 'perimeter'
)
```

#### `add_overhangs`
Adds horizontal shading overhangs above windows.

```ruby
OpenstudioStandards::SimpleAPI::Envelope.add_overhangs(
  model,
  projection_factor: 0.5,           # Projection / window height ratio
  facades: ['south'],               # default: all facades
  offset_from_top: 0.0              # meters from top of window
)
```

#### `set_infiltration`
Sets infiltration rates based on standard or custom value.

```ruby
OpenstudioStandards::SimpleAPI::Envelope.set_infiltration(
  model,
  standard: 'NECB2011',             # uses standard-specific method
  climate_zone: 'NECB HDD Method',
  infiltration_rate: nil            # or specify custom (m3/s-m2 @ 75 Pa)
)
```

---

## Module: Loads

**Purpose:** Apply internal loads (occupancy, lighting, equipment) and schedules.

### Methods

#### `apply_space_type_loads`
Applies internal loads based on space types and standard.

```ruby
OpenstudioStandards::SimpleAPI::Loads.apply_space_type_loads(
  model,
  standard: 'NECB2011',             # required
  include_lighting: true,
  include_equipment: true,
  include_occupancy: true,
  include_infiltration: true,
  include_ventilation: true
)
```

#### `set_lighting_power_density`
Overrides lighting power density.

```ruby
OpenstudioStandards::SimpleAPI::Loads.set_lighting_power_density(
  model,
  power_density: 10.0,              # W/m2
  spaces: :all,                     # :all or array of space names/objects
  standard: nil                     # or use standard lookup
)
```

#### `set_equipment_power_density`
Overrides equipment (plug load) power density.

```ruby
OpenstudioStandards::SimpleAPI::Loads.set_equipment_power_density(
  model,
  power_density: 8.0,               # W/m2
  spaces: :all,
  standard: nil
)
```

#### `set_occupancy_density`
Overrides occupancy density.

```ruby
OpenstudioStandards::SimpleAPI::Loads.set_occupancy_density(
  model,
  people_per_area: 0.05,            # people/m2 (or use area_per_person)
  area_per_person: nil,             # m2/person (alternative to people_per_area)
  spaces: :all
)
```

#### `add_internal_mass`
Adds internal thermal mass to spaces.

```ruby
OpenstudioStandards::SimpleAPI::Loads.add_internal_mass(
  model,
  area_per_floor_area: 2.0,         # ratio of mass area to floor area
  construction: 'default',          # or specific construction name
  spaces: :all
)
```

---

## Module: Schedules

**Purpose:** Create and manage schedules for systems and loads.

### Methods

#### `apply_standard_schedules`
Applies standard schedules to all loads based on space types.

```ruby
OpenstudioStandards::SimpleAPI::Schedules.apply_standard_schedules(
  model,
  standard: 'NECB2011',
  building_type: 'Office'           # NECB building type
)
```

#### `set_hours_of_operation`
Sets building hours of operation and updates schedules.

```ruby
OpenstudioStandards::SimpleAPI::Schedules.set_hours_of_operation(
  model,
  weekday_start: 8.0,               # hour (decimal, 8.5 = 8:30am)
  weekday_duration: 10.0,           # hours
  saturday_start: nil,              # nil = closed
  saturday_duration: nil,
  sunday_start: nil,
  sunday_duration: nil,
  ramp_hours: 1.0                   # hours for ramp up/down
)
```

#### `create_simple_schedule`
Creates a simple schedule ruleset.

```ruby
OpenstudioStandards::SimpleAPI::Schedules.create_simple_schedule(
  model,
  name: 'My Schedule',
  schedule_type: 'fractional',      # 'fractional', 'temperature', 'on_off'
  default_value: 0.0,
  rules: [
    { days: 'weekdays', hours: [8..18], value: 1.0 },
    { days: 'saturday', hours: [9..14], value: 0.5 }
  ]
)
```

---

## Module: ZoneHVAC

**Purpose:** Add zone-level HVAC equipment (terminal units, packaged equipment).

**Note:** NECB primarily uses system-level HVAC (see AirLoops module for NECB Systems 1-8). These zone-level methods are for special applications.

### Methods

#### `add_packaged_terminal_air_conditioners`
Adds PTACs to zones.

```ruby
OpenstudioStandards::SimpleAPI::ZoneHVAC.add_packaged_terminal_air_conditioners(
  model,
  standard: 'NECB2011',
  zones: :all,                      # :all or array of zone names/objects
  heating_type: 'electric',         # 'electric', 'gas', 'hot_water', 'none'
  cooling_type: 'electric',         # 'electric', 'none'
  ventilation: true                 # include outdoor air
)
```

#### `add_packaged_terminal_heat_pumps`
Adds PTHPs to zones.

```ruby
OpenstudioStandards::SimpleAPI::ZoneHVAC.add_packaged_terminal_heat_pumps(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_cop: nil,                 # nil = use standard
  cooling_cop: nil,                 # nil = use standard
  ventilation: true
)
```

#### `add_baseboards`
Adds baseboard heating to zones (common in Canadian buildings).

```ruby
OpenstudioStandards::SimpleAPI::ZoneHVAC.add_baseboards(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_type: 'electric',         # 'electric', 'hot_water'
  efficiency: nil                   # nil = use standard
)
```

#### `add_unit_heaters`
Adds unit heaters to zones (common in warehouses, garages).

```ruby
OpenstudioStandards::SimpleAPI::ZoneHVAC.add_unit_heaters(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_type: 'gas',              # 'gas', 'electric', 'hot_water'
  fan_type: 'constant_volume'       # 'constant_volume', 'cycling'
)
```

#### `add_vrf_terminals`
Adds VRF terminal units (for use with VRF outdoor unit).

```ruby
OpenstudioStandards::SimpleAPI::ZoneHVAC.add_vrf_terminals(
  model,
  standard: 'NECB2011',
  zones: :all,
  outdoor_unit: nil                 # VRF outdoor unit object (created separately)
)
```

---

## Module: SystemSelector

**Purpose:** Help select appropriate HVAC systems using a decision tree.

### Methods

#### `recommend_system`
Recommends HVAC system based on building characteristics.

```ruby
OpenstudioStandards::SimpleAPI::SystemSelector.recommend_system(
  building_type: 'Office',          # NECB building type
  floor_area: 5000.0,               # m²
  num_zones: 15,
  climate_zone: 'NECB 6',           # or 'NECB HDD Method'
  standard: 'NECB2011',
  province: 'ON',                   # For fuel selection
  heating_fuel: :auto,              # :auto or 'natural_gas', 'electricity', etc.
  cooling_fuel: :auto,
  high_efficiency: false,           # true = above-code performance
  special_requirements: []          # [:high_ventilation, :humidity_control, etc.]
)
```

**Returns:**
```ruby
{
  system_type: 2,                   # NECB System 2
  system_name: 'Multi-zone VAV with electric reheat',
  equipment_speed: :multi_speed,
  heating_fuel: 'natural_gas',
  cooling_fuel: 'electricity',
  economizer: true,
  erv_required: true,
  confidence: 0.95,
  rationale: [
    'Building area 5000 m² falls in 600-14,000 m² range for System 2',
    'Office building type is primary use case for VAV systems',
    'Climate Zone 6 requires ERV per NECB',
    'Natural gas is standard heating fuel in Ontario'
  ],
  alternatives: [
    { system_type: 4, reason: 'If future expansion planned' },
    { system_type: 5, reason: 'If packaged equipment preferred' }
  ]
}
```

#### `list_viable_systems`
Lists all viable system options ranked by suitability.

```ruby
OpenstudioStandards::SimpleAPI::SystemSelector.list_viable_systems(
  building_type: 'Office',
  floor_area: 5000.0,
  num_zones: 15,
  climate_zone: 'NECB 6',
  standard: 'NECB2011'
)
```

**Returns:** Array of system options with suitability scores (0-1)

#### `validate_system_choice`
Validates if a chosen system is appropriate.

```ruby
OpenstudioStandards::SimpleAPI::SystemSelector.validate_system_choice(
  system_type: 1,                   # User wants System 1
  building_type: 'Office',
  floor_area: 5000.0,               # But building is 5000 m²
  climate_zone: 'NECB 6',
  standard: 'NECB2011'
)
```

**Returns:**
```ruby
{
  valid: false,
  errors: ['System 1 is for buildings ≤600 m². This building is 5000 m².'],
  warnings: [],
  recommended_instead: [2, 4, 5]
}
```

---

## Module: AirLoops

**Purpose:** Add central air distribution systems.

**Note:** This module provides three levels of access:
1. **High-level (recommended for LLMs)** - `add_necb_system()` with auto-selection
2. **Mid-level** - Specific system types with sensible defaults
3. **Low-level** - Direct access to all 200+ system configurations via `add_cbecs_system()`

### Methods

#### `add_necb_system` (High-level - Recommended)
Adds NECB-compliant system automatically selected based on building characteristics.

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_necb_system(
  model,
  standard: 'NECB2011',             # 'NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'
  zones: :all,
  system_type: :autoselect,         # :autoselect or 1-8 (see NECB System Types below)
  equipment_speed: :multi_speed     # :single_speed or :multi_speed
)
```

**NECB System Types:**
- **System 1**: Residential/Small Commercial (≤ 600 m² / 6,458 ft²) - Single zone makeup air unit or packaged terminal units
- **System 2**: Multi-zone VAV with reheat (large non-residential)
- **System 3**: Single-zone heat pump (residential, hotels, some offices)
- **System 4**: VAV with reheat (large buildings > 14,000 m²)
- **System 5**: Packaged VAV with reheat
- **System 6**: VAV with parallel fan powered (PFP) boxes and reheat
- **System 7**: VAV with hot water reheat
- **System 8**: VAV with electric reheat

**Returns:** `{ success: true, air_loop: <AirLoop object>, plant_loops: [...], system_type: 3 }`

#### `add_necb_system`
Adds NECB-compliant system automatically selected based on building characteristics.

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_necb_system(
  model,
  standard: 'NECB2011',             # 'NECB2011', 'NECB2015', 'NECB2017', 'NECB2020'
  zones: :all,
  system_type: :autoselect,         # :autoselect or 1-8 (see NECB System Types below)
  equipment_speed: :multi_speed     # :single_speed or :multi_speed
)
```

**NECB System Types:**
- **System 1**: Residential/Small Commercial (≤ 600 m² / 6,458 ft²) - Single zone makeup air unit or packaged terminal units
- **System 2**: Multi-zone VAV with reheat (large non-residential)
- **System 3**: Single-zone heat pump (residential, hotels, some offices)
- **System 4**: VAV with reheat (large buildings > 14,000 m²)
- **System 5**: Packaged VAV with reheat
- **System 6**: VAV with parallel fan powered (PFP) boxes and reheat
- **System 7**: VAV with hot water reheat
- **System 8**: VAV with electric reheat

**Returns:** `{ success: true, air_loop: <AirLoop object>, plant_loops: [...], system_type: 3 }`

#### `add_vav_with_reheat`
Adds VAV system with reheat terminals (generic, not NECB-specific).

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_vav_with_reheat(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_fuel: 'natural_gas',      # 'natural_gas', 'electricity', 'fuel_oil', 'propane', 'district_heating'
  cooling_fuel: 'electricity',      # 'electricity', 'district_cooling'
  reheat_type: 'hot_water',         # 'hot_water', 'electric', 'gas'
  economizer: true,                 # enable air-side economizer
  demand_control_ventilation: true,
  heat_recovery: false,             # enable energy recovery (common in cold climates)
  system_name: 'VAV System 1'
)
```

**Returns:** `{ success: true, air_loop: <AirLoop object>, plant_loops: [...] }`

#### `add_packaged_rooftop_vav`
Adds packaged rooftop VAV unit.

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_packaged_rooftop_vav(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_fuel: 'natural_gas',
  cooling_type: 'two_speed_dx',     # 'single_speed_dx', 'two_speed_dx'
  reheat_type: 'electric',
  economizer: true,
  demand_control_ventilation: true,
  system_name: 'RTU-1'
)
```

#### `add_packaged_rooftop_single_zone`
Adds single-zone packaged rooftop units (common in small Canadian commercial buildings).

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_packaged_rooftop_single_zone(
  model,
  standard: 'NECB2011',
  zones: :all,                      # creates one RTU per zone
  heating_fuel: 'natural_gas',
  cooling_type: 'single_speed_dx',
  economizer: true,
  system_name_prefix: 'RTU'
)
```

#### `add_makeup_air_unit`
Adds makeup air unit (common in NECB System 1 applications).

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_makeup_air_unit(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_fuel: 'natural_gas',
  heating_coil_type: 'gas',         # 'gas', 'electric', 'hot_water'
  economizer: false,
  system_name: 'MAU'
)
```

#### `add_dedicated_outdoor_air_system`
Adds DOAS for ventilation (increasingly common in Canadian high-performance buildings).

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_dedicated_outdoor_air_system(
  model,
  standard: 'NECB2011',
  zones: :all,
  heat_recovery: true,              # highly recommended for Canadian climate
  heat_recovery_type: 'enthalpy',   # 'enthalpy', 'sensible'
  heat_recovery_effectiveness: nil, # nil = use standard
  supply_temperature: 18.0,         # C, default: 18
  system_name: 'DOAS'
)
```

---

### Advanced: Direct System Access

#### `add_cbecs_system` (Low-level - All 136 CBECS combinations)
Provides direct access to all CBECS system combinations for advanced users.

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_cbecs_system(
  model,
  standard: 'NECB2011',
  system_type: 'PVAV with gas boiler reheat',  # See CBECS system list
  zones: :all
)
```

**CBECS System Types** (136 total - partial list):
- Baseboard electric/gas/heat pump/district
- PTAC with various heating options (19 combinations)
- PTHP with various configurations (7 combinations)
- PSZ-AC with various plants (13 combinations)
- DOAS + Fan Coil with various plants (24 combinations)
- DOAS + VRF
- DOAS + Water Source Heat Pumps (4 combinations)
- VAV with various reheat and plants (32 combinations)
- VRF with various supplemental heating (6 combinations)
- Water Source Heat Pumps with various plants (4 combinations)
- [See HVAC_SYSTEMS_SUMMARY.md for complete list]

#### `add_any_system` (Low-level - Direct access to base 43 system types)
Direct access to base system types with full control.

```ruby
OpenstudioStandards::SimpleAPI::AirLoops.add_any_system(
  model,
  standard: 'NECB2011',
  system_type: 'VAV Reheat',        # One of 43 base system types
  zones: :all,
  heating_type: 'NaturalGas',
  zone_heating_type: nil,
  cooling_type: 'Electricity',
  system_options: {}                # Advanced options hash
)
```

**Base System Types** (43 total):
- PTAC, PTHP, PSZ-AC, PSZ-HP, PSZ-VAV
- Window AC, Residential AC
- Forced Air Furnace (commercial and residential variants)
- Residential Air Source Heat Pump, Residential Minisplit Heat Pumps
- VAV Reheat, VAV No Reheat, VAV Gas Reheat, VAV PFP Boxes
- PVAV Reheat, PVAV PFP Boxes
- VRF
- Water Source Heat Pumps, Ground Source Heat Pumps
- Fan Coil, Radiant Slab
- Baseboards, Unit Heaters, High Temp Radiant
- DOAS (4 variants), Evaporative Cooler
- ERVs, Residential ERVs, Residential Ventilators
- Ideal Air Loads

---

## Module: Plant

**Purpose:** Add central plant equipment (chillers, boilers, towers).

### Methods

#### `add_chilled_water_plant`
Adds chilled water plant with chillers and optional cooling tower.

```ruby
OpenstudioStandards::SimpleAPI::Plant.add_chilled_water_plant(
  model,
  standard: 'NECB2011',
  chiller_type: 'water_cooled_centrifugal',  # or 'air_cooled_scroll', etc.
  num_chillers: 2,
  cooling_capacity: :autosize,
  condenser_type: 'cooling_tower',  # 'cooling_tower', 'air_cooled', 'fluid_cooler'
  chilled_water_supply_temp: 6.7,   # C
  chilled_water_return_temp: 12.2,  # C
  condenser_water_supply_temp: 29.4, # C
  condenser_water_return_temp: 35.0, # C
  plant_loop_name: 'Chilled Water Loop'
)
```

**Returns:** `{ success: true, chilled_water_loop: <Loop>, condenser_loop: <Loop> }`

#### `add_hot_water_plant`
Adds hot water plant with boilers.

```ruby
OpenstudioStandards::SimpleAPI::Plant.add_hot_water_plant(
  model,
  standard: 'NECB2011',
  heating_fuel: 'natural_gas',      # 'natural_gas', 'electricity', 'fuel_oil', 'propane'
  boiler_type: 'condensing',        # 'condensing', 'non_condensing'
  num_boilers: 2,
  heating_capacity: :autosize,
  hot_water_supply_temp: 82.0,      # C
  hot_water_return_temp: 60.0,      # C
  plant_loop_name: 'Hot Water Loop'
)
```

#### `add_air_source_heat_pump_plant`
Adds air-source heat pump for heating and/or cooling.

```ruby
OpenstudioStandards::SimpleAPI::Plant.add_air_source_heat_pump_plant(
  model,
  standard: 'NECB2011',
  num_units: 2,
  heating_capacity: :autosize,
  cooling_capacity: :autosize,
  heating_cop: nil,                 # nil = use standard
  cooling_cop: nil,
  plant_loop_name: 'Heat Pump Loop'
)
```

#### `add_vrf_outdoor_unit`
Adds VRF outdoor condensing unit.

```ruby
OpenstudioStandards::SimpleAPI::Plant.add_vrf_outdoor_unit(
  model,
  standard: 'NECB2011',
  capacity: :autosize,
  heating_cop: nil,                 # nil = use standard
  cooling_cop: nil,
  defrost_strategy: 'resistive',    # 'resistive', 'reverse_cycle'
  system_name: 'VRF System'
)
```

**Returns:** `{ success: true, vrf_system: <VRF object> }`

#### `add_district_heating`
Adds district heating connection.

```ruby
OpenstudioStandards::SimpleAPI::Plant.add_district_heating(
  model,
  hot_water_supply_temp: 82.0,
  hot_water_return_temp: 60.0,
  plant_loop_name: 'District Heating Loop'
)
```

#### `add_district_cooling`
Adds district cooling connection.

```ruby
OpenstudioStandards::SimpleAPI::Plant.add_district_cooling(
  model,
  chilled_water_supply_temp: 6.7,
  chilled_water_return_temp: 12.2,
  plant_loop_name: 'District Cooling Loop'
)
```

---

## Module: DHW

**Purpose:** Add domestic hot water (service water heating) systems.

### Methods

#### `add_service_water_heating`
Adds complete service water heating system with equipment and end uses.

```ruby
OpenstudioStandards::SimpleAPI::DHW.add_service_water_heating(
  model,
  standard: 'NECB2011',
  fuel: 'natural_gas',              # 'natural_gas', 'electricity', 'heat_pump', 'district'
  heater_type: 'storage',           # 'storage', 'tankless', 'heat_pump'
  capacity: :autosize,
  efficiency: nil,                  # nil = use standard
  tank_volume: :autosize,
  supply_temperature: 60.0,         # C
  distribution_type: 'recirculation', # 'recirculation', 'no_recirculation'
  include_end_uses: true            # adds typical fixtures
)
```

#### `add_water_heater`
Adds water heater equipment only (no end uses).

```ruby
OpenstudioStandards::SimpleAPI::DHW.add_water_heater(
  model,
  standard: 'NECB2011',
  fuel: 'natural_gas',
  heater_type: 'storage',
  capacity: 50000.0,                # W
  tank_volume: 0.3,                 # m3
  efficiency: 0.80,
  name: 'Water Heater 1'
)
```

#### `add_water_use_equipment`
Adds water use end uses (fixtures) to spaces.

```ruby
OpenstudioStandards::SimpleAPI::DHW.add_water_use_equipment(
  model,
  standard: 'NECB2011',
  spaces: :all,
  peak_flow_rate: :standard,        # :standard or value in m3/s
  water_heater_loop: nil            # plant loop to connect to
)
```

---

## Module: Controls

**Purpose:** Add building control systems and sensors.

### Methods

#### `add_thermostats`
Adds thermostats to thermal zones.

```ruby
OpenstudioStandards::SimpleAPI::Controls.add_thermostats(
  model,
  standard: 'NECB2011',
  zones: :all,
  heating_setpoint: 21.0,           # C (nil = use standard)
  cooling_setpoint: 24.0,           # C (nil = use standard)
  heating_setback: 15.0,            # C during unoccupied
  cooling_setup: 30.0,              # C during unoccupied
  setback_schedule: nil             # nil = use standard occupancy schedule
)
```

#### `add_daylighting_controls`
Adds daylighting sensors and controls.

```ruby
OpenstudioStandards::SimpleAPI::Controls.add_daylighting_controls(
  model,
  standard: 'NECB2011',
  zones: :all,
  control_type: 'continuous',       # 'continuous', 'stepped', 'continuous_off'
  min_power_fraction: 0.3,          # minimum dimming level
  min_light_fraction: 0.3,
  sensor_height: 0.8                # meters above floor
)
```

#### `add_economizers`
Adds or modifies economizers on air systems.

```ruby
OpenstudioStandards::SimpleAPI::Controls.add_economizers(
  model,
  standard: 'NECB2011',
  climate_zone: 'NECB HDD Method',
  air_loops: :all,
  economizer_type: :code_required   # :code_required, 'differential_drybulb', 'differential_enthalpy', etc.
)
```

#### `add_demand_control_ventilation`
Adds CO2-based demand control ventilation.

```ruby
OpenstudioStandards::SimpleAPI::Controls.add_demand_control_ventilation(
  model,
  air_loops: :all,
  setpoint: 1000.0                  # ppm CO2
)
```

#### `add_energy_management_system`
Adds custom EMS program (advanced).

```ruby
OpenstudioStandards::SimpleAPI::Controls.add_energy_management_system(
  model,
  program_name: 'Custom Control',
  sensors: [...],
  actuators: [...],
  program_lines: [...]
)
```

---

## Module: ExteriorLoads

**Purpose:** Add exterior lighting and equipment.

### Methods

#### `add_exterior_lighting`
Adds exterior lighting for parking, facades, canopies, etc.

```ruby
OpenstudioStandards::SimpleAPI::ExteriorLoads.add_exterior_lighting(
  model,
  standard: 'NECB2011',
  lighting_zone: '3',               # '0' through '4'
  include_parking: true,
  parking_area: :autosize,          # m2 or :autosize from building footprint
  parking_fraction: 1.0,            # fraction of allowance to apply
  include_building_facades: true,
  include_canopies: true,
  include_driveways: true
)
```

---

## Module: Simulation

**Purpose:** Run simulations and sizing runs.

### Methods

#### `set_simulation_controls`
Configures simulation settings.

```ruby
OpenstudioStandards::SimpleAPI::Simulation.set_simulation_controls(
  model,
  run_design_days: true,
  run_annual: true,
  timesteps_per_hour: 4,
  solar_distribution: 'FullInteriorAndExterior',
  load_convergence_tolerance: 0.04,
  temperature_convergence_tolerance: 0.4
)
```

#### `run_sizing`
Runs HVAC sizing simulation.

```ruby
OpenstudioStandards::SimpleAPI::Simulation.run_sizing(
  model,
  output_directory: './output',
  cleanup: true                     # remove temporary files after
)
```

**Returns:** `{ success: true, sql_path: '...', warnings: [...] }`

#### `run_annual_simulation`
Runs annual energy simulation.

```ruby
OpenstudioStandards::SimpleAPI::Simulation.run_annual_simulation(
  model,
  weather_file: './weather.epw',
  output_directory: './output',
  design_days_only: false,
  run_period_start: nil,            # [month, day]
  run_period_end: nil,              # [month, day]
  cleanup: true
)
```

---

## Module: Validation

**Purpose:** Validate and check models.

### Methods

#### `check_model`
Performs comprehensive model checks.

```ruby
OpenstudioStandards::SimpleAPI::Validation.check_model(
  model,
  standard: 'NECB2011',
  climate_zone: 'NECB HDD Method',
  checks: :all                      # :all or array of check names
)
```

**Returns:** 
```ruby
{
  success: true,
  errors: [],
  warnings: [],
  info: {
    geometry_checks: { ... },
    envelope_checks: { ... },
    hvac_checks: { ... }
  }
}
```

#### `check_envelope_compliance`
Checks envelope compliance with standard.

```ruby
OpenstudioStandards::SimpleAPI::Validation.check_envelope_compliance(
  model,
  standard: 'NECB2011',
  climate_zone: 'NECB HDD Method'
)
```

#### `check_hvac_efficiency`
Checks HVAC equipment efficiency compliance.

```ruby
OpenstudioStandards::SimpleAPI::Validation.check_hvac_efficiency(
  model,
  standard: 'NECB2011'
)
```

#### `run_necb_qaqc`
Runs comprehensive NECB-specific quality assurance checks.

```ruby
OpenstudioStandards::SimpleAPI::Validation.run_necb_qaqc(
  model,
  standard: 'NECB2011',
  output_path: './qaqc_report.html'
)
```

---

## Module: Reporting

**Purpose:** Generate model summaries and reports.

### Methods

#### `get_model_summary`
Returns comprehensive model summary.

```ruby
OpenstudioStandards::SimpleAPI::Reporting.get_model_summary(model)
```

**Returns:**
```ruby
{
  building: {
    floor_area: 5000.0,
    conditioned_area: 4800.0,
    num_floors: 3,
    num_zones: 15,
    num_spaces: 15
  },
  envelope: {
    wall_area: 2400.0,
    roof_area: 1667.0,
    window_area: 480.0,
    window_to_wall_ratio: 0.20
  },
  hvac: {
    systems: [...],
    heating_capacity: 250000.0,
    cooling_capacity: 200000.0
  },
  loads: {
    lighting_power: 50000.0,
    equipment_power: 40000.0,
    occupancy: 100
  }
}
```

#### `generate_qaqc_report`
Generates QAQC HTML report.

```ruby
OpenstudioStandards::SimpleAPI::Reporting.generate_qaqc_report(
  model,
  output_path: './reports/qaqc.html'
)
```

---

## Module: Weather

**Purpose:** Set weather files and climate data.

### Methods

#### `set_weather_file`
Sets EPW weather file for the model.

```ruby
OpenstudioStandards::SimpleAPI::Weather.set_weather_file(
  model,
  weather_file_path: './weather/CAN_ON_Toronto.epw'
)
```

#### `set_climate_zone`
Sets climate zone (NECB uses HDD-based method).

```ruby
OpenstudioStandards::SimpleAPI::Weather.set_climate_zone(
  model,
  climate_zone: 'NECB HDD Method'   # Auto-calculates from weather file
  # Or specify directly: 'NECB 4', 'NECB 5', 'NECB 6', 'NECB 7A', 'NECB 7B', 'NECB 8'
)
```

#### `get_weather_file_from_location`
Downloads and sets weather file based on Canadian location.

```ruby
OpenstudioStandards::SimpleAPI::Weather.get_weather_file_from_location(
  model,
  city: 'Toronto',
  province: 'ON',                   # ON, QC, BC, AB, SK, MB, NS, NB, PE, NL, YT, NT, NU
  country: 'CAN'
)
```

**Canadian Provinces/Territories:**
- ON (Ontario), QC (Quebec), BC (British Columbia), AB (Alberta)
- SK (Saskatchewan), MB (Manitoba), NS (Nova Scotia), NB (New Brunswick)
- PE (Prince Edward Island), NL (Newfoundland and Labrador)
- YT (Yukon), NT (Northwest Territories), NU (Nunavut)

---

## Cross-Cutting Design Decisions

### Standard Names
All methods accept standard names in these formats:

**NECB (Primary - Canadian):**
- `'NECB2011'`, `'NECB2015'`, `'NECB2017'`, `'NECB2020'`
- `'BTAPPRE1980'`, `'BTAP1980TO2010'` (vintage standards)

**ASHRAE 90.1 (Secondary):**
- `'90.1-2019'`, `'90.1-2016'`, `'90.1-2013'`, `'90.1-2010'`, `'90.1-2007'`, `'90.1-2004'`

**Other Standards:**
- `'DEER 2020'`, `'IECC 2015'`

### Climate Zones

**NECB Climate Zones (Primary - based on Heating Degree Days):**
- `'NECB HDD Method'` - Auto-calculates from weather file (recommended)
- `'NECB 4'` - Zone 4 (<3000 HDD) - Warmest (e.g., coastal BC)
- `'NECB 5'` - Zone 5 (3000-3999 HDD) - e.g., Vancouver, Victoria
- `'NECB 6'` - Zone 6 (4000-4999 HDD) - e.g., Toronto, Montreal
- `'NECB 7A'` - Zone 7A (5000-5999 HDD) - e.g., Ottawa, Quebec City
- `'NECB 7B'` - Zone 7B (6000-6999 HDD) - e.g., Edmonton, Calgary
- `'NECB 8'` - Zone 8 (≥7000 HDD) - Coldest (e.g., Yellowknife, Iqaluit)

**ASHRAE 169 (Secondary):**
- `'ASHRAE 169-2013-5A'`, `'ASHRAE 169-2013-3B'`, etc.
- Can also use short form: `'5A'`, `'3B'`

### Return Values
All methods return a hash with:
```ruby
{
  success: true/false,
  errors: ['error message 1', ...],
  warnings: ['warning message 1', ...],
  info: { method_specific_data: ... }
}
```

### Zone/Space Selection
Most methods accept `zones:` or `spaces:` parameter with these options:
- `:all` - Apply to all zones/spaces
- Array of strings - Zone/space names: `['Zone 1', 'Zone 2']`
- Array of objects - Zone/space objects: `[zone_obj1, zone_obj2]`

### Autosize
Equipment capacity can be:
- `:autosize` - Let EnergyPlus autosize
- Numeric value - Specify capacity in Watts

### Optional vs Required Parameters
- Parameters with `# required` comment must be provided
- All others are optional with sensible defaults

---

## Example Workflows

### Workflow 1: LLM-Guided with Decision Tree (Recommended)

```ruby
require 'openstudio'
require 'openstudio-standards'

# Create blank model
model = OpenStudio::Model::Model.new

# Step 1: Get system recommendation
recommendation = OpenstudioStandards::SimpleAPI::SystemSelector.recommend_system(
  building_type: 'Office',
  floor_area: 5000.0,
  num_zones: 15,
  climate_zone: 'NECB HDD Method',
  standard: 'NECB2011',
  province: 'ON'
)

puts "Recommended: #{recommendation[:system_name]}"
puts "Reason: #{recommendation[:rationale].join('; ')}"

# Step 2: Apply recommendation (or ask user to choose from alternatives)
# ... geometry and envelope setup ...

result = OpenstudioStandards::SimpleAPI::AirLoops.add_necb_system(
  model,
  standard: recommendation[:standard],
  zones: :all,
  system_type: recommendation[:system_type],
  equipment_speed: recommendation[:equipment_speed]
)

if result[:success]
  puts "Added #{result[:system_type]} successfully"
else
  puts "Errors: #{result[:errors]}"
end
```

### Workflow 2: Simple API with Defaults

```ruby
require 'openstudio'
require 'openstudio-standards'

# Create blank model
model = OpenStudio::Model::Model.new

# Set weather (Canadian location)
OpenstudioStandards::SimpleAPI::Weather.get_weather_file_from_location(
  model,
  city: 'Toronto',
  province: 'ON',
  country: 'CAN'
)

# Set climate zone (auto-calculate from weather)
OpenstudioStandards::SimpleAPI::Weather.set_climate_zone(
  model,
  climate_zone: 'NECB HDD Method'
)

# Create geometry
OpenstudioStandards::SimpleAPI::Geometry.create_rectangular_building(
  model,
  length: 50.0,
  width: 30.0,
  num_floors: 3,
  floor_to_floor_height: 3.8,
  building_type: 'Office'           # NECB building type
)

# Assign space types
OpenstudioStandards::SimpleAPI::Geometry.assign_space_types(
  model,
  standard: 'NECB2011',
  building_type: 'Office'
)

# Add envelope
OpenstudioStandards::SimpleAPI::Envelope.apply_standard_constructions(
  model,
  standard: 'NECB2011',
  climate_zone: 'NECB HDD Method',
  wall_type: 'steel_framed'
)

OpenstudioStandards::SimpleAPI::Envelope.set_window_to_wall_ratio(
  model,
  ratio: 0.40
)

# Add internal loads
OpenstudioStandards::SimpleAPI::Loads.apply_space_type_loads(
  model,
  standard: 'NECB2011'
)

# Add NECB-compliant HVAC (auto-selects system type)
result = OpenstudioStandards::SimpleAPI::AirLoops.add_necb_system(
  model,
  standard: 'NECB2011',
  zones: :all,
  system_type: :autoselect,         # Will select appropriate NECB System 1-8
  equipment_speed: :multi_speed
)
puts "Selected NECB System Type #{result[:system_type]}"

# Add DHW
OpenstudioStandards::SimpleAPI::DHW.add_service_water_heating(
  model,
  standard: 'NECB2011',
  fuel: 'natural_gas'
)

# Add controls
OpenstudioStandards::SimpleAPI::Controls.add_thermostats(
  model,
  standard: 'NECB2011',
  zones: :all
)

OpenstudioStandards::SimpleAPI::Controls.add_daylighting_controls(
  model,
  standard: 'NECB2011',
  zones: :all
)

# Run NECB QAQC
OpenstudioStandards::SimpleAPI::Validation.run_necb_qaqc(
  model,
  standard: 'NECB2011',
  output_path: './necb_qaqc_report.html'
)

# Save model
model.save('./my_necb_building.osm', true)

# Run simulation
OpenstudioStandards::SimpleAPI::Simulation.run_annual_simulation(
  model,
  output_directory: './output'
)
```

### Workflow 3: Advanced User with Direct System Access

```ruby
require 'openstudio'
require 'openstudio-standards'

model = OpenStudio::Model::Model.new

# ... geometry setup ...

# Power user wants specific CBECS system combination
OpenstudioStandards::SimpleAPI::AirLoops.add_cbecs_system(
  model,
  standard: 'NECB2011',
  system_type: 'DOAS with water source heat pumps cooling tower with boiler',
  zones: model.getThermalZones
)

# Or use lowest-level API for maximum control
OpenstudioStandards::SimpleAPI::AirLoops.add_any_system(
  model,
  standard: 'NECB2011',
  system_type: 'Water Source Heat Pumps',
  zones: model.getThermalZones,
  heating_type: 'NaturalGas',
  cooling_type: 'Electricity',
  system_options: {
    condenser_loop_type: 'CoolingTower',
    heat_pump_capacity: 10000,  # W
    # ... many more options
  }
)
```

### Workflow 4: Validation Before Building

```ruby
# User/LLM wants to verify a system choice before applying it
validation = OpenstudioStandards::SimpleAPI::SystemSelector.validate_system_choice(
  system_type: 1,
  building_type: 'Office',
  floor_area: 5000.0,
  climate_zone: 'NECB 6',
  standard: 'NECB2011'
)

if validation[:valid]
  # Proceed with system
  OpenstudioStandards::SimpleAPI::AirLoops.add_necb_system(model, system_type: 1, ...)
else
  puts "System 1 not recommended: #{validation[:errors]}"
  puts "Consider systems: #{validation[:recommended_instead]}"
  
  # Get details on recommended alternatives
  validation[:recommended_instead].each do |sys_num|
    rec = OpenstudioStandards::SimpleAPI::SystemSelector.recommend_system(
      building_type: 'Office',
      floor_area: 5000.0,
      num_zones: 15,
      climate_zone: 'NECB 6',
      standard: 'NECB2011',
      system_type_override: sys_num
    )
    puts "System #{sys_num}: #{rec[:system_name]} - #{rec[:rationale].first}"
  end
end
```

---

## LLM Tool Use Pattern

### Typical LLM Interaction Flow

**User:** "Create a 3-story office building in Toronto with a VAV system"

**LLM thinks:**
1. Office building → likely NECB System 2, 4, or 5
2. Toronto → Ontario → NECB Climate Zone 6
3. 3 stories → estimate ~5000 m² → medium commercial
4. User said "VAV" → respecting user preference

**LLM calls:**
```ruby
# Step 1: Get recommendation to validate user's request
recommendation = SystemSelector.recommend_system(
  building_type: 'Office',
  floor_area: 5000.0,  # estimated
  num_zones: 15,       # estimated (5 zones per floor)
  climate_zone: 'NECB HDD Method',
  standard: 'NECB2011',
  province: 'ON'
)
# Returns: system_type: 2 (VAV) - matches user intent ✓

# Step 2: Create geometry
Geometry.create_rectangular_building(...)

# Step 3: Apply system (using recommendation)
AirLoops.add_necb_system(
  model,
  standard: 'NECB2011',
  zones: :all,
  system_type: recommendation[:system_type]
)
```

**LLM responds:** "I've created a 3-story office building in Toronto with NECB System 2 (VAV with electric reheat), which is the code-compliant system for medium-sized office buildings in Ontario."

---

**User:** "Actually, make it a small building, just 500 m²"

**LLM thinks:**
1. 500 m² < 600 m² → NECB System 1, not System 2
2. User originally wanted VAV, but that's not code-compliant for this size

**LLM calls:**
```ruby
recommendation = SystemSelector.recommend_system(
  building_type: 'Office',
  floor_area: 500.0,
  num_zones: 5,
  climate_zone: 'NECB HDD Method',
  standard: 'NECB2011',
  province: 'ON'
)
# Returns: system_type: 1, rationale includes "Buildings ≤600 m² require System 1"
```

**LLM responds:** "For a 500 m² building, NECB requires System 1 (single-zone makeup air unit or packaged terminal units) rather than VAV. System 1 is more appropriate and cost-effective for small buildings. Should I use System 1, or would you like to make the building larger to accommodate VAV?"

---

## Implementation Notes for LLMs

### Why This API is LLM-Friendly

1. **Clear domain boundaries** - Easy to map user intent ("add HVAC") to correct module
2. **Descriptive method names** - `add_packaged_rooftop_vav` is self-documenting
3. **Keyword arguments** - LLM can generate parameters in any order
4. **Sensible defaults** - Minimal parameters for common cases
5. **Consistent patterns** - All methods follow same structure
6. **Return values** - Success/error info helps LLM detect and fix issues
7. **Standard names** - Consistent across all methods (`'90.1-2019'`)

### Suggested LLM Tool Use Pattern

1. **User request:** "Create a 3-story office building in Chicago with VAV system"

2. **LLM understands:**
   - Geometry: 3 stories, office
   - Location: Chicago → weather file + climate zone 5A
   - HVAC: VAV system
   - Standard: Assume latest (90.1-2019)

3. **LLM generates calls:**
   ```ruby
   # Geometry domain
   Geometry.create_rectangular_building(model, num_floors: 3, building_type: 'office', ...)
   
   # Weather domain  
   Weather.set_weather_file(model, city: 'Chicago', state: 'IL')
   
   # Envelope domain
   Envelope.apply_standard_constructions(model, standard: '90.1-2019', climate_zone: '5A')
   
   # Loads domain
   Loads.apply_space_type_loads(model, standard: '90.1-2019')
   
   # AirLoops domain
   AirLoops.add_vav_with_reheat(model, standard: '90.1-2019', zones: :all)
   ```

4. **LLM checks return values** and reports errors/warnings to user

---

## NECB-Specific Features

### Energy Conservation Measures (ECMs)

The NECB implementation includes a comprehensive ECM framework. Consider adding:

```ruby
module OpenstudioStandards::SimpleAPI::NECB
  # Apply NECB ECMs
  def self.apply_ecm(
    model,
    standard: 'NECB2011',
    ecm_type: :erv,                 # :erv, :natural_ventilation, :pv_ground, :hvac_upgrade
    ecm_options: {}
  )
  end
end
```

### Provincial Variations

NECB implementation accounts for provincial differences in fuel availability and costs:

```ruby
# Fuel selection based on province
OpenstudioStandards::SimpleAPI::Weather.get_weather_file_from_location(
  model,
  city: 'Vancouver',
  province: 'BC',                   # BC has different fuel preferences
  country: 'CAN'
)
# This could auto-select appropriate heating fuels (e.g., electric in BC, gas in ON)
```

### Costing and Economics

NECB includes Canadian-specific costing data (RS Means, utility rates, carbon pricing):

```ruby
module OpenstudioStandards::SimpleAPI::Economics
  def self.calculate_lifecycle_cost(
    model,
    province: 'ON',
    study_period_years: 25,
    include_carbon_pricing: true
  )
  end
end
```

## Questions for Review

1. **NECB System Selection**: Is the auto-select approach clear? Should we provide more guidance on when to use each system type?

2. **Missing NECB features?** Are there NECB-specific capabilities not covered (thermal bridging, BEPS compliance path)?

3. **Method granularity?** Are methods at right level (not too high-level, not too detailed)?

4. **Parameter names?** Clear enough for Canadian context? Any ambiguous names?

5. **Default behaviors?** Are the defaults sensible for Canadian building practices?

6. **Return value structure?** Is `{ success:, errors:, warnings:, info: }` sufficient?

7. **Climate zone handling?** Is the HDD-based method clear? Should we auto-detect province-based defaults?

8. **Missing methods?** What common Canadian building operations are not covered?

9. **Provincial variations?** Should we expose more province-specific defaults (fuel types, utility rates)?

10. **NECB QAQC integration?** Should validation be more integrated or remain separate?

11. **ECM framework?** Should energy conservation measures be first-class in the API?

12. **Vintage buildings?** Should BTAPPRE1980 and BTAP1980TO2010 be more prominent for retrofit work?
