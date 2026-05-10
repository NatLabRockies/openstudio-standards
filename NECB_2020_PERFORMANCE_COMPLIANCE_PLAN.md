# NECB 2020 Performance Path Compliance Method

## Context

The NECB 2020 Section 8.4 (Performance Path) provides an alternative to prescriptive requirements (Sections 3.2, 4.2, 5.2, 6.2, 7.2) where compliance is demonstrated by comparing a **proposed building's** annual energy consumption against the **building energy target** of the **reference building** (per Article 8.4.1.2).

**Official NECB 2020 Terminology:**
- **Proposed Building**: The actual building design being evaluated (Section 8.4.3)
- **Reference Building**: A hypothetical building with identical geometry but meeting all prescriptive requirements (Section 8.4.4)  
- **Building Energy Target**: The maximum annual energy consumption allowed, calculated from the reference building
- **Compliance**: Achieved when proposed building annual energy ≤ building energy target (reference building energy) Currently, the openstudio-standards library focuses on prescriptive path implementation but lacks a comprehensive method for:

1. Creating both proposed and reference buildings from an input OSM file
2. Generating detailed compliance logs that track which NECB 2020 Section 8.4 articles were applied
3. Validating compliance per Articles 8.4.1.2 (annual energy comparison) and 8.4.1.2 (unmet hours)

This implementation will create a new method that orchestrates the full performance path workflow with article-level logging for transparency and traceability.

## Recommended Approach

### New Method Signature

Create a new method in NECB2020 class:

```ruby
# /lib/openstudio-standards/standards/necb/NECB2020/necb_2020.rb

def model_create_necb_2020_performance_compliance(
  proposed_model:,           # INPUT: User's proposed building OSM model
  epw_file:,                 # INPUT: Weather file path
  sizing_run_dir: Dir.pwd,   # Where to run sizing simulations
  output_dir: Dir.pwd,       # Where to save outputs
  run_simulations: false,    # Whether to run EnergyPlus and validate compliance
  html_report: true          # Whether to generate HTML report
)
```

**Input:**
- `proposed_model`: The **proposed building** as an OpenStudio Model object (already loaded)
  - This is the actual building design being evaluated for compliance
  - Used "as-is" per Section 8.4.3 - the method documents its characteristics but does NOT modify it
  - Must have known occupancy and sufficient component information (per Article 8.4.1.2)

**Returns:** Hash containing:
- `:proposed_model` - The input **proposed building** model (unmodified, for reference)
- `:reference_model` - Generated **reference building** OpenStudio Model (prescriptive requirements applied)
- `:building_energy_target` - The **building energy target** from reference building simulation (GJ or kWh)
- `:compliance_log` - Structured hash with article-by-article application logs
- `:proposed_model_path` - Path to saved proposed building OSM copy
- `:reference_model_path` - Path to saved reference building OSM
- `:html_report_path` - Path to HTML compliance report (if `html_report: true`)
- `:compliance_result` - Hash with simulation results and pass/fail status (if `run_simulations: true`):
  - `:compliant` - Boolean: true if proposed energy ≤ building energy target
  - `:proposed_annual_energy` - Proposed building annual energy (GJ)
  - `:reference_annual_energy` - Reference building annual energy = building energy target (GJ)
  - `:energy_margin` - Difference in GJ and percentage
  - `:unmet_hours_valid` - Boolean: heating/cooling unmet hours within limits per 8.4.1.2.(3-4)

### Implementation Plan

#### Phase 1: Core Infrastructure (New Files)

**1.1. Create compliance logging module**

File: `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/compliance_logger.rb`

