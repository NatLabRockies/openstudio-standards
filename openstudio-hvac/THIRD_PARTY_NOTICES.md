# Third-Party Notices

This gem embeds third-party assets. Their copyright and license terms are
reproduced below, as required by their licenses.

---

## OpenStudio Application component icons

The HTML system catalog produced by `OpenStudioHVAC::CatalogReport`
(`OpenStudioHVAC.catalog_html`) embeds component icons taken from the
**OpenStudio Application**
(<https://github.com/openstudiocoalition/OpenStudioApplication>). The
IDD-object-type → icon-file mapping follows that project's
`src/shared_gui_components/IconLibrary.cpp`.

The icons are the retina (`@2x`) PNGs from
`src/openstudio_lib/images/`, base64-embedded (once each) in the generated,
self-contained HTML document. They are stored in this gem at
`lib/openstudio_hvac/catalog_icons.rb` and regenerated with
`scripts/build_icons.rb`.

**License:** BSD-3-Clause

**Copyright notice (verbatim):**

> OpenStudio(R), Copyright (c) 2020-2025, OpenStudio Coalition and other
> contributors. All rights reserved.

The full BSD-3-Clause license text is published with the OpenStudio Application
at <https://github.com/openstudiocoalition/OpenStudioApplication/blob/develop/LICENSE.md>.
BSD-3-Clause permits redistribution in source and binary forms, with or without
modification, provided that the copyright notice, this list of conditions, and
the disclaimer are retained, and that neither the names of the copyright holders
nor of their contributors are used to endorse or promote derived products
without prior written permission. The software is provided "as is", without
warranty of any kind.

### Icon files used (39, retina `@2x` PNG)

```
OAMixer@2x.png
baseboard_electric@2x.png
baseboard_water@2x.png
boiler@2x.png
cav_reheat@2x.png
chiller_air@2x.png
coil_ht_dx_singlespeed@2x.png
coilheatingwater_baseboard@2x.png
cool_coil@2x.png
cool_coil_dx_vari_speed@2x.png
cooling_tower@2x.png
direct-air@2x.png
directEvap@2x.png
districtcooling@2x.png
districtheating@2x.png
dxcoolingcoil_2speed@2x.png
dxcoolingcoil_singlespeed@2x.png
electric_furnace@2x.png
energy_recov_vent@2x.png
evap_fluid_cooler@2x.png
fan_constant@2x.png
fan_variable@2x.png
four_pipe_fan_coil@2x.png
furnace@2x.png
ground_heat_exchanger_vertical@2x.png
heat_coil@2x.png
heat_coil-uht@2x.png
heat_pump3@2x.png
heatpump_watertowater_equationfit_heating@2x.png
ht_coil_dx_vari@2x.png
pump_constant@2x.png
pump_variable@2x.png
system_type_1@2x.png
system_type_2@2x.png
vav-reheat@2x.png
vrf_unit@2x.png
wahpDXCC@2x.png
wahpDXHC@2x.png
watertoairHP@2x.png
```
