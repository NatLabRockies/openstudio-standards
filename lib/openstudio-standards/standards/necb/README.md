# NECB (National Energy Code for Buildings) Standards

## Overview

The NECB (National Energy Code for Buildings) standards module provides comprehensive implementation of Canadian building energy codes. This module represents one of the most complete implementations of a national building energy standard, covering multiple versions of the Canadian National Energy Code for Buildings, vintage building standards, and energy conservation measures.

## Architecture

The NECB module is organized into four main categories:

1. **NECB Standard Versions** (2011, 2015, 2017, 2020)
2. **BTAP Vintage Standards** (Pre-1980, 1980-2010)  
3. **Energy Conservation Measures (ECMS)**
4. **Shared Resources** (Common data, documentation, QAQC)

## NECB Standard Versions

### NECB2011 - Foundation Implementation

#### Core Module: `necb_2011.rb`
**Most comprehensive NECB implementation with full building system coverage**

**Key Features:**
- Complete climate zone implementation for Canada (8 climate zones)
- All 8 HVAC system types with both single-speed and multi-speed variants
- Comprehensive building envelope requirements
- LED lighting compliance and occupancy sensor controls
- Service water heating system requirements
- BEPS (Building Energy Performance Standards) compliance pathways
- Thermal bridging calculations (TBD integration)
- Quality assurance and quality control (QAQC) framework

**Major Subsystems:**

##### HVAC Systems (`hvac_system_*.rb`)
- **System 1**: Single Zone systems (`hvac_system_1_single_speed.rb`, `hvac_system_1_multi_speed.rb`)
- **Systems 2 & 5**: Multi-zone VAV systems (`hvac_system_2_and_5.rb`)
- **Systems 3 & 8**: Single zone heat pumps (`hvac_system_3_and_8_single_speed.rb`, `hvac_system_3_and_8_multi_speed.rb`)  
- **System 4**: Multi-zone VAV with reheat (`hvac_system_4.rb`)
- **System 6**: Multi-zone VAV with PFP boxes (`hvac_system_6.rb`)
- **General**: `hvac_systems.rb`, `hvac_namer.rb`

##### Building Systems
- **Envelope**: `building_envelope.rb` - Comprehensive building envelope requirements
- **Lighting**: `lighting.rb` - Interior lighting power density and controls
- **Service Water Heating**: `service_water_heating.rb` - Hot water system efficiency requirements
- **Electrical**: `electrical_power_systems_and_motors.rb` - Motor efficiency requirements

##### Specialized Features  
- **Auto-zoning**: `autozone.rb` - Automated thermal zone creation
- **System Fuels**: `system_fuels.rb` - Fuel type selection and mapping
- **BEPS Compliance**: `beps_compliance_path.rb` - Building Energy Performance Standards

##### Data Resources (`data/`)
**Extensive JSON database covering:**
- **Climate & Geography**: `climate_zone_sets.json`, `province_map.json`
- **Building Envelope**: `materials.json`, `surface_thermal_transmittance.json`
- **HVAC Equipment**: `boilers.json`, `chillers.json`, `furnaces.json`, `heat_pumps.json`, `unitary_acs.json`
- **System Selection**: `systems.json`, `necb_hvac_system_selection_type.json`
- **Energy Efficiency**: `motors.json`, `heat_rejection.json`, `erv.json`
- **Building Types**: `space_types.json`, `prototype_inputs.json`
- **Lighting**: `led_lighting_data.json`
- **Economics**: `regional_fuel_use.json`
- **Reference Data**: `necb_2015_table_c1.json`, `constants.json`, `formulas.json`

##### Quality Assurance (`qaqc/`)
- **Main Module**: `necb_qaqc.rb` - Comprehensive model validation
- **Resources**: `qaqc_resources/` - Reference data for validation
- **Data**: `qaqc_data/` - Expected results for testing

### NECB2015 - Enhanced Version  

#### Core Module: `necb_2015.rb`
**Updated NECB implementation with enhanced lighting and HVAC systems**

**Key Improvements over 2011:**
- Enhanced lighting power density requirements
- Updated HVAC system efficiency requirements
- Refined control strategies

**Modules:**
- **Lighting**: `lighting.rb` - Updated lighting requirements
- **HVAC**: `hvac_systems.rb` - Enhanced system implementations
- **QAQC**: `qaqc/necb_2015_qaqc.rb` - Version-specific validation

### NECB2017 - System Updates

#### Core Module: `necb_2017.rb`  
**Newer version focusing on HVAC system improvements**

**Key Features:**
- Updated HVAC system requirements
- Enhanced system control strategies
- Refined equipment efficiency requirements