```ruby
module OpenstudioStandards
  module NECB2020
    class ComplianceLogger
      # Initialize log structure matching Section 8.4 hierarchy
      
      # Enhanced log format with BEFORE/AFTER tracking for debugging:
      # {
      #   section: '8.4.4',                      # Section number
      #   article: '8.4.4.3.(1)',                # Specific article/sentence
      #   action: 'Applied prescriptive requirement',
      #   component_name: 'South Wall',          # Affected component
      #   component_type: 'ExteriorWall',        # Component type
      #   proposed_value: 0.5,                   # BEFORE (proposed)
      #   reference_value: 0.315,                # AFTER (reference)
      #   change_magnitude: -0.185,              # Difference
      #   change_percent: -37.0,                 # Percent change
      #   code_reference: 'NECB 2020 Table 3.2.1.3',  # Source
      #   units: 'W/(m²·K)',                     # Units
      #   timestamp: <Time>,
      #   passed: true                           # Validation status
      # }
      
      # Methods:
      # - log_envelope_change(article:, component_name:, proposed_value:, reference_value:, ...)
      # - log_hvac_system_selection(article:, thermal_block:, system_type:, rationale:, ...)
      # - log_equipment_efficiency(article:, equipment_name:, proposed_eff:, reference_eff:, ...)
      # - log_no_change_required(article:, component_name:, reason:)
      # - get_logs_by_section(section_number) -> Array
      # - get_logs_by_article(article_number) -> Array
    end
  end
end
```

**1.2. Create proposed building processor**

File: `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/proposed_builder.rb`

Implements Article 8.4.3 (Proposed Building) requirements:
- 8.4.3.1: Dynamic HVAC system calculations
- 8.4.3.2: Operating schedules, internal loads, service water heating loads
- 8.4.3.3: Building envelope components (solar absorptance, SHGC, air leakage)
- 8.4.3.4: Interior lighting
- 8.4.3.7: Throttling ranges
- 8.4.3.8: Part-load performance curves

**1.3. Create reference building generator**

File: `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/reference_builder.rb`

Implements Article 8.4.4 (Reference Building) requirements:
- 8.4.4.1: General parameters (identical geometry, orientation, floor area, thermal blocks)
- 8.4.4.2: Operating schedules (identical to proposed)
- 8.4.4.3: Building envelope (prescriptive requirements from Section 3.2)
- 8.4.4.4: Thermal mass (identical to proposed)
- 8.4.4.5: Interior lighting (prescriptive LPD from Section 4.2)
- 8.4.4.6: Service water heating (prescriptive from Section 6.2)
- 8.4.4.7: HVAC system selection (Table 8.4.4.7-A)
- 8.4.4.8: Heating systems (prescriptive efficiencies from Section 5.2)
- 8.4.4.9: Equipment efficiencies (boilers, chillers, furnaces per Section 5.2)
- 8.4.4.10-13: Cooling systems, towers, economizers, heat pumps
- 8.4.4.14-19: Pumps, radiant systems, fans with prescriptive characteristics

**1.4. Create compliance validator**

File: `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/compliance_validator.rb`

Implements Article 8.4.1.2 and 8.4.2 validation:
- Compare annual energy consumption (proposed ≤ reference)
- Validate unmet heating hours ≤ 100 for both models (8.4.1.2.(3))
- Validate unmet cooling hours difference ≤ +10% (8.4.1.2.(4))
- Log calculation methods used (8.4.2.1)

**1.5. Create HTML report generator**

File: `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/compliance_report.rb`

Generates HTML report with:
- Summary table: Proposed vs Reference comparison
- Section 8.4.3 logs: What was captured from proposed building
- Section 8.4.4 logs: What prescriptive requirements were applied to reference
- Section 8.4.1/8.4.2 logs: Compliance validation results
- Article-by-article pass/fail indicators with color coding

#### Phase 2: Reference Building Generation Logic

**2.1. Leverage existing methods for prescriptive requirements**

Reuse from NECB2020/NECB2011:
- Envelope: `apply_standard_construction_properties()` from `/lib/openstudio-standards/standards/necb/NECB2011/building_envelope.rb`
- Lighting: `apply_standard_lights()` from `/lib/openstudio-standards/standards/necb/NECB2011/lighting.rb`
- HVAC efficiency: `apply_standard_efficiencies()` from `/lib/openstudio-standards/standards/necb/NECB2011/hvac_systems.rb`
- System selection: `get_necb_spacetype_system_selection()` from `/lib/openstudio-standards/standards/necb/NECB2011/autozone.rb`
- Infiltration: `space_apply_infiltration_rate()` from `/lib/openstudio-standards/standards/necb/NECB2020/necb_2020.rb` (75 Pa requirement)

