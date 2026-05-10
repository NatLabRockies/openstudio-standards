# HVAC System Selection Decision Tree

## Overview

This decision tree helps select the appropriate HVAC system based on building characteristics, climate, and requirements. It's designed to be machine-readable for LLM tools while remaining human-understandable.

## Decision Tree Structure

### Level 1: Code/Standard Compliance

**Question 1: Which building code applies?**
- **NECB (Canada)** → Go to NECB Decision Tree
- **ASHRAE 90.1 (USA)** → Go to CBECS/General Decision Tree
- **Other/Custom** → Go to General Decision Tree

---

## NECB Decision Tree (Canada)

### Step 1: Building Type and Size

**Question: What is the building type and conditioned floor area?**

| Building Type | Area | Primary System | Alternate System |
|--------------|------|----------------|------------------|
| **Residential** | Any size | System 3 (Heat Pumps) | System 1 (PTAC/PTHP) |
| **Hotel/Motel** | Any size | System 3 (Heat Pumps) | System 1 (PTAC/PTHP) |
| **Small Commercial** | ≤ 600 m² | System 1 (MAU or PTAC) | System 3 (Heat Pumps) |
| **Office** | 600-14,000 m² | System 2 (VAV w/ reheat) | System 4 or 5 |
| **Office** | > 14,000 m² | System 4 (VAV w/ reheat) | System 6 (VAV w/ PFP) |
| **Retail** | 600-14,000 m² | System 2 (VAV w/ reheat) | System 5 (PVAV) |
| **School** | 600-14,000 m² | System 2 (VAV w/ reheat) | System 4 or 6 |
| **School** | > 14,000 m² | System 4 (VAV w/ reheat) | System 6 (VAV w/ PFP) |
| **Hospital** | > 600 m² | System 4 (VAV w/ reheat) | System 6 (VAV w/ PFP) |
| **Warehouse** | Any size | System 1 (Unit Heaters) | System 2 (VAV) |

### Step 2: Equipment Speed Selection

**Question: What equipment efficiency level?**
- **Code minimum** → Single-speed equipment
- **Above code** → Multi-speed equipment (more efficient, better part-load performance)

### Step 3: Fuel Selection

**Question: What is the primary heating fuel?**

Based on province and availability:
- **British Columbia** → Often electric or natural gas
- **Ontario/Quebec** → Primarily natural gas
- **Alberta** → Natural gas
- **Atlantic provinces** → Fuel oil, propane, or electric
- **Northern territories** → Often fuel oil or propane

**NECB Result:**
```ruby
{
  system_type: 2,  # NECB System 2
  equipment_speed: :multi_speed,
  heating_fuel: 'natural_gas',
  standard: 'NECB2011'
}
```

---

## General Decision Tree (Non-NECB)

### Step 1: Scale and Zoning

**Question 1: How many thermal zones?**

- **1 zone** → Go to Single Zone Systems
- **2-10 zones** → Go to Small Multi-Zone Systems  
- **> 10 zones** → Go to Large Multi-Zone Systems

### Step 2A: Single Zone Systems

**Question: What is the building type?**

| Building Type | Recommended System | Notes |
|--------------|-------------------|-------|
| **Hotel/Motel room** | PTAC or PTHP | Individual zone control |
| **Apartment unit** | PTAC, PTHP, or Minisplit | Individual metering |
| **Small office/retail** | PSZ-AC or PSZ-HP | Packaged rooftop unit |
| **Residential** | Residential Furnace w/ AC or Heat Pump | Standard residential |
| **Warehouse** | Unit Heaters + optional cooling | Heating-only or minimal cooling |

**Follow-up: Heating fuel preference?**
- Natural gas → Gas furnace/heating
- Electricity → Heat pump or electric resistance
- Fuel oil → Oil furnace
- District → District connections

**Single Zone Result:**
```ruby
{
  system_category: :single_zone,
  system_type: 'PSZ-AC',
  heating_fuel: 'natural_gas',
  cooling_fuel: 'electricity'
}
```

### Step 2B: Small Multi-Zone Systems (2-10 zones)

**Question: Central plant or distributed equipment?**

#### Option A: Distributed Equipment
- **VRF** (Variable Refrigerant Flow)
  - Best for: Diverse loads, individual zone control
  - Pros: High efficiency, flexible
  - Cons: Higher first cost
  
- **Water Source Heat Pumps**
  - Best for: Hotels, apartments, offices with diverse loads
  - Pros: Heat recovery between zones
  - Cons: Requires condenser water loop

- **Fan Coils + Central Plant**
  - Best for: Existing buildings, hydronic systems
  - Pros: Quiet, flexible
  - Cons: Lower air flow, needs ventilation strategy

#### Option B: Central Air System
- **Packaged Rooftop VAV**
  - Best for: Retail, small office
  - Pros: Simple, lower first cost
  - Cons: Less efficient than VRF

- **Makeup Air Unit + Zone Heating**
  - Best for: Manufacturing, warehouses
  - Pros: Good for high ventilation needs
  - Cons: Limited cooling

