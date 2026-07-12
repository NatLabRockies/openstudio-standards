# NECB loads data — provenance and regeneration

One machine-readable dataset per vintage, transcribing the NECB space-use modelling
data (Article 8.4.3.2: operating schedules, internal loads, set-points).

## Files

- `space_types_2020.json` — the 308 NECB2020 space-type records, vendored VERBATIM
  from the openstudio-standards **MERGED** standards_data (inheritance chain
  NECB2011←2015←2017←2020, later keys win — the raw per-vintage files are partial;
  the merge is what legacy actually runs). Every record keeps all 80 keys,
  including `lighting_*` and `service_water_heating_*`: this gem does **not act**
  on those (openstudio-lighting / openstudio-shw territory) but is the canonical
  space-type data owner for the gem family. Units are IP as in legacy (documented
  in the provenance block); the apply layer converts exactly as legacy does.
- `schedules_2020.json` — the 240 `NECB-<letter>-<category>` schedule records
  (Hourly 24-value rows per `day_types` token + Constant records), vendored from
  the merged standards_data (the schedules table is inherited from NECB2015 —
  2017/2020 ship none of their own).
- `loads_rules_2020.json` / `loads_rules_2025.json` — provenance, the
  schedule-table citation prefix, and the **article-coverage manifest** for
  Subsection 8.4.3 (same contract as the openstudio-hvac/envelope gems: statuses
  implemented / partial / not_implemented / host_scope; partial and
  not_implemented WARN in every audit).

## 2025

Verified via the building-codes MCP server (necb:2025): Table A-8.4.3.2.(2)-B was
retrieved in full for BOTH editions and compared row-by-row — all 89 space
functions carry identical occupant density, receptacle load, SWH load, schedule
letter, and illuminance; schedule set A cell-verified identical. The only 2025
changes are structural: Article 8.4.3.2 was reorganized into clauses and the
schedule tables renumbered `A-8.4.3.2.(1)-X` → `A-8.4.3.2.(1)(b)-X`. The 2025
rules file therefore aliases the 2020 data tables (`data_vintage_alias`) and
carries the renumbered citation prefix.

## Verification workflow

Generated offline; **runtime never contacts the MCP**. To regenerate: dump
`Standard.build('NECB2020').standards_data` tables under the repo bundle, wrap
with the provenance blocks, and re-run `test/test_data_integrity.rb` (structural
equality vs the legacy merged tables + MCP spot checks). When a new edition
lands, diff the A-8.4.3.2 tables via the MCP before aliasing or transcribing.