**2.2. Modify existing methods to accept logging callback**

Add optional `logger` parameter to key methods:
- `apply_standard_construction_properties(model:, logger: nil, ...)`
- `apply_standard_lights(model:, logger: nil, ...)`
- `apply_standard_efficiencies(model:, logger: nil, ...)`

When logger is present, methods call `logger.log_article(section, article, action, details)` after applying requirements.

**2.3. Create reference model workflow**

```ruby
def generate_reference_building(proposed_model, logger)
  # Step 1: Deep copy proposed model
  reference_model = BTAP::FileIO.deep_copy(proposed_model)
  
  # Step 2: Keep identical per 8.4.4.1.(4): geometry, orientation, 
  #         thermal blocks, schedules, internal loads
  logger.log_article('8.4.4.1', '8.4.4.1.(4)', 
    'Preserved geometry and thermal blocks from proposed', {...})
  
  # Step 3: Apply prescriptive envelope (Section 3.2)
  apply_standard_construction_properties(
    model: reference_model, 
    logger: logger,
    necb_hdd: true,
    # ... prescriptive values
  )
  
  # Step 4: Apply prescriptive lighting (Section 4.2)
  apply_standard_lights(model: reference_model, logger: logger)
  
  # Step 5: Select HVAC systems per Table 8.4.4.7-A
  select_and_apply_reference_hvac_systems(
    model: reference_model, 
    logger: logger
  )
  
  # Step 6: Apply prescriptive efficiencies (Section 5.2)
  apply_standard_efficiencies(model: reference_model, logger: logger)
  
  # Step 7: Apply prescriptive service water heating (Section 6.2)
  apply_standard_service_water_heating(
    model: reference_model, 
    logger: logger
  )
  
  return reference_model
end
```

#### Phase 3: Proposed Building Processing

**3.1. Extract and document proposed building characteristics**

The proposed building is used "as-is" but characteristics must be logged per Section 8.4.3:

```ruby
def document_proposed_building(proposed_model, logger)
  # Log 8.4.3.2: Operating schedules, internal loads
  log_operating_schedules(proposed_model, logger)
  log_internal_loads(proposed_model, logger)
  
  # Log 8.4.3.3: Envelope components
  log_envelope_properties(proposed_model, logger)
  
  # Log 8.4.3.4: Interior lighting
  log_lighting_properties(proposed_model, logger)
  
  # Log 8.4.3.6: Service water heating
  log_swh_properties(proposed_model, logger)
  
  # Log HVAC system configuration
  log_hvac_configuration(proposed_model, logger)
end
```

**3.2. Validate proposed model meets minimum requirements**

Per Article 8.4.1.1 and 8.4.1.2, proposed model must:
- Have known occupancy
- Have sufficient information about components
- Have thermal blocks defined
- Have heating/cooling systems where applicable

#### Phase 4: HVAC System Selection for Reference Building

**4.1. Implement Table 8.4.4.7-A logic**

File: `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/reference_hvac_selector.rb`

Query the codes MCP server for Table 8.4.4.7-A requirements and map to existing system types:
- System 1: PTAC or room AC (residential/accommodation)
- System 2: Split AC or heat pump (data centers, historical collections, ice rinks)
- System 3: Single-zone rooftop unit (assembly ≤4 stories, general ≤2 stories, hospitals, etc.)
- System 4: MAU + local units (automotive, warehouses, food service with hoods)
- System 5: Refrigeration + MAU (refrigerated warehouses)
- System 6: VAV with reheat (assembly >4 stories, general >2 stories)

**4.2. Map space types to building/space classification**

Leverage existing `necb_hvac_system_selection_type` table in:
`/lib/openstudio-standards/standards/necb/NECB2011/data/necb_hvac_system_selection_type.json`

Update for NECB 2020 if needed.

**4.3. Create systems using existing methods**

Reuse existing HVAC system creation from `/lib/openstudio-standards/standards/necb/NECB2011/hvac_system_*.rb` files:
- `add_system_1_airloop()` for System 1
- `add_system_2_airloop()` for System 2
- `add_system_3_airloop()` for System 3
- `add_system_4_airloop()` for System 4
- `add_system_5_airloop()` for System 5
- `add_system_6_airloop()` for System 6