**Small Multi-Zone Result:**
```ruby
{
  system_category: :small_multizone,
  system_type: 'VRF',
  zones: 5,
  heating_fuel: 'electricity',
  cooling_fuel: 'electricity'
}
```

### Step 2C: Large Multi-Zone Systems (>10 zones)

**Question: What is the building internal load profile?**

#### High Internal Loads (Office, Hospital, School)
→ **VAV with Reheat**
- Chilled water plant (water-cooled chiller + cooling tower)
- Hot water plant (boilers) or district heating
- VAV boxes with hot water or electric reheat

**Variations:**
- System 4 (NECB): Standard VAV with reheat
- System 6 (NECB): VAV with parallel fan powered boxes (better for perimeter zones)
- VAV No Reheat: Cooling-only applications

#### Medium Internal Loads (Retail, Assembly)
→ **Packaged VAV (PVAV)**
- Packaged rooftop units with VAV
- DX cooling, gas or electric heating
- Electric reheat terminals

#### Variable Loads with Diverse Schedule
→ **DOAS + Zone Equipment**
- DOAS for ventilation (with ERV in cold climates)
- VRF, WSHP, or fan coils for zone conditioning
- Best for high-performance buildings

**Large Multi-Zone Result:**
```ruby
{
  system_category: :large_multizone,
  system_type: 'VAV Reheat',
  air_system: {
    type: 'vav',
    economizer: true,
    erv: true  # if cold climate
  },
  plant: {
    heating: { type: 'boiler', fuel: 'natural_gas' },
    cooling: { type: 'water_cooled_chiller' }
  },
  terminals: {
    type: 'vav_reheat',
    reheat_fuel: 'hot_water'
  }
}
```

---

## Climate-Based Refinements

### Cold Climates (HDD > 5000 or ASHRAE Zones 6-8)

**Recommended additions:**
- Energy Recovery Ventilator (ERV) - Required by NECB in many zones
- Hot water reheat (not electric) - Better part-load performance
- Condensing boilers - Higher efficiency
- Heat pumps with auxiliary heat

### Hot-Dry Climates (ASHRAE Zones 2B, 3B)

**Recommended additions:**
- Economizers (dry-bulb control)
- Evaporative cooling (pre-cooling or stand-alone)
- Higher ventilation rates (free cooling)

### Hot-Humid Climates (ASHRAE Zones 1A, 2A, 3A)

**Recommended additions:**
- Dehumidification controls
- Enthalpy-based economizers (more selective)
- Dedicated dehumidification equipment for pools, spas

### Mild Climates (ASHRAE Zones 3C, 4C)

**Recommended additions:**
- Heat pumps (efficient year-round)
- Economizers (extended use)
- Natural ventilation strategies

---

## Fuel Availability Decision

### Primary Heating Fuel Selection

**Question: What fuels are available?**

| Fuel Available | Best Use Cases | Considerations |
|----------------|----------------|----------------|
| **Natural Gas** | Most commercial applications | Lowest operating cost in most areas |
| **Electricity** | Heat pumps, small loads | High efficiency with heat pumps |
| **Fuel Oil** | Rural areas, backup | Higher emissions, storage required |
| **Propane** | Rural areas without gas | Similar to natural gas |
| **District Heating** | Urban cores, campuses | No on-site equipment |
| **None (cooling only)** | Warm climates, data centers | Cooling-only systems |

---

## Special Considerations

### High Ventilation Requirements

**Examples:** Laboratories, hospitals, commercial kitchens, manufacturing

**Recommended systems:**
- 100% outdoor air units
- Dedicated outdoor air systems (DOAS)
- Energy recovery highly recommended

### High Humidity Control

**Examples:** Museums, data centers, natatoriums

**Recommended systems:**
- DOAS with dedicated dehumidification
- Chilled water with reheat
- Desiccant dehumidification

### High Occupant Density

**Examples:** Theaters, auditoriums, convention centers

**Recommended systems:**
- Demand control ventilation (DCV)
- High-capacity ventilation systems
- CO2-based controls

### Industrial/Warehouse

**Examples:** Manufacturing, warehouses, shipping/receiving

**Recommended systems:**
- Unit heaters (heating only)
- Evaporative cooling (cooling only in dry climates)
- Makeup air units (if process exhaust)
- Radiant heating (high ceilings)

---

## Decision Tree API for LLMs

### Proposed Tool Interface

```ruby
module OpenstudioStandards
  module SimpleAPI
    module SystemSelector
      
      # Interactive decision tree
      def self.recommend_system(
        building_type:,           # 'Office', 'Retail', 'Hotel', etc.
        floor_area:,              # m² or ft²
        num_zones:,               # Integer
        climate_zone:,            # 'NECB 6', 'ASHRAE 5A', etc.
        standard:,                # 'NECB2011', '90.1-2019', etc.
        province: nil,            # For NECB fuel selection
        heating_fuel: :auto,      # :auto or specific fuel
        cooling_fuel: :auto,      # :auto or specific fuel
        high_efficiency: false,   # Above-code performance
        special_requirements: []  # [:high_ventilation, :humidity_control, etc.]
      )
        # Returns recommended system configuration
      end
      
      # Get all viable options ranked by suitability
      def self.list_viable_systems(
        building_type:,
        floor_area:,
        num_zones:,
        climate_zone:,
        standard:
      )
        # Returns array of system options with scores
      end
      
      # Explain why a system was recommended
      def self.explain_recommendation(recommendation)
        # Returns human-readable explanation
      end
      
      # Check if a system is appropriate
      def self.validate_system_choice(
        system_type:,
        building_type:,
        floor_area:,
        climate_zone:,
        standard:
      )
        # Returns { valid: true/false, warnings: [], errors: [] }
      end
      
    end
  end
end
```