**Modules:**
- **HVAC**: `hvac_systems.rb` - Updated system implementations

### NECB2020 - Latest Version

#### Core Module: `necb_2020.rb`
**Latest NECB implementation with building envelope and service water heating improvements**

**Key Features:**
- Enhanced building envelope performance requirements
- Updated service water heating efficiency standards
- Latest building code compliance requirements

**Modules:**
- **Envelope**: `building_envelope.rb` - Updated envelope requirements
- **Service Water Heating**: `service_water_heating.rb` - Enhanced efficiency requirements

## BTAP Vintage Standards

### BTAPPRE1980 - Pre-1980 Building Standards

#### Core Module: `btap_pre1980.rb`
**Building performance standards for buildings constructed before 1980**

**Purpose:** Historical building analysis and retrofit potential assessment

**Key Features:**
- Legacy building envelope performance levels
- Historical HVAC system types and efficiencies  
- Vintage building infiltration rates
- Baseline performance for retrofit analysis

**Modules:**
- **Envelope**: `building_envelope.rb` - Pre-1980 construction standards
- **HVAC Systems**: Multiple system files for historical equipment types
- **Data**: `data/` - Historical performance data

### BTAP1980TO2010 - Transitional Period Standards

#### Core Module: `btap_1980to2010.rb`
**Building standards for the 1980-2010 construction period**  

**Purpose:** Bridge between historical and modern building standards

**Key Features:**
- Transitional building envelope requirements
- Equipment efficiency improvements over pre-1980 era
- Building code evolution tracking

## Energy Conservation Measures (ECMS)

### ECMS Framework (`ECMS/`)

#### Core Module: `ecms.rb`
**Energy Conservation Measures implementation framework**

**Purpose:** Systematic evaluation and implementation of building energy efficiency measures

**Key ECM Categories:**

##### HVAC ECMs (`hvac_systems.rb`)
- Advanced HVAC system configurations
- High-efficiency equipment options
- System optimization strategies

##### Energy Recovery Ventilation (`erv.rb`)
- Energy recovery ventilator implementation
- Heat recovery system integration
- Ventilation system optimization

##### Natural Ventilation (`nv.rb`)  
- Natural ventilation strategies
- Mixed-mode system implementation
- Climate-responsive ventilation control

##### Renewable Energy (`pv_ground.rb`)
- Ground-mounted photovoltaic systems
- Solar energy integration
- On-site renewable energy generation

##### Load Optimization (`loads.rb`)
- Building load reduction strategies
- Equipment efficiency improvements
- Operational optimization measures

##### Data Resources (`data/`)
- ECM performance data
- Cost-benefit analysis parameters
- Implementation guidelines

## Shared Resources

### Common Data and Utilities (`common/`)

#### BTAP Integration
- **`btap_datapoint.rb`**: Large-scale building analysis utilities
- **`btap_data.rb`**: Common BTAP data handling functions

#### Economic and Environmental Data
- **`national_carbon_price_sched_feb_2025.json`**: Canadian carbon pricing schedules
- **`utility_pricing_2025-02-20.csv`**: Canadian utility rate data
- **`neb_end_use_prices.csv`**: End-use energy pricing
- **`eccc_electric_grid_intensity_20250311.csv`**: Electric grid emissions factors
- **`nir_gas_grid_intensity_20250311.csv`**: Natural gas grid emissions factors

#### Reference Data
- **`necb_reference_runs.csv`**: Reference building performance data
- **`space_type_upgrade_map.json`**: Space type transformation mappings
- **`system_types.yaml`**: HVAC system type definitions
- **`construction_defaults.osm`**: Default construction assemblies

#### Documentation (`docs/`)
- **`air_system_names_method.md`**: Air system naming conventions

#### Specialized Resources
- **`phius.md`**: Passive House Institute US integration notes
- **`bc_step_code_indicators.md`**: British Columbia Step Code compliance

## Key Features and Capabilities

### Climate Zone Implementation
- **8 Canadian Climate Zones**: Complete implementation from Zone 4 (warmest) to Zone 8 (coldest)
- **Provincial Mapping**: Automatic climate zone determination by province and city
- **Weather Data Integration**: Seamless integration with Canadian weather files

### HVAC System Types
**Complete implementation of all 8 NECB system types:**

1. **System 1**: Residential/Small Commercial (≤ 25,000 ft²)
2. **System 2**: Multi-zone VAV with reheat
3. **System 3**: Single-zone heat pump  
4. **System 4**: VAV with reheat (large buildings)
5. **System 5**: Packaged VAV with reheat
6. **System 6**: VAV with PFP boxes and reheat
7. **System 7**: VAV with hot water reheat
8. **System 8**: VAV with electric reheat