#### Phase 5: Compliance Validation (Optional - if run_simulations: true)

**5.1. Run EnergyPlus simulations**

```ruby
def run_compliance_simulations(proposed_model, reference_model, 
                                 epw_file, output_dir, logger)
  # Run proposed building simulation
  proposed_sql = run_simulation(proposed_model, epw_file, 
                                 "#{output_dir}/proposed")
  
  # Run reference building simulation  
  reference_sql = run_simulation(reference_model, epw_file,
                                  "#{output_dir}/reference")
  
  # Extract results
  proposed_results = extract_results(proposed_sql)
  reference_results = extract_results(reference_sql)
  
  # Validate per 8.4.1.2
  validate_compliance(proposed_results, reference_results, logger)
end
```

**5.2. Extract and compare annual energy**

Per Article 8.4.1.2.(2):
- Extract total annual energy consumption (kWh or GJ)
- Compare: proposed ≤ reference (building energy target)
- Log result with percentage difference

**5.3. Validate unmet hours**

Per Articles 8.4.1.2.(3) and 8.4.1.2.(4):
- Heating unmet hours ≤ 100 for both models
- Cooling unmet hours difference ≤ +10%
- Log results for each thermal block

#### Phase 6: HTML Report Generation

**6.1. Report structure**

```
NECB 2020 Performance Compliance Report
========================================

Building Information
- Proposed model: [path]
- Reference model: [path]
- Climate zone: [zone] (HDD: [value])
- Weather file: [epw]

Compliance Summary
------------------
[Table with Pass/Fail indicators]
✓ Annual Energy: Proposed XXX GJ ≤ Reference YYY GJ
✓ Heating Unmet Hours: Proposed XX hrs, Reference YY hrs (both ≤ 100)
✓ Cooling Unmet Hours: Difference Z% (≤ 10%)

Section 8.4.3: Proposed Building Characteristics
-------------------------------------------------
[Expandable sections for each article with logged details]

8.4.3.2: Operating Schedules, Internal Loads
  ✓ Applied representative schedules for [space types]
  - People: [details]
  - Lighting: [details]
  - Equipment: [details]

8.4.3.3: Building Envelope Components
  ✓ Solar absorptance: [values by surface]
  ✓ SHGC: [values by window type]
  ✓ Air leakage: [I75Pa value], adjusted to [IAGW value]

Section 8.4.4: Reference Building Requirements
-----------------------------------------------
[Expandable sections for each article with applied values]

8.4.4.3: Building Envelope
  ✓ Applied Section 3.2 prescriptive requirements
  
  [Table showing before/after for debugging]
  Component          | Proposed  | Reference | Change  | Code Reference
  -------------------|-----------|-----------|---------|------------------
  South Ext Wall     | 0.500     | 0.315     | -37.0%  | Table 3.2.1.3
  North Ext Wall     | 0.500     | 0.315     | -37.0%  | Table 3.2.1.3
  Roof               | 0.250     | 0.183     | -26.8%  | Table 3.2.1.3
  Windows (all)      | 2.000     | 1.800     | -10.0%  | Table 3.2.1.3
  
  Climate zone: 5 (HDD 3500)

8.4.4.7: HVAC System Selection
  ✓ Applied Table 8.4.4.7-A system selection
  - Thermal block [name]: System [X] (Building type: [Y], Stories: [Z])
  - Reference: NECB 2020 Article 8.4.4.7, Table 8.4.4.7-A

[Continue for all articles...]
```

**6.2. Use existing QAQC HTML generation as template**

Adapt from: `/lib/openstudio-standards/lib/openstudio-standards/qaqc/reporting.rb`
- ERB templates for section formatting
- Color-coded pass/fail indicators
- Expandable sections for detailed logs

### Critical Files to Create/Modify

**New files (6):**
1. `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/compliance_logger.rb`
2. `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/proposed_builder.rb`
3. `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/reference_builder.rb`
4. `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/reference_hvac_selector.rb`
5. `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/compliance_validator.rb`
6. `/lib/openstudio-standards/standards/necb/NECB2020/performance_compliance/compliance_report.rb`

