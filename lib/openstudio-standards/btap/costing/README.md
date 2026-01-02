# BTAP Costing Framework

## Overview

The BTAP Costing Framework is one of the most comprehensive building lifecycle cost analysis systems available, providing detailed economic analysis for all building systems with Canadian-specific regional cost variations. This framework enables complete building cost estimation from conceptual design through detailed analysis, with integration for energy conservation measure (ECM) cost-benefit analysis.

## Architecture Overview

### Core Components

1. **Main Costing Engine** (`btap_costing.rb`) - Central cost calculation and regional interpolation
2. **Database System** (`costing_database_wrapper.rb`) - Cost data management and validation  
3. **Component Costing Modules** (9 specialized modules) - Building system-specific cost calculations
4. **Cost Database** (`common_resources/`) - Comprehensive Canadian cost data
5. **Testing Framework** - Automated validation and regression testing
6. **Workflow Integration** - OpenStudio measure and NECB standards integration

### Data Flow Architecture

```
Building Model → Component Analysis → Regional Cost Factors → Database Lookup → Cost Calculation → Results Aggregation
```

## Main Costing Engine

### `btap_costing.rb` - Core System

#### BTAPCosting Class
**Primary costing engine with regional cost factor integration**

**Key Features:**
- **Regional Cost Interpolation**: Distance-based cost interpolation between Canadian cities
- **Database Generation**: Automated cost database creation for all Canadian locations  
- **Cost Auditing**: Comprehensive cost validation and verification
- **Mechanical Integration**: Integration with mechanical system sizing data

**Core Methods:**

##### Regional Cost Analysis
```ruby
# Get cost factors for specific location
get_regional_cost_factors(location)

# Find closest cost database location  
get_closest_cost_location(lat, lon)

# Distance-based interpolation between locations
interpolate(target_location, reference_locations, values)
```

##### Database Management
```ruby
# Load complete cost database
load_database()

# Validate all cost data for consistency
validate_database()

# Generate regional cost databases
generate_construction_cost_database_for_all_cities()
```

##### Cost Calculation
```ruby
# Add individual cost items to building total
add_costed_item(category, description, quantity, unit_cost, total_cost)

# Process list of cost items
cost_list_items(cost_item_array)
```

#### SimpleLinearRegression Class
**Mathematical utility for cost interpolation calculations**

**Purpose**: Provides statistical interpolation for regional cost variations
**Usage**: Used internally by BTAPCosting for distance-based cost adjustments

## Component Costing Modules

### Building Systems Costing

#### 1. Envelope Costing (`envelope_costing.rb`)
**Building envelope component cost analysis**

**Components Covered:**
- **Exterior Walls**: All construction types and insulation levels
- **Roofs**: Flat and sloped roofs with various membrane and insulation systems  
- **Foundations**: Basement walls, slab-on-grade, crawl spaces
- **Windows and Doors**: Various performance levels and frame types
- **Air Sealing**: Building envelope airtightness measures

**Integration Points:**
- Construction assembly performance requirements
- Regional material and labor cost variations
- Energy code compliance cost implications

#### 2. HVAC System Costing (`heating_cooling_costing.rb`)  
**Complete HVAC equipment and system costing**

**Equipment Categories:**
- **Heating Equipment**: Boilers, furnaces, heat pumps, electric heating
- **Cooling Equipment**: Chillers, rooftop units, split systems, evaporative cooling
- **Distribution Systems**: Ductwork, piping, pumps, fans
- **Controls**: Thermostats, building automation, advanced controls
- **Specialized Systems**: Radiant systems, displacement ventilation

**Costing Methodology:**
- Equipment capacity-based costing with performance tier adjustments
- Installation complexity factors for different building types
- Regional labor rate variations
- Commissioning and testing cost inclusions

#### 3. Lighting System Costing (`lighting_costing.rb` & `led_lighting_costing.rb`)

##### Traditional Lighting (`lighting_costing.rb`)
- **Fixture Costs**: All standard commercial fixture types
- **Control Systems**: Occupancy sensors, daylight dimming, time controls
- **Installation**: Electrical connections, mounting, commissioning

##### LED Lighting Upgrades (`led_lighting_costing.rb`)  
- **LED Conversion Costs**: Retrofit and new installation LED systems
- **Payback Analysis**: Energy savings vs. capital cost analysis
- **Control Integration**: Advanced LED controls and dimming systems
- **Maintenance Savings**: LED lifecycle cost advantages

