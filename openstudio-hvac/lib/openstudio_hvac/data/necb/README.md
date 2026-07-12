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
  diff; only article citations differ. The 2025 file declares
  `efficiency_vintage_fallback: 2020` because Table 5.2.12.1.-A (unitary equipment) was
  restructured in 2025 (SEER2/EER2 transition) and is not yet transcribed —
  `apply_efficiencies` uses 2020 values with an audit warning until it is.

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

## efficiencies_<vintage>.json (phase 3)

Capacity-binned minimum-performance tables (boilers, chillers, unitary ACs, heat pumps,
furnaces, heat rejection, fan/pump motor rules) vendored from openstudio-standards
NECB<vintage> `data/*.json`, cross-checked against NECB Table 5.2.12.1. Same provenance
and zero-runtime-dependency contract.