### Example LLM Usage

```ruby
# LLM provides building parameters from user request
recommendation = OpenstudioStandards::SimpleAPI::SystemSelector.recommend_system(
  building_type: 'Office',
  floor_area: 5000,  # m²
  num_zones: 15,
  climate_zone: 'NECB 6',
  standard: 'NECB2011',
  province: 'ON'
)

# Returns:
{
  system_type: 2,  # NECB System 2
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
    'Climate Zone 6 (Toronto) requires ERV per NECB',
    'Natural gas is standard heating fuel in Ontario'
  ],
  alternatives: [
    { system_type: 4, reason: 'If future expansion planned' },
    { system_type: 5, reason: 'If packaged equipment preferred' }
  ]
}

# LLM can then apply the recommendation
OpenstudioStandards::SimpleAPI::AirLoops.add_necb_system(
  model,
  standard: recommendation[:standard],
  system_type: recommendation[:system_type],
  equipment_speed: recommendation[:equipment_speed],
  heating_fuel: recommendation[:heating_fuel]
)
```

---

## Machine-Readable Decision Rules

### JSON/YAML Format for LLM Tools

```yaml
decision_tree:
  
  necb_systems:
    rules:
      - condition:
          building_type: ['Multi-unit residential', 'Hotel', 'Motel']
        result:
          primary_system: 3
          reason: "Residential buildings use heat pumps for individual zone control"
      
      - condition:
          building_type: any
          floor_area_m2: { max: 600 }
        result:
          primary_system: 1
          reason: "Small buildings (≤600 m²) use System 1"
      
      - condition:
          building_type: ['Office', 'School/university', 'Retail']
          floor_area_m2: { min: 600, max: 14000 }
        result:
          primary_system: 2
          alternative: [4, 5]
          reason: "Medium commercial buildings use VAV systems"
      
      - condition:
          building_type: any
          floor_area_m2: { min: 14000 }
        result:
          primary_system: 4
          alternative: [6]
          reason: "Large buildings (>14,000 m²) use System 4 or 6"
      
      - condition:
          building_type: ['Warehouse', 'Warehouse - refrigerated', 'Manufacturing facility']
        result:
          primary_system: 1
          alternate_approach: 'unit_heaters'
          reason: "Industrial spaces often use unit heaters"
  
  climate_requirements:
    - condition:
        climate_zone: ['NECB 6', 'NECB 7A', 'NECB 7B', 'NECB 8']
      requirements:
        erv_required: true
        reason: "Cold climates require energy recovery ventilation"
    
    - condition:
        climate_zone: ['NECB 7B', 'NECB 8']
      requirements:
        heating_fuel_preference: ['natural_gas', 'fuel_oil', 'propane']
        heating_capacity_safety_factor: 1.2
        reason: "Very cold climates need robust heating"
  
  fuel_selection:
    by_province:
      BC:
        primary: ['electricity', 'natural_gas']
        reason: "BC has low electricity costs, carbon policy favors electric"
      ON:
        primary: ['natural_gas']
        secondary: ['electricity']
        reason: "Ontario primarily uses natural gas for heating"
      QC:
        primary: ['electricity', 'natural_gas']
        reason: "Quebec has low electricity costs from hydro"
      AB:
        primary: ['natural_gas']
        reason: "Alberta has abundant natural gas"
      SK:
        primary: ['natural_gas']
      MB:
        primary: ['natural_gas', 'electricity']
```

---

## Benefits of Decision Tree Approach

### For LLMs:
1. **Clear decision points** - Binary or multiple-choice questions
2. **Traceable logic** - Can explain why a system was chosen
3. **Fallback options** - Alternative systems if primary not suitable
4. **Validation** - Can check if user's choice makes sense
5. **Learning** - Can understand the logic, not just memorize mappings

### For Users:
1. **Guided selection** - Don't need to know all 200 systems
2. **Code compliance** - Automatically considers standard requirements
3. **Explanation** - Understand why a system was recommended
4. **Flexibility** - Can override recommendations with justification

### For Developers:
1. **Maintainable** - Rules in structured format
2. **Testable** - Can validate decision logic
3. **Extensible** - Easy to add new systems or rules
4. **Auditable** - Can trace how decisions were made

---

## Next Steps

1. **Implement SystemSelector module** with decision tree logic
2. **Create machine-readable rules** (YAML/JSON format)
3. **Build explanation system** to document why systems were chosen
4. **Add validation** to warn if unusual combinations selected
5. **Integrate with Simple API** so it uses recommendations automatically
