# OpenStudio-Standards

openstudio-standards is a Ruby Gem library that extends the {https://www.openstudio.net/ OpenStudio SDK}.
It has four main use-cases:

1. Provide higher level methods to help BEM users and developers to create OpenStudio models from custom or programmatically-generated geometry
2. Create typical building models in OpenStudio format
3. Create a code baseline model from a proposed model
4. Check a model against a code/standard

openstudio-standards previously supported making the DOE/PNNL prototype buildings in OpenStudio format. This has since been deprecated, as the DOE/PNNL prototypes are intended for specific code comparisons under the Energy Policy Act and are not intended to accurately represent typical existing or new buildings. While openstudio-standards still creates typical buildings, these are not the same as the highly specific DOE/PNNL prototypes that are used for code determination. Typical buildings may share the same geometry and some component level assumptions, but they strive to be more realistic and are updated regularly to reflect common practice.

## Overview of Main Features
If you are looking for a high-level overview of the features of this library, see the {file:docs/Features.md Features page}.

## User Quick Start Guide

If you are a user, see the {file:docs/UserQuickStartGuide.md User Quick Start Guide}

## Online Documentation

If you are a user, please see the {http://www.rubydoc.info/gems/openstudio-standards Online Documentation} for an overview of how the library is structured and how it is used.

## Developer Information

If you are a developer looking to get started, see the {file:docs/DeveloperInformation.md Developer Information page}.

For an overview of the repository structure, see the {file:docs/RepositoryStructure.md Repository Structure page}.

For an overview of the code architecture, see the {file:docs/CodeArchitecture.md Code Architecture page}.