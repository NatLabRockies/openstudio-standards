# data/ — what each file is, and the systems.json config schema

| File | Job |
|---|---|
| `systems.json` | THE catalog: 97 descriptive system names → family + build config. The name is the API; grep here before assuming a name exists. |
| `sizing.json` | named sizing blocks (`necb_psz`, `necb_mau_hp`, …) the builders stamp onto Sizing:Zone/System objects. The generic zone factors (heating 1.3 / cooling 1.1, HP cooling 1.0) are mirrored as sentinels in `necb/reference.rb` (`GENERIC_ZONE_*`) — change them together. |
| `curves.json` | structural performance curves the efficiency pass does NOT re-set (hs14 W2W, hs15 CAWHP). |
| `necb/` | vintage rulesets + efficiency tables + coverage manifests (own README). |
| `costing/` | costing CSV database (own README; licensing rules there). |

## systems.json row schema

Every row: `name` (exact string key), `family` (selects the builder in
`builder.rb::FAMILIES`), `needs_boiler`, plus family-specific keys below.
This schema GREW BY ACCRETION from three source vocabularies (NECB
systems.json descriptions, CBECS names, legacy ECM ids) — the historical
warts are called out rather than papered over.

| Key | Rows | Meaning / allowed values |
|---|---|---|
| `name` | 97 | the catalog key — byte-stable, matched exactly (aliases + generated `canonical_name` also resolve) |
| `family` | 97 | builder selector: one of the 18 families (`psz`, `vav_reheat`, `fan_coils`, `mau_ptac`, `baseboards`, `zone_terminal`, `unit_heaters`, `furnace`, `evap_cooler`, `wshp`, `vrf`, `zone_ervs`, `doas`, `doas_pthp`, `ecm_*`, `composite`) |
| `sys_abbr` | 70 | legacy pipe-name prefix (`sys_1`…`sys_6`, `psz_ac`, `pvav`) — feeds the `:necb_pipe_name` namer |
| `sizing` | 68 | which `sizing.json` block the build stamps |
| `origin` | 53 | provenance tag: `cbecs` / `generic` / `necb_ecm` / `necb_reference_hp` |
| `comment` | 54 | human note carried from the source vocabulary |
| `heating_coil_type` | 30 | the air-loop heating coil, and nothing else: `Gas` / `Electric` / `Hot Water`. (Historically `DX` also appeared here meaning "this is a reference ASHP build" — that is now `heat_source: 'ashp'`; the old spelling is still ACCEPTED as an alias by `psz.rb`/`canonical.rb`, but no row uses it and `test_catalog_schema.rb` fails if one comes back.) |
| `heat_source` | 8 | `ashp` — marks a reference air-source-heat-pump build (psz sys3/sys4 `necb_reference_hp` rows): DX heat + DX cool with `_ashp` coil names, plus the `supp_htg_fuel` supplemental coil. Legacy alias: `heating_coil_type: 'DX'` |
| `heating_type` | 5 | zone-terminal heat: `Gas` / `Electric` / `None` (zone_terminal + unit_heaters families — a SECOND heating vocabulary, historical) |
| `heating` | 1 | bare boolean on one composite part (third vocabulary; avoid in new rows) |
| `baseboard_type` | 55 | `Hot Water` / `Electric` / `None` |
| `needs_chiller`, `chiller_type` | 34/33 | CHW plant + compressor type (`Scroll`/`Centrifugal`/`Rotary Screw`/`Reciprocating`) |
| `mau_heating_coil_type`, `mau_cooling_type` | 20/16 | make-up-air-unit coils (`mau_cooling_type`: `DX`/`Hydronic` — note the asymmetric name, no `_coil_`) |
| `supp_htg_fuel` | 20 | ASHP supplemental coil fuel: `Gas` / `Electric` / `None` |
| `fan_coil_type` | 16 | `FPFC` (four-pipe) / `TPFC` (two-pipe) |
| `per_zone` | 12 | psz family: one packaged unit PER zone (the CBECS/90.1 convention) vs one for the group |
| `parts` | 12 | composite family: array of {name, config-override} pairs built on the same zones |
| `boiler_fuel` | 9 | `NaturalGas` / `Electricity` |
| `air_eqpt` | 7 | ECM DOAS coil set: `ashp` / `ccashp` / `hydronic` (lowercase — ECM dialect) |
| `unit_type` | 4 | zone_terminal: `ptac` / `pthp` / `window_ac` |
| `reference_hp` | 4 | marks the Table 8.4.4.13 reference heat-pump variants — the `mau_ptac` family's own marker (a second spelling of the same idea as `heat_source`, deliberately left alone: different family, different builder) |
| `plant_type` | 3 | ecm_hp_fancoils: `gshp` / `cawhp` |
| `vent_type`, `ventilation`, `zone_ventilation` | 2/2/1 | THREE ventilation vocabularies (historical): `vent_type: 'doas'` selects a DOAS part; the booleans toggle terminal OA |
| `hw_source` | 1 | `district` — baseboards on a district loop, no boiler |
| `cooling_type` | 1 | `'dx'` (lowercase) — PVAV two-speed DX instead of CHW |
| `cooling` | 1 | bare boolean off-switch on one composite part |

Value-case conventions differ by source vocabulary (`'Gas'` vs `'dx'` vs
`'ashp'`) — they are exact-match strings; copy an existing row rather than
guessing case. New rows should prefer the majority spellings
(`heating_coil_type`, `mau_cooling_type`, `vent_type`).

`test/test_catalog_schema.rb` freezes this schema: every row's keys must be in
its family's allowlist and every closed vocabulary above is enum-checked, so a
typo'd or invented key fails the suite. Adding a key is a conscious act — add it
to the test's allowlist AND to this table (with its row count).