#### 4. Ventilation System Costing (`ventilation_costing.rb`)
**Air handling and ventilation system economics**

**System Components:**
- **Air Handling Units**: Various sizes and efficiency levels
- **Ductwork Systems**: Supply, return, and exhaust ductwork
- **Filtration**: Standard and high-efficiency filtration systems
- **Ventilation Controls**: CO2 sensors, variable speed drives

#### 5. Service Hot Water Costing (`shw_costing.rb`) 
**Complete service water heating system analysis**

**System Elements:**
- **Water Heaters**: Gas, electric, heat pump, solar thermal systems
- **Distribution Systems**: Piping, insulation, circulation pumps
- **Controls**: Temperature controls, circulation controls, timer systems
- **Efficiency Measures**: Heat recovery, high-efficiency equipment

#### 6. Advanced System Costing

##### Demand Controlled Ventilation (`dcv_costing.rb`)
- **CO2 Sensors**: Cost and installation of occupancy-based ventilation controls
- **Control Systems**: Integration with building automation systems  
- **Energy Savings**: Ventilation energy reduction economic analysis

##### Daylighting Controls (`daylighting_sensor_control_costing.rb`)
- **Daylight Sensors**: Various sensor types and placement strategies
- **Dimming Controls**: Continuous and stepped dimming systems
- **Integration Costs**: Connection to lighting control systems

##### Natural Ventilation (`nv_costing.rb`)
- **Operable Windows**: Automated and manual window systems
- **Control Systems**: Temperature and wind sensors, automated controls
- **Mixed-Mode Integration**: Natural and mechanical ventilation integration

##### Ground-Mounted PV (`pv_ground_costing.rb`)
- **Solar Panels**: Various efficiency levels and mounting systems
- **Electrical Systems**: Inverters, electrical connections, grid integration
- **Installation**: Site preparation, mounting structures, commissioning

## Cost Database System

### Database Wrapper (`costing_database_wrapper.rb`)

#### CostingDatabase Class  
**Central database management and validation system**

**Key Functionality:**
- **Database Loading**: Load cost data from CSV resources
- **Data Validation**: Comprehensive validation of all cost data
- **Database Access**: Thread-safe access to cost information
- **Schema Enforcement**: Ensure data structure consistency

**Critical Methods:**
```ruby
# Load database from CSV resources
load_database_from_resources()

# Validate complete database for consistency
validate_database()

# Validate construction set definitions
validate_constructions_sets()

# Validate HVAC equipment data
validate_ahu_items_and_quantities()
```

### Cost Database Structure (`common_resources/`)

#### Core Cost Data
- **`costs.csv`**: Base construction and equipment costs
- **`costs_local_factors.csv`**: Regional cost adjustment factors for all Canadian provinces/territories
- **`locations.csv`**: Geographic coordinates and regional data for cost interpolation

#### Material Databases
- **`materials_opaque.csv`**: Insulation, structural, and finish materials
- **`materials_glazing.csv`**: Windows, glazing, and frame materials
- **`materials_lighting.csv`**: Lighting fixtures, lamps, and control equipment
- **`materials_hvac.csv`**: HVAC equipment, components, and installation materials

#### Construction and Assembly Data  
- **`constructions_opaque.csv`**: Wall, roof, floor, and foundation assemblies
- **`constructions_glazing.csv`**: Window and door assembly definitions
- **`construction_sets.csv`**: Complete building envelope construction sets
- **`ConstructionProperties.csv`**: Thermal and physical properties with cost data
- **`Constructions.csv`**: Detailed construction assembly specifications

#### Equipment and System Data
- **`hvac_vent_ahu.csv`**: Air handling unit specifications, capacities, and costs
- **`lighting_sets.csv`**: Complete lighting system packages
- **`lighting.csv`**: Individual lighting fixture and component costs

## Regional Cost System

### Canadian Regional Integration

#### Provincial Cost Factors
**All Canadian provinces and territories included:**
- British Columbia, Alberta, Saskatchewan, Manitoba
- Ontario, Quebec, New Brunswick, Nova Scotia, Prince Edward Island  
- Newfoundland and Labrador, Northwest Territories, Nunavut, Yukon

