# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

openstudio-standards is a Ruby Gem library that extends the OpenStudio SDK for building energy modeling. It provides four main capabilities:

1. Methods to create OpenStudio models from geometry templates, user geometry, or programmatically generated geometry
2. Creating typical building models in OpenStudio format
3. Creating code baseline models from proposed models
4. Checking models against building energy codes/standards

The library supports multiple building energy codes and standards including ASHRAE 90.1 (various vintages), NECB (Canadian National Energy Code for Buildings), DEER, CBES, and others.

## Development Environment

**Ruby Version:** This project requires Ruby 2.7.2 (for OpenStudio 3.2.0-3.7.0) or Ruby 3.2.2 (for OpenStudio 3.8.0+). Currently using Ruby 3.2.2.

**OpenStudio:** Requires OpenStudio SDK 3.7.0+ installed and properly connected to Ruby via an `openstudio.rb` file. See `docs/DeveloperInformation.md` for setup instructions.

**Dependencies:** Run `bundle install` after cloning to install all required gems.

## Common Commands

### Running Tests

- **Run a single test file:** `ruby test/subdirectory/test_XX.rb`
- **Run all CircleCI tests:** `bundle exec rake test:circleci` (CI environment only)
- **Run parallel tests locally:** `bundle exec rake test:parallel_run_all_tests_locally`
- **Run specific test suites:**
  - `bundle exec rake test:circ-90_1_general`
  - `bundle exec rake test:circ-necb`
  - `bundle exec rake test:circ-doe_prototype`

Test files are located in `/test` directory, organized by standard/feature. Tests use Minitest framework.

### Code Quality

- **Check code style:** `bundle exec rake rubocop`
- **Auto-correct style issues:** `bundle exec rake rubocop:auto_correct`
- **View rubocop results in browser:** `bundle exec rake rubocop:show`

### Documentation

- **Generate YARD documentation:** `bundle exec rake doc`
- **Generate and view docs in browser:** `bundle exec rake doc:show`

Documentation is generated from inline YARD comments. All public methods must be documented with `@param`, `@return`, and description.

### Data Management

- **Update standards data from spreadsheets:** `bundle exec rake data:update`
- **Export JSONs to data library:** `bundle exec rake data:export:jsons`
- **Update costing database:** `bundle exec rake data:update:costing`