**Modified files (5):**
1. `/lib/openstudio-standards/standards/necb/NECB2020/necb_2020.rb` - Add main method
2. `/lib/openstudio-standards/standards/necb/NECB2011/building_envelope.rb` - Add logger parameter
3. `/lib/openstudio-standards/standards/necb/NECB2011/lighting.rb` - Add logger parameter
4. `/lib/openstudio-standards/standards/necb/NECB2011/hvac_systems.rb` - Add logger parameter
5. `/lib/openstudio-standards/standards/necb/NECB2011/service_water_heating.rb` - Add logger parameter

**Test files (5):**
1. `/test/necb/unit_tests/tests/test_necb_2020_performance_compliance/test_section_8_4_3_proposed.rb` - Article-level tests for Section 8.4.3
2. `/test/necb/unit_tests/tests/test_necb_2020_performance_compliance/test_section_8_4_4_reference.rb` - Article-level tests for Section 8.4.4 (40+ tests)
3. `/test/necb/unit_tests/tests/test_necb_2020_performance_compliance/test_section_8_4_1_compliance.rb` - Compliance validation tests
4. `/test/necb/unit_tests/tests/test_necb_2020_performance_compliance/test_logging_and_reporting.rb` - Logging infrastructure tests
5. `/test/necb/unit_tests/tests/test_necb_2020_performance_compliance.rb` - Main integration tests

### Existing Code to Reuse

**Thermal blocks:**
- `model_create_thermal_zones()` from autozone.rb
- `apply_auto_zoning()` from autozone.rb

**Climate zone:**
- `get_necb_hdd18()` from necb_2011.rb
- `get_climate_zone_name()` from necb_2011.rb

**Model manipulation:**
- `BTAP::FileIO.deep_copy()` for cloning models
- `BTAP::FileIO.load_osm()` for loading
- `BTAP::FileIO.save_osm()` for saving

**Prescriptive requirements:**
- `apply_standard_construction_properties()` for envelope
- `apply_standard_lights()` for lighting
- `apply_standard_efficiencies()` for HVAC equipment
- `get_necb_spacetype_system_selection()` for system selection
- `create_necb_system()` for HVAC system creation

**QAQC patterns:**
- `OpenstudioStandards::QAQC.create_qaqc_html()` for HTML generation
- `necb_section_test()` pattern for validation logging

### Data Sources

**NECB 2020 Section 8.4 articles (via codes MCP server):**
- Query actual code text: `mcp__codes__get_section(code: 'necb', edition: '2020', section_number: '8.4.X.Y')`
- Get tables: `mcp__codes__get_table(code: 'necb', edition: '2020', table_number: '8.4.4.7.-A')`

**Standards data (JSON files):**
- `/lib/openstudio-standards/standards/necb/NECB2020/data/` - NECB 2020 specific data
- `/lib/openstudio-standards/standards/necb/NECB2011/data/` - Inherited tables

### Testing Strategy

#### Article-Level Unit Tests

Create comprehensive test suite with one test per article/sentence to ensure correctness and enable debugging.

**Test file structure:**
```
/test/necb/unit_tests/tests/test_necb_2020_performance_compliance/
  test_section_8_4_3_proposed.rb      # Section 8.4.3 tests
  test_section_8_4_4_reference.rb     # Section 8.4.4 tests
  test_section_8_4_1_compliance.rb    # Section 8.4.1 & 8.4.2 tests
  test_logging_and_reporting.rb       # Logging infrastructure tests
```

**Example: Article 8.4.4.4 - Thermal Mass**

Section 8.4.4.4 states: "The energy model calculations shall account for the effect of thermal mass."