#### Cost Interpolation Methodology
1. **Distance Calculation**: Great circle distance between project location and reference cities
2. **Weight Calculation**: Inverse distance weighting for cost factor interpolation  
3. **Factor Application**: Apply interpolated factors to base costs
4. **Validation**: Ensure interpolated costs fall within reasonable ranges

#### Regional Variations Captured
- **Labor Costs**: Regional labor rate differences
- **Material Costs**: Transportation and availability impacts
- **Market Conditions**: Regional construction market factors
- **Climate Adjustments**: Cold weather construction impacts

## Testing and Validation Framework

### Automated Testing System

#### Test Execution (`test_run_costing_tests.rb`)
**Main test runner for comprehensive costing validation**

**Testing Categories:**
- **Component Costing Tests**: Validate each building system costing module
- **Database Tests**: Ensure cost database integrity and completeness
- **Regional Factor Tests**: Validate cost interpolation across all Canadian locations  
- **Integration Tests**: Test costing integration with building models

#### Parallel Testing (`parallel_tests.rb`)
**Large-scale test execution for comprehensive validation**

**Capabilities:**
- **Multi-Core Testing**: Parallel test execution for faster validation
- **Regression Testing**: Compare results against established baselines
- **Performance Testing**: Validate costing calculation performance
- **Coverage Analysis**: Ensure comprehensive test coverage

#### Test Management
- **`copy_test_results_files_to_expected_results.rb`**: Test result management and baseline updates
- **`test_run_all_test_locally.rb`**: Local development testing framework

### Reference Data Validation

#### NECB Reference Buildings (`necb_reference_runs.csv`)
**Comprehensive cost validation using Canadian reference buildings**

**Validation Coverage:**
- All major Canadian building types
- Multiple climate zones
- Various building sizes and complexities
- Integration with NECB energy standards

#### Mechanical System Validation (`mech_sizing.json`)
**HVAC system sizing and costing validation data**

**Content:**
- Equipment capacity ranges and costs
- Installation complexity factors
- Regional installation cost variations
- Performance verification data

#### Utility Cost Integration (`neb_end_use_prices.csv`)
**Canadian utility rate integration for lifecycle cost analysis**

**Data Sources:**
- National Energy Board utility rate data
- Provincial utility rate structures
- Time-of-use pricing where applicable
- Regional rate variations

## Workflow Integration

### OpenStudio Measure Integration (`btap_measure_helper.rb`)

#### BTAPMeasureHelper Class
**Integration with OpenStudio measure framework**

**Key Features:**
- **Argument Validation**: Validate measure arguments for costing calculations
- **Hash Conversion**: Convert measure arguments to costing parameters
- **Type Validation**: Ensure argument types match costing requirements

#### BTAPMeasureTestHelper Class  
**Testing framework for measure integration**

**Testing Capabilities:**
- **Argument Range Testing**: Validate argument ranges and defaults
- **Model Creation**: Create NECB prototype models for testing
- **Measure Execution**: Run measures with costing integration
- **Result Validation**: Validate costing results from measure execution

### BTAP Workflow Integration (`btap_workflow.rb`)
**Integration with larger BTAP analysis workflows**

**Workflow Steps:**
1. **Model Analysis**: Extract building characteristics for costing
2. **Component Identification**: Identify all building systems and components
3. **Regional Analysis**: Determine appropriate regional cost factors
4. **Cost Calculation**: Calculate costs for all building systems
5. **Results Integration**: Integrate costs with energy and performance analysis

### File-Based Costing (`cost_building_from_file.rb`)
**Automated costing from building definition files**

**Capabilities:**
- **Batch Processing**: Cost multiple buildings from file definitions
- **Standardized Input**: Consistent building definition format
- **Automated Analysis**: Minimal user intervention required
- **Results Export**: Standardized costing result formats

## Usage Patterns

### Basic Costing Workflow

#### 1. Initialize Costing System
```ruby
# Create costing object with database loading
costing = BTAPCosting.new
costing.load_database

# Validate database integrity  
costing.validate_database
```

#### 2. Determine Regional Factors
```ruby
# Get regional cost factors for project location
location = "Toronto, ON"
cost_factors = costing.get_regional_cost_factors(location)

# Or use coordinates for precise interpolation
lat, lon = 43.7, -79.4
closest_location = costing.get_closest_cost_location(lat, lon)
```

