# OpenStudio-Standards

openstudio-standards is a Ruby Gem library that extends the [OpenStudio SDK](https://www.openstudio.net/).
It has four main use-cases:

1. Provide methods to create OpenStudio models from geometry templates, user geometry, or programmatically generated geometry
2. Create typical building models in OpenStudio format
3. Create a code baseline model from a proposed model
4. Check a model against a code/standard

openstudio-standards previously supported making the DOE/PNNL prototype buildings in OpenStudio format. This has since been deprecated, as the DOE/PNNL prototypes are intended for specific code comparisons under the Energy Policy Act and are not intended to accurately represent typical existing or new buildings. While openstudio-standards still creates typical buildings, these are not identical to the DOE/PNNL prototypes.

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