```ruby
# test_section_8_4_4_reference.rb

def test_8_4_4_4_thermal_mass_identical_to_proposed
  # Article 8.4.4.4.(1) - implicit from 8.4.4.1.(4)(a): 
  # "total floor area of conditioned and unconditioned spaces" must be identical
  
  # Setup: Create proposed model with specific thermal mass properties
  proposed = create_test_model_with_thermal_mass(
    wall_material: 'Concrete',
    wall_thickness_m: 0.2,
    roof_material: 'Concrete',  
    roof_thickness_m: 0.15
  )
  
  # Run compliance method
  result = @necb2020.model_create_necb_2020_performance_compliance(
    proposed_model: proposed,
    epw_file: @test_epw
  )
  
  reference = result[:reference_model]
  log = result[:compliance_log]
  
  # Verify thermal mass materials are identical
  proposed_walls = get_wall_constructions(proposed)
  reference_walls = get_wall_constructions(reference)
  
  assert_equal(proposed_walls.length, reference_walls.length, 
    "8.4.4.4: Reference must have same number of wall types as proposed")
  
  proposed_walls.each_with_index do |prop_wall, idx|
    ref_wall = reference_walls[idx]
    
    # Check material thermal mass properties
    assert_equal(prop_wall.layers.length, ref_wall.layers.length,
      "8.4.4.4: Wall layer count must match")
    
    prop_wall.layers.each_with_index do |prop_layer, layer_idx|
      ref_layer = ref_wall.layers[layer_idx]
      
      assert_in_delta(prop_layer.thickness, ref_layer.thickness, 0.001,
        "8.4.4.4: Layer thickness must be identical (proposed vs reference)")
      
      assert_in_delta(prop_layer.material.density, ref_layer.material.density, 0.1,
        "8.4.4.4: Material density (thermal mass) must be identical")
        
      assert_in_delta(prop_layer.material.specificHeat, ref_layer.material.specificHeat, 1.0,
        "8.4.4.4: Material specific heat (thermal mass) must be identical")
    end
  end
  
  # Verify logging captured this
  thermal_mass_logs = log[:section_8_4_4].select { |entry| entry[:article] == '8.4.4.4' }
  assert(!thermal_mass_logs.empty?, "8.4.4.4: Must log thermal mass preservation")
  
  # Check log details
  assert(thermal_mass_logs.first[:details].key?(:constructions_preserved),
    "8.4.4.4: Log must detail which constructions were preserved")
  
  assert(thermal_mass_logs.first[:details][:constructions_preserved].include?('Concrete Wall'),
    "8.4.4.4: Log must list concrete wall as preserved")
end
```

**Example: Article 8.4.4.3 - Building Envelope**

Section 8.4.4.3.(1): "The thermal transmittance and solar transmittance of the components of the reference building's envelope shall comply with Section 3.2."

```ruby
def test_8_4_4_3_envelope_prescriptive_values
  # Setup: Create proposed model with non-compliant envelope
  proposed = create_test_model(
    building_type: 'Office',
    wall_u_value: 0.5,  # Worse than prescriptive
    window_u_value: 2.0  # Worse than prescriptive
  )
  
  # Add climate zone
  epw_file = get_test_epw_for_climate_zone('5')  # HDD 3500
  
  # Run compliance
  result = @necb2020.model_create_necb_2020_performance_compliance(
    proposed_model: proposed,
    epw_file: epw_file
  )
  
  reference = result[:reference_model]
  log = result[:compliance_log]
  climate_zone = result[:climate_zone]
  
  # Get prescriptive U-values from NECB 2020 Table 3.2.1.3 for climate zone 5
  expected_wall_u = get_prescriptive_u_value('wall', 'opaque', climate_zone)
  expected_window_u = get_prescriptive_u_value('window', 'fenestration', climate_zone)
  
  # Verify reference envelope matches prescriptive
  reference_walls = get_exterior_walls(reference)
  reference_walls.each do |wall|
    actual_u = wall.construction.get.uFactor.get
    assert_in_delta(expected_wall_u, actual_u, 0.01,
      "8.4.4.3.(1): Reference wall U-value must match Section 3.2 prescriptive (climate zone #{climate_zone})")
  end
  
  reference_windows = get_exterior_windows(reference)
  reference_windows.each do |window|
    actual_u = window.construction.get.uFactor.get
    assert_in_delta(expected_window_u, actual_u, 0.05,
      "8.4.4.3.(1): Reference window U-value must match Section 3.2 prescriptive")
  end
  
  # Verify logging shows BEFORE and AFTER values
  envelope_logs = log[:section_8_4_4].select { |entry| entry[:article] == '8.4.4.3.(1)' }
  assert(!envelope_logs.empty?, "8.4.4.3: Must log envelope changes")
  
  # Check log contains change tracking
  wall_log = envelope_logs.find { |e| e[:component_type] == 'ExteriorWall' }
  assert_not_nil(wall_log, "8.4.4.3: Must log wall modifications")
  
  assert_equal(0.5, wall_log[:proposed_u_value],
    "8.4.4.3: Log must capture proposed U-value BEFORE change")
  
  assert_equal(expected_wall_u, wall_log[:reference_u_value],
    "8.4.4.3: Log must capture reference U-value AFTER change")
    
  assert_equal('NECB 2020 Table 3.2.1.3', wall_log[:code_reference],
    "8.4.4.3: Log must cite specific code table/article")
end
```