#### 3. Calculate Component Costs
```ruby
# Example: Envelope costing
envelope_costs = calculate_envelope_costs(model, cost_factors)

# Example: HVAC system costing  
hvac_costs = calculate_hvac_costs(model, cost_factors)

# Aggregate all system costs
total_cost = envelope_costs + hvac_costs + lighting_costs + ...
```

### Advanced Costing Analysis

#### 1. ECM Cost-Benefit Analysis
```ruby
# Calculate baseline building cost
baseline_cost = calculate_total_building_cost(baseline_model, location)

# Calculate improved building cost
improved_cost = calculate_total_building_cost(improved_model, location)

# Determine incremental cost
ecm_cost = improved_cost - baseline_cost

# Calculate payback with energy savings
payback_period = ecm_cost / annual_energy_savings
```

#### 2. Regional Cost Comparison
```ruby
# Compare costs across multiple Canadian cities
cities = ["Vancouver, BC", "Calgary, AB", "Toronto, ON", "Montreal, QC"]
costs = {}

cities.each do |city|
  cost_factors = costing.get_regional_cost_factors(city)
  costs[city] = calculate_total_building_cost(model, cost_factors)
end
```

#### 3. Parametric Cost Analysis
```ruby
# Analyze cost impacts of different design parameters
insulation_levels = [RSI_2, RSI_3, RSI_4, RSI_5]
costs = []

insulation_levels.each do |r_value|
  modified_model = adjust_envelope_insulation(model, r_value)
  cost = calculate_envelope_costs(modified_model, cost_factors)
  costs << {r_value: r_value, cost: cost}
end
```

## Integration with NECB Standards

### Standards Compliance Costing
The costing framework fully integrates with NECB (National Energy Code for Buildings) requirements:

- **Baseline Compliance**: Cost of meeting minimum NECB requirements
- **Above-Code Measures**: Incremental costs for exceeding code requirements  
- **System Selection**: Cost implications of different NECB-compliant HVAC systems
- **Regional Variations**: How NECB compliance costs vary across Canadian climate zones

### Energy Conservation Measures (ECMs)
- **NECB ECM Library**: Pre-defined ECMs with established cost data
- **Custom ECM Analysis**: Tools for analyzing custom energy conservation measures
- **Lifecycle Cost Integration**: Complete economic analysis including energy savings

## Development Guidelines

### Adding New Component Costing

#### 1. Create Component Module
```ruby
# Create new file: new_system_costing.rb
class NewSystemCosting
  def self.calculate_costs(model, cost_factors, options = {})
    # Implement costing logic
  end
end
```

#### 2. Add Cost Database Entries
- Update appropriate CSV files in `common_resources/`
- Add equipment/material specifications
- Include regional cost factors
- Validate database integrity

#### 3. Create Tests
- Add component-specific test cases
- Test regional cost variations
- Validate against known project costs
- Include in automated test suite

#### 4. Integration
- Integrate with main costing workflow
- Add to cost aggregation logic
- Update documentation
- Include in validation framework

### Testing Requirements

#### 1. Component Tests
- Test each costing module independently
- Validate cost calculations against manual calculations
- Test regional factor applications
- Validate database lookups

#### 2. Integration Tests  
- Test complete building costing workflows
- Validate cost aggregation logic
- Test integration with NECB standards
- Validate ECM cost calculations

#### 3. Regression Tests
- Maintain baseline cost results for reference buildings
- Detect unintended cost calculation changes
- Validate database updates don't break existing functionality
- Performance regression testing

## Key Benefits for LLM Development

### Clear System Understanding
- **Component Relationships**: Understand how 9 costing modules interact
- **Data Flow**: Clear path from building model to final costs
- **Regional Logic**: How Canadian cost variations are handled
- **Integration Points**: Where costing connects to NECB standards and BTAP workflow

### Safe Modification Guidelines
- **Database Schema**: Understand CSV structure to prevent data corruption
- **Regional Factor Logic**: Critical cost interpolation algorithms
- **Testing Framework**: How to validate changes don't break existing functionality
- **API Boundaries**: Clear interfaces between costing modules

### Established Patterns
- **Component Addition**: Template for adding new building system costing
- **Data Updates**: Process for updating cost databases safely
- **Validation Requirements**: What constitutes valid costing data
- **Error Handling**: How to handle missing data and edge cases

This comprehensive framework represents years of Canadian building cost analysis expertise and provides the foundation for sophisticated building economic analysis.
