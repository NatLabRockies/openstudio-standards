# NECB rule data — provenance

## reference_rules_<vintage>.json

Machine-readable transcription of the NECB performance-path reference-HVAC rules:
system-selection table, system definitions (mapped to gem catalog names), and the
modeling rules (oversizing, heating/cooling plant staging, fans, hydronic pumps,
purchased energy).

- **2020**: Division B, Subsection **8.4.4** (Tables 8.4.4.7.-A/-B/8.4.4.13).
- **2025**: NECB 2025 **renumbered the performance path** — the reference-building rules
  moved to Subsection **8.4.5** (Tables 8.4.5.7.-A/-B/8.4.5.13; part-load curves to
  8.4.6). All rule *values* were verified identical to 2020 via MCP retrieval + edition
  diff; only article citations differ.

- **Source:** NECB 2020 code text retrieved through the building-codes MCP server
  (`necb:2020`, NRC copyright — the JSON stores rule VALUES and short quoted fragments
  for auditability, not the code text itself).
- **Provenance:** the file header records code/edition/source/date; every rule block
  carries an `article` citation. The audit log emitted at runtime repeats these
  citations per decision.
- **Runtime:** zero MCP dependency. The MCP server is a development/verification tool;
  when a new edition lands, regenerate a `reference_rules_<edition>.json` and diff.
- **Category keywords** extend the Table 8.4.4.7.-A space lists with common synonyms so
  arbitrary space-type strings map to a category; unmatched types fall back to the
  default category per 8.4.4.7.(3) with an audit warning.

## efficiencies_<vintage>.json

Capacity-binned minimum-performance tables (boilers, chillers, unitary ACs, heat pumps,
furnaces, heat rejection) + the NECB performance curves. Same provenance and
zero-runtime-dependency contract.

- **2020**: vendored verbatim from openstudio-standards NECB2020 `data/*.json`
  (= Table 5.2.12.1 values), curves from NECB2011 `curves.json`.
- **2025**: transcribed/verified per-table from the NECB 2025 Table 5.2.12.1 series via
  the MCP (letter map: -K chillers, -N boilers, -O furnaces, -A unitary ACs & HPs; the
  file's `provenance.verification` block records the per-table result). Verified
  **identical** to 2020: chillers (Path B COPc, every bin), boilers, furnaces, unitary-AC
  SEER/EER ladder. **Real 2025 changes**: HP cooling < 19 kW is SEER 15 (2020: EER 11.0 —
  the -A class merge), split-system HP heating HSPF 7.4 → 7.8. Additions: single-phase
  SEER2/HSPF2 class rows (distinct subcategories, engine-neutral), COPh at −8.3 °C
  (informational), and the NEW Table 5.2.12.1.-M plant-heat-pump heating COPs by leaving
  water temperature (`plant_heat_pumps_heating`, informational). SEER2/EER2/HSPF2 convert
  with the SEER/EER/HSPF formulas, matching the documented openstudio-standards
  assumption. Table -C (PTAC/PTHP coefficients) changed moderately in 2025; that
  coefficient path is not implemented by the engine (documented gap, same as 2020).