#### Enhanced Logging Format

Update ComplianceLogger to track **before/after changes** for debugging:

```ruby
# compliance_logger.rb

def log_envelope_change(article:, component_name:, component_type:, 
                        proposed_value:, reference_value:, 
                        code_reference:, units:)
  entry = {
    section: article.split('.')[0..2].join('.'),  # e.g., '8.4.4'
    article: article,                              # e.g., '8.4.4.3.(1)'
    action: 'Applied prescriptive requirement',
    component_name: component_name,                # e.g., 'South Wall'
    component_type: component_type,                # e.g., 'ExteriorWall'
    proposed_value: proposed_value,                # BEFORE: 0.5
    reference_value: reference_value,              # AFTER: 0.315
    change_magnitude: reference_value - proposed_value,
    change_percent: ((reference_value - proposed_value) / proposed_value * 100).round(1),
    code_reference: code_reference,                # 'NECB 2020 Table 3.2.1.3'
    units: units,                                   # 'W/(m²·K)'
    timestamp: Time.now,
    passed: true  # or false if validation failed
  }
  
  @logs[:section_8_4_4] << entry
end

def log_no_change_required(article:, component_name:, reason:)
  entry = {
    section: article.split('.')[0..2].join('.'),
    article: article,
    action: 'No change required',
    component_name: component_name,
    reason: reason,  # e.g., "Proposed already meets prescriptive requirements"
    timestamp: Time.now,
    passed: true
  }
  
  @logs[:section_8_4_4] << entry
end
```

#### Test Coverage Matrix

Create comprehensive test coverage for every sentence in Section 8.4:

**Section 8.4.3 (Proposed Building) - 9 articles with tests:**
- [ ] 8.4.3.1 - HVAC system dynamic calculations
- [ ] 8.4.3.2.(1) - Operating schedules
- [ ] 8.4.3.2.(2) - Internal loads (people, equipment)
- [ ] 8.4.3.2.(3) - Set-point temperatures
- [ ] 8.4.3.3.(1) - Solar absorptance (default 0.7 if unknown)
- [ ] 8.4.3.3.(2) - SHGC adjustment factor (0.8 if no shading calculation)
- [ ] 8.4.3.3.(3) - Air leakage (75 Pa normalized)
- [ ] 8.4.3.4 - Interior lighting (dwelling units 5 W/m², controls)
- [ ] 8.4.3.7 - Throttling ranges (default ±1°C)
- [ ] 8.4.3.8 - Part-load performance curves

**Section 8.4.4 (Reference Building) - 40+ articles with tests:**
- [ ] 8.4.4.1.(4) - Identical: floor area, use, thermal blocks, shape, orientation
- [ ] 8.4.4.1.(5) - Heating/cooling presence identical
- [ ] 8.4.4.2.(1) - Operating schedules identical
- [ ] 8.4.4.2.(2) - Internal loads identical
- [ ] 8.4.4.2.(3) - Set-point temperatures identical
- [ ] 8.4.4.3.(1) - Envelope meets Section 3.2 prescriptive
- [ ] 8.4.4.4.(1) - Thermal mass identical (implicit)
- [ ] 8.4.4.5.(1) - Interior lighting meets Section 4.2 prescriptive
- [ ] 8.4.4.6.(1) - Service water heating meets Section 6.2
- [ ] 8.4.4.7.(1) - HVAC system selection per Table 8.4.4.7-A
- [ ] 8.4.4.8.(1-5) - Heating system characteristics (fuel type, capacity, controls)
- [ ] 8.4.4.9.(1-2) - Equipment efficiencies per Section 5.2
- [ ] 8.4.4.10.(1-9) - Cooling system characteristics
- [ ] 8.4.4.11.(1-3) - Cooling tower systems
- [ ] 8.4.4.12.(1) - Economizers per Table 8.4.4.12
- [ ] 8.4.4.13.(1-2) - Heat pump systems
- [ ] 8.4.4.14.(1-3) - Hydronic pumps (flow, power)
- [ ] 8.4.4.16.(1-2) - Radiant heating/cooling adjustments
- [ ] 8.4.4.17.(1-4) - Fans (exhaust, part-load curves)
- [ ] 8.4.4.18.(1-6) - Supply/return fan characteristics
- [ ] 8.4.4.19.(1-8) - Default fan parameters for Systems 3 and 6

