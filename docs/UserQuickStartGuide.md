# User Quick Start Guide

## Create Typical Building

Starting with OpenStudio 3.8.0, the "Create Typical Building from Model" measure is available on BCL and fully uses methods from openstudio-standards.

1. Components & Measures > Find Measures, download Whole Building > Space Types > Create Typical Building from Model
2. Components & Measures > Apply Measure Now > Whole Building > Space Types > Create Typical Building from Model
3. Pick the building type/climate zone/vintage
4. Run

## Create a Custom Building Type

To create a typical model of a custom building type — your own mix of space types with custom area ratios, building form, schedule overrides, and load overrides — pass a specification hash or JSON file to `OpenstudioStandards::CreateTypical.create_custom_building_from_spec`. See the {file:docs/CustomBuildings.md Custom Buildings page} for the specification format and examples.

## Using OpenStudio-Standards in Measures
**This gem is included with the OpenStudio installer**.  All you need to do is add `require openstudio-standards` to your `measure.rb` file and you will have access to the methods in this gem:

    class MyMeasureName < OpenStudio::Measure::ModelMeasure

     require 'openstudio-standards'
     ...

## Installing OpenStudio-Standards from RubyGems
If you want to install a newer release of this gem from RubyGems.org than what is available in the OpenStudio installer, follow the instructions on the {file:docs/DeveloperInformation.md Developer Information page}.
