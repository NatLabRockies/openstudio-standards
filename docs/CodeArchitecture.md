
# Code Architecture

## Modules
The openstudio-standards library contains a library of generic methods to create, modify, or get information about an OpenStudio model. These are organized in modules. See the ruby documentation for a detailed method list.
 - constructions
 - create_typical
 - daylighting
 - geometry
 - hvac
 - infiltration
 - qaqc
 - schedules
 - service_water_heating
 - space
 - standards (see below)
 - thermal_zone
 - weather

## Standards
In the openstudio-standards library, each code or standard (such as ASHRAE 90.1-2013) is represented by a Class.  Because many different standards share code, instead of having many copies of the same code, code reuse is accomplished through inheritance.

Here is the typical inheritance pattern:

- Standard (_abstract class_)
  - ASHRAE901 (_abstract class_)
    - ASHRAE9012004 (_concrete class_)
    - ASHRAE9012007 (_concrete class_)
    - ASHRAE9012010 (_concrete class_)
    - ASHRAE9012013 (_concrete class_)

Methods that are implemented in the **Standard** class are used by the inherited classes such as **ASHRAE90120013**.  However, if **ASHRAE90120013** has special requirements, it can reimplement some or all of the methods found in **Standard**.  These reimplementations can use their own logic.  These reimplementations will only be used by objects of the type **ASHRAE90120013**, they will not be propagated back up to the **Standard** class, or to any other Standards such as **ASHRAE9012004**.