**Each system type includes:**
- Single-speed and multi-speed equipment options
- Appropriate control strategies
- Equipment sizing and selection
- Energy efficiency requirements

### Building Performance Standards (BEPS)  
- **Performance Path Compliance**: Alternative compliance using energy modeling
- **Prescriptive Path Integration**: Seamless integration with prescriptive requirements
- **Trade-off Analysis**: Building component performance trade-offs
- **Compliance Reporting**: Automated compliance documentation

### Advanced Features

#### Thermal Bridging Integration
- **TBD Integration**: Heat transfer through thermal bridges
- **Detailed Heat Transfer**: Beyond simple assembly U-values
- **Whole Building Performance**: Complete thermal performance assessment

#### LED Lighting Compliance
- **Power Density Requirements**: Automatic lighting power density calculations
- **Control Integration**: Occupancy sensor and daylight dimming controls
- **Compliance Verification**: Automated lighting compliance checking

#### Quality Assurance Framework
- **Comprehensive QAQC**: Model validation and quality checking
- **Expected Results Testing**: Comparison against reference buildings
- **Performance Verification**: Energy use intensity and component performance validation

### Canadian-Specific Features

#### Provincial Integration  
- **Provincial Fuel Mapping**: Province-specific fuel type availability
- **Utility Rate Integration**: Provincial electricity and gas rate structures
- **Climate Data**: Canadian weather station integration

#### Economic Analysis
- **Regional Cost Factors**: Provincial and regional cost adjustments
- **Carbon Pricing**: Integration with Canadian carbon pricing policies
- **Lifecycle Cost Analysis**: Complete economic analysis framework

## Usage Patterns

### Typical Implementation Workflow

1. **Standard Selection**: Choose appropriate NECB version (2011, 2015, 2017, 2020)
2. **Climate Zone Determination**: Automatic based on building location
3. **System Type Selection**: Based on building type and size
4. **Component Specification**: Apply standard-specific requirements
5. **Performance Verification**: QAQC validation and compliance checking

### ECM Evaluation Process

1. **Baseline Model**: Create NECB-compliant baseline
2. **ECM Selection**: Choose from available energy conservation measures
3. **Performance Modeling**: Model ECM implementation
4. **Economic Analysis**: Cost-benefit analysis using Canadian data
5. **Optimization**: Identify optimal ECM combinations

### Integration Points

- **BTAP Framework**: Complete integration with BTAP costing and analysis
- **OpenStudio Standards**: Seamless integration with base standards framework
- **Canadian Data**: Weather, utility, and economic data integration

## Dependencies

### Internal Dependencies
- **Base Standards Framework**: Inherits from OpenStudio-Standards base classes
- **BTAP Integration**: Extensive integration with BTAP utilities and costing
- **Common Utilities**: Uses shared utility functions and data structures

### External Dependencies  
- **OpenStudio SDK**: Building energy modeling capabilities
- **EnergyPlus**: Energy simulation engine
- **TBD**: Thermal bridging analysis (optional)

### Data Dependencies
- **Canadian Weather Data**: Environment and Climate Change Canada weather files
- **Economic Data**: Statistics Canada and provincial utility data
- **Building Code Data**: National Research Council of Canada standards

## Development and Maintenance

### Version Evolution
- **NECB2011**: Foundation implementation (most complete)
- **NECB2015**: Lighting and HVAC updates
- **NECB2017**: System control improvements  
- **NECB2020**: Envelope and service water heating updates

### Testing Framework
- **Reference Buildings**: Comprehensive test suite using Canadian reference buildings
- **Regression Testing**: Automated testing against expected results
- **Compliance Verification**: Validation against published code requirements

### Maintenance Considerations
- **Code Updates**: Regular updates to reflect changes in Canadian building codes
- **Data Updates**: Annual updates to utility rates, carbon pricing, and cost data
- **Weather Data**: Updates to Canadian weather files as available

## Canadian Building Code Context

The NECB standards module provides the most comprehensive implementation of Canadian building energy requirements available in any building energy modeling tool. It reflects the unique aspects of Canadian building codes:

- **Climate-Based Requirements**: Robust climate zone implementation
- **System Type Flexibility**: Complete range of HVAC system options
- **Performance-Based Compliance**: Both prescriptive and performance path options  
- **Provincial Variations**: Accommodation of provincial building code differences
- **Economic Integration**: Canadian-specific cost and economic data

This makes the NECB module essential for any building energy analysis work in Canada.