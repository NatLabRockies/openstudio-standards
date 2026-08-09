# OpenStudio-Standards

openstudio-standards is a Ruby Gem library that extends the [OpenStudio SDK](https://www.openstudio.net/).
It has four main use-cases:

1. Provide methods to create OpenStudio models from geometry templates, user geometry, or programmatically generated geometry
2. Create typical building models in OpenStudio format
3. Create a code baseline model from a proposed model
4. Check a model against a code/standard

openstudio-standards previously supported making the DOE/PNNL prototype buildings in OpenStudio format. This has since been deprecated, as the DOE/PNNL prototypes are intended for specific code comparisons under the Energy Policy Act and are not intended to accurately represent typical existing or new buildings. While openstudio-standards still creates typical buildings, these are not identical to the DOE/PNNL prototypes.

## The NECB gem family (incubating in this repository)

Seven standalone, SDK-only gems implementing the NECB 2020/2025 Part 8
performance path live as siblings at the repository root. Dependency flow:
geometry → loads → (lighting, shw) and hvac/envelope stand alone; the
umbrella composes the five domain gems and runs EnergyPlus via
openstudio-simulation.

| Gem | One line |
|---|---|
| [openstudio-geometry](openstudio-geometry) | model creation: seven footprint wizards, the bar-by-shape engine, a 3D viewer |
| [openstudio-loads](openstudio-loads) | NECB space types, space-use loads, schedules (the bare-geometry on-ramp) |
| [openstudio-lighting](openstudio-lighting) | Part 4 LPD allowances, daylighting controls, exterior lighting, fixture costing |
| [openstudio-shw](openstudio-shw) | Part 6 service-water-heating demand, Table 6.2.2.1 efficiencies, costing |
| [openstudio-hvac](openstudio-hvac) | 97-system topology catalog, Table 8.4.4.7.-A reference systems, efficiencies, HVAC costing |
| [openstudio-envelope](openstudio-envelope) | prescriptive Section 3.2, thermal bridging (TBD), reference envelope, costing |
| [openstudio-simulation](openstudio-simulation) | the EnergyPlus runner (local CLI backend + remote seam) |
| [openstudio-necb](openstudio-necb) | **the umbrella**: the full 8.4.1.2 proposed-vs-reference determination, one audit, the AHJ HTML report |

Each gem's README is its API guide; `openstudio-necb/docs/README.md` carries
the family glossary and the decision-register guide.

## Overview of Main Features
If you are looking for a high-level overview of the features of this library, see the [Features](docs/Features.md) page.

## User Quick Start Guide

If you are a user, see the [User Quick Start Guide](docs/UserQuickStartGuide.md).

## Online Documentation

If you are a user, please see the [Online Documentation](https://gemdocs.org/gems/openstudio-standards) for an overview of how the library is structured and how it is used.

## Developer Information

If you are a developer looking to get started, see the [Developer Information](docs/DeveloperInformation.md) page.

For an overview of the repository structure, see the [Repository Structure](docs/RepositoryStructure.md).

For an overview of the code architecture, see the [Code Architecture](docs/CodeArchitecture.md).