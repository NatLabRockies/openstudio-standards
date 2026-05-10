# Simple API Design Summary

## Overview

The Simple API is a **three-tiered facade** over openstudio-standards that makes building modeling accessible to LLMs while preserving full access to the underlying complexity.

## Key Design Principles

### 1. Layered Access (Progressive Disclosure)

```
┌─────────────────────────────────────────────┐
│  Layer 1: Decision Tree (LLM-Friendly)      │  ← Recommended for most users
│  - SystemSelector.recommend_system()        │
│  - Auto-selects based on building params    │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  Layer 2: Simple API (Mid-Level)            │  ← Common systems, sensible defaults
│  - add_necb_system()                        │
│  - add_vav_with_reheat()                    │
│  - add_packaged_rooftop_vav()               │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│  Layer 3: Full Access (Advanced)            │  ← Power users, special cases
│  - add_cbecs_system() (136 combinations)    │
│  - add_any_system() (43 base types)         │
│  - Direct Standard API (unlimited control)  │
└─────────────────────────────────────────────┘
```

### 2. Domain-Based Organization

**10 primary domains:**
- Geometry, Envelope, Loads, Schedules
- ZoneHVAC, AirLoops, Plant, DHW
- Controls, ExteriorLoads

**Plus 4 utility domains:**
- SystemSelector (decision tree)
- Simulation, Validation, Weather, Reporting

### 3. Decision Tree Integration

**SystemSelector module provides:**
- `recommend_system()` - Get optimal system recommendation
- `list_viable_systems()` - See all options ranked by suitability  
- `validate_system_choice()` - Check if user's choice makes sense
- `explain_recommendation()` - Understand why systems were recommended

**Decision tree considers:**
- Building type and floor area
- Number of thermal zones
- Climate zone and province
- Code/standard requirements (NECB, ASHRAE 90.1)
- Fuel availability
- Special requirements (ventilation, humidity control, etc.)

## Example: How an LLM Would Use It

### User Request
> "Create a 3-story office building in Vancouver with efficient HVAC"

### LLM Process

**Step 1: Extract parameters**
```ruby
{
  building_type: 'Office',
  floor_area: 4500.0,      # estimated from 3 stories
  num_zones: 15,           # estimated
  location: 'Vancouver',
  province: 'BC',
  climate_zone: 'NECB 5',  # Vancouver is Zone 5
  high_efficiency: true    # user said "efficient"
}
```

**Step 2: Get system recommendation**
```ruby
rec = SystemSelector.recommend_system(
  building_type: 'Office',
  floor_area: 4500.0,
  num_zones: 15,
  climate_zone: 'NECB 5',
  standard: 'NECB2011',
  province: 'BC',
  high_efficiency: true
)

# Returns:
{
  system_type: 2,
  system_name: 'Multi-zone VAV with electric reheat',
  equipment_speed: :multi_speed,  # because high_efficiency: true
  heating_fuel: 'electricity',    # BC preference
  erv_required: true,             # NECB Zone 5
  confidence: 0.92,
  rationale: [
    'Building area 4500 m² is in range for System 2',
    'Multi-speed equipment for above-code efficiency',
    'Electric heating aligns with BC carbon policy',
    'ERV required for Climate Zone 5'
  ]
}
```

**Step 3: Build model**
```ruby
# Geometry
Geometry.create_rectangular_building(
  model,
  length: 60.0, width: 25.0,
  num_floors: 3,
  building_type: 'Office'
)

# Weather
Weather.get_weather_file_from_location(
  model,
  city: 'Vancouver',
  province: 'BC'
)

# Envelope
Envelope.apply_standard_constructions(
  model,
  standard: 'NECB2011',
  climate_zone: 'NECB 5'
)

# Loads
Loads.apply_space_type_loads(model, standard: 'NECB2011')

# HVAC - using recommendation
AirLoops.add_necb_system(
  model,
  standard: 'NECB2011',
  zones: :all,
  system_type: rec[:system_type],
  equipment_speed: rec[:equipment_speed]
)

# DHW
DHW.add_service_water_heating(
  model,
  standard: 'NECB2011',
  fuel: 'electricity'  # matches BC preference
)

# Controls
Controls.add_thermostats(model, standard: 'NECB2011')
Controls.add_daylighting_controls(model, standard: 'NECB2011')
```