Note: 90.1 standards data comes from [building-energy-standards-data](https://github.com/pnnl/building-energy-standards-data). Other standards use JSON files in `/data/standards/` or Google Spreadsheets (contact maintainer for access).

### Building and Installation

- **Build gem:** `bundle exec rake build`
- **Install locally:** `bundle exec rake install`
- **List all available rake tasks:** `bundle exec rake -T`

## Code Architecture

### Inheritance-Based Standards System

The library uses class inheritance to implement different building energy codes/standards:

```
Standard (abstract base class)
├── ASHRAE901 (abstract)
│   ├── ASHRAE9012004
│   ├── ASHRAE9012007
│   ├── ASHRAE9012010
│   ├── ASHRAE9012013
│   ├── ASHRAE9012016
│   └── ASHRAE9012019
├── NECB (Canadian standards)
│   ├── NECB2011
│   ├── NECB2015
│   ├── NECB2017
│   └── NECB2020
└── [DEER, CBES, IECC, etc.]
```

**Key Concept:** Methods implemented in parent classes are inherited by children. Child classes can override methods to implement standard-specific requirements. Changes to child classes do not propagate back to parent or sibling classes.

**Creating Standards:** Use the factory method: `Standard.build('NECB2011')` or `Standard.build('90.1-2013')`

### Module Organization

The library is organized into functional modules in `/lib/openstudio-standards/`:

- **constructions** - Methods for creating/modifying building constructions
- **create_typical** - Methods to create entire typical building models
- **daylighting** - Daylighting control methods
- **geometry** - Geometry creation and manipulation
- **hvac** - HVAC system creation and modification
- **infiltration** - Infiltration modeling
- **schedules** - Schedule creation and modification
- **service_water_heating** - Service water heating systems
- **space** - Space-level methods
- **thermal_zone** - Thermal zone methods
- **weather** - Weather file handling
- **qaqc** - Quality assurance/quality control checks
- **utilities** - Common tasks (running simulations, logging, etc.)

### Standards Implementation

`/lib/openstudio-standards/standards/` contains the actual implementation of each standard:

- **standard.rb** - The abstract `Standard` base class
- **Standards.[Component].rb** - Methods for specific OpenStudio components (e.g., `Standards.ChillerElectricEIR.rb`, `Standards.Fan.rb`)
- **ashrae_90_1/** - ASHRAE 90.1 implementations by vintage
- **necb/** - Canadian NECB implementations by vintage
- **deer/**, **cbes/**, **icc_iecc/** - Other standard implementations

Standards methods lookup efficiency values, performance curves, construction U-values, etc., from the JSON data in `/data/standards/`.

### Prototypes

`/lib/openstudio-standards/prototypes/` contains typical building assumptions not governed by code (HVAC configurations, fan pressure drops, etc.). These are based on DOE Prototypes, DOE Reference Buildings, and Canadian Archetype Buildings.

### BTAP

`/lib/openstudio-standards/btap/` contains methods specific to the Canadian energy code (NECB) and Canadian prototype models. Many methods here are duplicative of `/standards` methods and are gradually being migrated.

## Data Directory Structure

- **/data/standards/** - Energy code/standard data (efficiencies, U-values, schedules, etc.) in JSON format
- **/data/geometry/** - 3D building geometry templates and HVAC system JSON descriptors
- **/data/weather/** - Weather files (.epw), design days (.ddy), and climate summaries (.stat)
- **/data/costing/** - Construction and material cost data (RS-Means database)

**Important:** Do not edit `/data/standards/` JSON files directly. Edit the [OpenStudio_Standards Google Spreadsheet](https://drive.google.com/drive/folders/1x7yEU4jnKw-gskLBih8IopStwl0KAMEi) or make pull requests to [building-energy-standards-data](https://github.com/pnnl/building-energy-standards-data), then run `bundle exec rake data:update`.

## Development Workflow

1. **Create a feature branch** from your local copy
2. **Modify code** following the architecture patterns
3. **Create tests** in `/test/subdirectory/test_XX.rb` for new functionality
4. **Document methods** using YARD format (see existing methods for examples)
5. **Run tests locally** to verify changes don't break existing functionality
6. **Check code style** with rubocop
7. **Generate documentation** to verify it looks correct
8. **Commit and push** branch to GitHub
9. **Create pull request** targeting the main branch (typically `develop`)
10. **Code review** by maintainers

### Testing Requirements

- All new code must have corresponding unit tests
- Tests prove code works and prevent future regressions
- Test files should follow naming convention: `test_XX.rb` in appropriate `/test/subdirectory/`
- Tests use Minitest framework with helper modules in `/test/helpers/`

## Important Notes

- **Standards Data Sources:** ASHRAE 90.1 data is managed in the external [building-energy-standards-data](https://github.com/pnnl/building-energy-standards-data) repository. Other standards may use Google Spreadsheets or local JSON files.

- **Code Reuse Philosophy:** The library heavily favors code reuse through inheritance and shared methods. When methods need to operate differently in different contexts, use input arguments rather than duplicating code. Only create separate methods when behavior is fundamentally different.

- **Standard Registration:** All Standard subclasses must register themselves using `register_standard('TemplateName')` to be available via the factory method.

- **Branches:** The main development branch is `develop`.

- **Continuous Integration:** Tests run automatically on CircleCI for all commits and pull requests. Test results are posted to GitHub PRs.

- **Issues:** Report issues and feature requests on the [GitHub Issues page](https://github.com/NREL/openstudio-standards/issues). Follow [OpenStudio Issue Prioritization Guide](https://github.com/NREL/OpenStudio/wiki/Issue-Prioritization) for labeling.

## Additional Documentation

- [Features](docs/Features.md) - High-level overview of library features
- [User Quick Start Guide](docs/UserQuickStartGuide.md) - For end users of the library
- [Developer Information](docs/DeveloperInformation.md) - Detailed setup and development process
- [Repository Structure](docs/RepositoryStructure.md) - Detailed file organization
- [Code Architecture](docs/CodeArchitecture.md) - Detailed architectural patterns
- [Online Documentation](https://gemdocs.org/gems/openstudio-standards) - Full API documentation

## Contact

For questions or to request access to data spreadsheets, contact matthew.dahlhausen@nrel.gov
