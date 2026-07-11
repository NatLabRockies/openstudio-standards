# openstudio-hvac

Build HVAC system **topologies** on OpenStudio thermal zones by **descriptive, fuel-encoding
system name** — no standards metadata, no pre-existing systems, no sizing runs required.

Incubating inside the openstudio-standards repository as an independent, SDK-only gem
(`require 'openstudio'` is the only runtime dependency). Topology only by design: sizing runs
and code-efficiency application are the host application's job (e.g. openstudio-standards,
whose data-driven efficiency pass applies to any topology, including systems built here).

## Usage

```ruby
require 'openstudio_hvac'

# Discover the catalog (a closed, validated vocabulary — MCP/tool friendly)
OpenStudioHVAC.systems(filter: 'Gas')
# => [{ 'name' => 'PSZ RTU Gas and DX Coils and Hot Water Baseboard', 'family' => 'psz', ... }, ...]

# Build a system on a set of zones. The name IS the fuel specification.
result = OpenStudioHVAC.build_system(
  model,
  'PSZ RTU Gas and DX Coils and Hot Water Baseboard',
  zones,
  control_zone: zones.first,       # explicit control zone: no sizing run needed to elect one
  remove_existing: false,          # true = zone-scoped teardown first (replace, don't stack)
  namer: :default                  # :necb_pipe_name reproduces the NECB naming convention
)
result.air_loops    # => [OpenStudio::Model::AirLoopHVAC]
result.control_zone
```

Preconditions (validated with clear errors): zones must carry dual-setpoint thermostats;
the control zone must be one of the served zones.

### Integration with openstudio-standards (efficiency)

```ruby
# 1. topology (this gem)
OpenStudioHVAC.build_system(model, 'PSZ RTU Electric and DX Coils and Electric Baseboard', zones)
# 2. sizing + code efficiencies (host)
standard = Standard.build('NECB2011')
standard.model_run_sizing_run(model, sizing_dir)
standard.model_apply_hvac_efficiency_standard(model, 'NECB HDD Method')
# -> NECB capacity-binned COP/EER + reference curves land on the gem-built coils
```

## Catalog (current)

| Family | Systems | Origin |
|---|---|---|
| `psz` | `PSZ RTU {Gas,Electric} and DX Coils and {Hot Water,Electric} Baseboard` (+ `with exhaust` variants) | NECB sys3 / sys4, unified into one implementation |
| `vav_reheat` | `MZ BU RTU {Electric,Hot Water} Heating Coil {Scroll,Centrifugal,Rotary Screw,Reciprocating} Chiller and {Electric,Hot Water} Baseboard` | NECB sys6: per-story built-up VAV, supply+return fans, CHW/CW plant |
| `fan_coils` | `{FPFC,TPFC} MAU {DX,Chilled Water} Coils with {Scroll,Centrifugal,Rotary Screw,Reciprocating} Chiller` | NECB sys2/sys5: per-zone fan coils + CV make-up air unit. TPFC names are NEW (the legacy catalog had no sys5 descriptions) |
| `mau_ptac` | `PSZ MAU {Hot Water,Electric} and DX Coils and {Hot Water,Electric} Baseboard with PTAC` | NECB sys1: 100% OA make-up air unit + per-zone PTAC + baseboards |

44 catalog names covering all NECB reference systems sys1–sys6 (non-heat-pump). Every family
is parity-verified against the legacy openstudio-standards NECB builders (object inventory,
sizing fields, quirks and all — pipe-names byte-identical), and the topology + host-efficiency
contract is integration-verified (NECB2011 capacity-binned values + reference curves land on
gem-built coils after the host's sizing/efficiency pass).

Planned extensions: CBECS descriptive types mapped onto these families, and NECB ECM system
topologies (hs08–hs16). NECB reference-heat-pump variants are out of scope for now (they
require regional standards data; future work via config injection).

## Design notes

- **The name is the API.** Each catalog row fully specifies topology + fuels/coils/baseboard,
  like CBECS's `'Baseboard gas boiler'` and NECB's systems.json descriptions.
- **`control_zone:` is a first-class parameter.** Single-zone systems (one air handler tracking
  one thermostat over several zones) traditionally elected the control zone by largest heating
  load, requiring a sizing run and standards-tagged geometry. Naming it explicitly removes that
  dependency entirely.
- **NECB behavior is data** (`lib/openstudio_hvac/data/`): sizing blocks (`sizing.json`),
  reference performance curves (`curves.json`), and the catalog (`systems.json`).
- **Naming is pluggable.** `:necb_pipe_name` byte-matches the legacy
  `sys_3|mixed|shr>none|...` convention (verified against openstudio-standards output) for
  hosts whose downstream code parses those names.
- **Zone-scoped teardown** (`remove_existing:`) replaces systems on the given zones only,
  including orphaned plant loops (water-cooled chiller → condenser chains handled via a
  fixpoint), preserving service-hot-water loops and other zones' systems.

## Tests

```bash
cd openstudio-hvac
ruby test/test_catalog.rb
ruby test/test_naming.rb
ruby test/test_psz.rb
```

Plain ruby + the OpenStudio SDK bindings — no bundler required.
