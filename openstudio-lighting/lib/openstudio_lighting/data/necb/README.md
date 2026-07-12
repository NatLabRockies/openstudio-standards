# NECB lighting data — provenance and regeneration

- `led_lighting_2020.json` — the merged legacy `led_lighting_data` table (308
  records; LED alternative LPDs W/ft² + heat fractions per NREL 63807).
- `lpd_space_functions_2025.json` — NECB 2025 Table 4.2.1.6 transcribed in full
  via the building-codes MCP: LPD (W/m²) **plus the per-row 4.2.2.1
  lighting-control requirement matrix** new in 2025 (X = required, A/B =
  alternative groups).
- `lpd_building_types_2025.json` — NECB 2025 Table 4.2.1.5 (building-type
  method, W/m²).
- `lighting_rules_<vintage>.json` — provenance, sensor-schedule threshold
  (8.6 W/m²), dwelling-unit LPD (8.4.4.5.(2)), the LED atrium equations
  (legacy `space_height` NameError defect documented and fixed), and the
  Part 4 + 8.4.4.5 article-coverage manifest.

## The 2025 verification

The 4.2.1.6 edition diff looked significant (similarity 0.68) but is
**structural**: 2025 added ~9 control columns and renamed rows. The transcribed
2025 table was joined to the 2020 space-type records (openstudio-loads gem) by
normalized name — 162 exact matches, **zero LPD differences**, atrium bins
4.2/5.2/6.5 W/m² identical, every rename spot-checked identical. 2025 therefore
aliases the 2020 LPD data (`data_vintage_alias`), while the 2025 control matrix
and both 2025 tables ship as native data.

Interior LPDs for 2020 live in the openstudio-loads gem's space-type records
(`lighting_per_area` W/ft² + fractions + `occ_sense`/`rel_absence_occ`/
`personal_control` = the Table 4.3.2.10 factors); this gem reads them through
`OpenStudioLoads::NECB::SpaceTypes`. Runtime never contacts the MCP.