**Section 8.4.1 & 8.4.2 (Compliance Validation) - 15+ tests:**
- [ ] 8.4.1.2.(2) - Annual energy: proposed ≤ reference
- [ ] 8.4.1.2.(3) - Heating unmet hours ≤ 100 for both
- [ ] 8.4.1.2.(4) - Cooling unmet hours difference ≤ +10%
- [ ] 8.4.2.9 - Air leakage calculation (75 Pa → 5 Pa conversion)

#### Integration Tests

**Full workflow test:**
```ruby
def test_full_workflow_medium_office_climate_zone_5
  # Load prototype
  proposed = load_prototype('MediumOffice')
  
  # Run compliance
  result = @necb2020.model_create_necb_2020_performance_compliance(
    proposed_model: proposed,
    epw_file: get_climate_zone_epw('5'),
    run_simulations: true,
    html_report: true
  )
  
  # Verify all components
  assert(result[:compliant], "Compliance check failed")
  assert(File.exist?(result[:html_report_path]), "HTML report not generated")
  assert(result[:compliance_log][:section_8_4_3].length > 5, "Insufficient proposed logging")
  assert(result[:compliance_log][:section_8_4_4].length > 20, "Insufficient reference logging")
  
  # Verify each major subsection was logged
  assert_logged_article(result[:compliance_log], '8.4.4.3', 'Envelope')
  assert_logged_article(result[:compliance_log], '8.4.4.5', 'Lighting')
  assert_logged_article(result[:compliance_log], '8.4.4.7', 'HVAC System Selection')
  assert_logged_article(result[:compliance_log], '8.4.4.9', 'Equipment Efficiencies')
end
```

#### Verification Steps

**Automated verification (CI/CD):**
1. Run all article-level unit tests
2. Verify 100% of articles in Section 8.4.3, 8.4.4 have corresponding tests
3. Check logging coverage - every test must verify log entry exists
4. Generate code coverage report (target: >90% for new files)

**Manual verification:**
1. Review HTML report for sample buildings
2. Spot-check prescriptive values against code tables
3. Verify before/after logging makes sense for debugging
4. Test with edge case models (no HVAC, custom schedules, etc.)

### Implementation Order

1. **Compliance logger** (foundation for all logging)
2. **Reference builder core** (model cloning, basic setup)
3. **HVAC system selector** (Table 8.4.4.7-A logic)
4. **Reference builder complete** (prescriptive requirements)
5. **Proposed builder** (characteristic documentation)
6. **Compliance validator** (simulation and comparison - optional)
7. **HTML report generator** (presentation layer)
8. **Main method** (orchestration)
9. **Tests** (verification)

### Edge Cases to Handle

- Missing thermal blocks in proposed model → Create using autozone
- Unknown space types → Log warning, use default system selection
- Weather file without HDD → Extract from .stat file
- Proposed model with no HVAC → Reference gets default systems per Table 8.4.4.7-A
- Multiple building types in one model → Select systems per thermal block
- Custom schedules not in standards → Keep as-is, log as non-standard

### Future Enhancements (Out of Scope)

- Automated ECM analysis (test multiple reference configurations)
- Cost-benefit analysis integration
- Multi-year climate scenario testing
- Batch processing of multiple buildings
- Web API for cloud-based compliance checking