**Step 4: Respond to user**
> "I've created a 3-story office building (4,500 m², 15 zones) in Vancouver with NECB System 2 (VAV with electric reheat and energy recovery). This system:
> - Uses multi-speed equipment for higher efficiency (>code)
> - Uses electric heating (aligned with BC's low carbon electricity)
> - Includes an energy recovery ventilator (required by NECB for Zone 5)
> - Meets NECB 2011 requirements for medium commercial offices"

## Benefits

### For LLMs:
1. **Clear decision path** - Decision tree provides structured logic
2. **Validation built-in** - Can check if choices make sense before building
3. **Explanation available** - Can tell users WHY systems were chosen
4. **Graceful degradation** - If recommendation fails, can fall back to mid-level API
5. **Traceable** - Each decision documented with rationale

### For Users:
1. **Don't need HVAC expertise** - Decision tree guides selection
2. **Code compliance** - Automatically follows NECB/ASHRAE 90.1 rules
3. **Explainable** - Can see reasoning behind recommendations
4. **Flexible** - Can override recommendations with validation warnings
5. **Progressive learning** - Can start simple, learn advanced features over time

### For Developers:
1. **Maintainable** - Decision logic in structured format (YAML/JSON)
2. **Testable** - Can validate decision tree logic
3. **Extensible** - Easy to add new systems or rules
4. **Backward compatible** - Existing code still works, Simple API is additive
5. **Documented** - Each method has clear purpose and examples

## Implementation Priority

### Phase 1: Core Infrastructure
1. **SystemSelector module** with decision tree
2. **Geometry module** (5 methods)
3. **AirLoops module** with NECB systems (6 methods)
4. **Validation framework** (return value structure, error handling)

### Phase 2: Complete Building Model
5. **Envelope module** (5 methods)
6. **Loads module** (5 methods)
7. **DHW module** (3 methods)
8. **Controls module** (5 methods)
9. **Weather module** (3 methods)

### Phase 3: Advanced Features
10. **Plant module** (6 methods)
11. **ZoneHVAC module** (5 methods)
12. **Schedules module** (3 methods)
13. **ExteriorLoads module** (1 method)

### Phase 4: Analysis & Reporting
14. **Simulation module** (3 methods)
15. **Validation module** (4 methods including NECB QAQC)
16. **Reporting module** (2 methods)

## File Structure

```
lib/openstudio-standards/
├── simple_api/
│   ├── simple_api.rb              # Main entry point
│   ├── system_selector.rb         # Decision tree engine
│   ├── decision_rules.yaml        # Machine-readable rules
│   ├── geometry.rb                # Geometry methods
│   ├── envelope.rb                # Envelope methods
│   ├── loads.rb                   # Loads methods
│   ├── schedules.rb               # Schedules methods
│   ├── zone_hvac.rb               # Zone equipment methods
│   ├── air_loops.rb               # Air systems methods
│   ├── plant.rb                   # Plant equipment methods
│   ├── dhw.rb                     # DHW methods
│   ├── controls.rb                # Controls methods
│   ├── exterior_loads.rb          # Exterior loads methods
│   ├── simulation.rb              # Simulation methods
│   ├── validation.rb              # Validation methods
│   ├── weather.rb                 # Weather methods
│   └── reporting.rb               # Reporting methods
└── [existing structure unchanged]
```

## Testing Strategy

### Unit Tests
- Each Simple API method has unit test
- Decision tree logic validated against known cases
- Validation methods catch inappropriate combinations

### Integration Tests
- Complete building models (simple → complex)
- NECB system selection scenarios
- Climate-specific requirements
- Fuel availability logic

### Regression Tests
- Simple API doesn't break existing functionality
- All existing tests still pass
- Performance benchmarks maintained

## Documentation Strategy

### For LLMs (Machine-Readable)
- Decision tree in YAML/JSON format
- Structured API documentation
- Clear return value schemas
- Example prompts and expected tool calls

### For Humans
- Simple API design document (this file + detailed docs)
- Decision tree documentation
- Example workflows for common scenarios
- Migration guide from current API

### Generated Docs
- YARD documentation for all methods
- Interactive examples
- Decision tree visualizations

## Success Metrics

### Adoption
- **Target**: 80% of new models use Simple API
- Measure: Track method calls in logs/telemetry

### Accuracy  
- **Target**: 95% of SystemSelector recommendations are appropriate
- Measure: Validation pass rate, user override frequency

### Simplicity
- **Target**: 50% reduction in parameters for common cases
- Measure: Average parameters per method call

### Completeness
- **Target**: 90% of use cases covered by Simple API
- Measure: Fallback to advanced API frequency

## Next Steps

1. **Review this design** - Get feedback on approach
2. **Prototype SystemSelector** - Validate decision tree logic
3. **Implement Phase 1** - Core infrastructure + one complete example
4. **User testing** - Validate with LLM interactions
5. **Iterate and expand** - Add remaining modules based on usage

## Open Questions

1. **Decision tree format**: YAML, JSON, or Ruby DSL?
2. **Override mechanism**: How should users override recommendations?
3. **Province defaults**: Should we auto-detect fuel preferences by province?
4. **Vintage buildings**: Should BTAP vintage standards be first-class in Simple API?
5. **ECM framework**: Should energy conservation measures be integrated into decision tree?
6. **Multi-system buildings**: How to handle buildings with multiple HVAC systems?
7. **QAQC integration**: Should validation run automatically or on-demand?
8. **Performance**: Are there caching opportunities for repeated recommendations?
9. **Logging**: What level of detail should be logged for troubleshooting?
10. **Versioning**: How do we version Simple API separately from underlying implementation?
