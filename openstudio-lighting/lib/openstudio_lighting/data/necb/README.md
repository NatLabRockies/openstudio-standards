# NECB lighting data — provenance and regeneration

- `led_lighting_2020.json` — the merged legacy `led_lighting_data` table (308
  records; LED alternative LPDs W/ft² + heat fractions per NREL 63807).
- `lpd_space_functions_2025.json` — NECB 2025 Table 4.2.1.6 transcribed in full
  via the building-codes MCP: LPD (W/m²) **plus the per-row 4.2.2.1
  lighting-control requirement matrix** new in 2025 (X = required, A/B =
  alternative groups).
- `lpd_building_types_2025.json` — NECB 2025 Table 4.2.1.5 (building-type
  method, W/m²).
- `daylighting_controls_4_2_1_6.json` — Table 4.2.1.6's two **daylight-control**
  columns (`... for Sidelighting [see 4.2.2.1.(10)]` / `... for Toplighting
  [see 4.2.2.1.(13)]`), keyed by the 105 NECB **space-function catalog names**
  rather than by table row, so the 4.2.2.1.(10)/(13) gate is a direct lookup.
  Four-state per column: `required` / `not_required` / `not_applicable` /
  `unknown`. **D-57.** See "The Table 4.2.1.6 extraction problem" below — do not
  regenerate this file from a single MCP call.
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

## The Table 4.2.1.6 extraction problem (read before touching the control data)

**Both** MCP extractions of Table 4.2.1.6 are partly corrupted, and they are
corrupted **differently**. Neither may be vendored blind.

- The **2020** extraction is the worse one. Its `Space Category` column *lags*
  the row it belongs to, so rows read like `Classroom/lecture hall/training room
  | Computer/Server room`, and it drops whole rows' worth of control marks: it
  carries `Manual` = X on only **57 of 103** rows, where 4.2.2.1.(3) makes that
  column apply to *every* space type listed in the table. It reports 40 X in
  each daylight column.
- The **2025** extraction keeps `Space Category` correct per row and carries
  `Manual` = X on **85 of 105** rows. It reports 67 sidelighting / 64
  toplighting X.
- Aligned by leaf name + LPD, the two disagree on **38 of 91** matched rows.

Therefore: 2025 is the primary source; 2020 is used **only to corroborate, never
to negate**. An X in 2020 where 2025 is blank is a **CONFLICT** (state
`unknown`), not an absence. An empty cell is never read as "not required" on one
extraction's word alone.

Some cells are genuine cross-references, not flags, and are stated as such:
`Storage garage interior` → Article 4.2.2.2. (which has its *own* daylight rule
in Sentence (4)); `Guest room` → Sentence 4.2.2.6.(2); `medical supply room` →
the Storage Room rows under Common Space Types.

Mapping validation: each of the 105 catalog names was mapped by hand to a table
row, then every hard mapping was checked by comparing the catalog's
`lighting_per_area` (W/ft² × 10.7639) against the row's LPD (W/m²) — **102 of
102 agree** within 0.06 W/m² / 1%.

Residue (published in the file's own `residue` array, and asserted by
`test_daylighting_necb2020.rb`): 4 names with no table row (`- undefined -`,
both `Dwelling units` rows, `Audience seating area permanent - convention
centre`), `WholeBuilding` (building-type method — 4.2.2.1.(2) ties the control
requirement to the space-by-space types the tag does not identify), and 4 rows
whose columns CONFLICT between extractions (`Classroom/Lecture hall/Training
room other` toplighting; `Health care facility physical therapy room`
sidelighting; `Manufacturing facility low bay area` toplighting; `Museum general
exhibition area` both). Every one of these WARNS loudly at runtime and takes the
documented conservative default (`required` — photocontrols in the *reference*
lower its lighting energy and so tighten the target, which cannot hand a
non-conforming building a pass). `unknown_control_requirement: :not_required`
flips it, still warning.

Interior LPDs for 2020 live in the openstudio-loads gem's space-type records
(`lighting_per_area` W/ft² + fractions + `occ_sense`/`rel_absence_occ`/
`personal_control` = the Table 4.3.2.10 factors); this gem reads them through
`OpenStudioLoads::NECB::SpaceTypes`. Runtime never contacts the MCP.
