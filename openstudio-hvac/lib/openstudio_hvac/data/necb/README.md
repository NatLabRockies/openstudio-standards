# NECB rule data — provenance

## reference_rules_<vintage>.json

Machine-readable transcription of the NECB performance-path reference-HVAC rules
(Division B, Subsection 8.4.4): Table 8.4.4.7.-A system selection, Table 8.4.4.7.-B /
8.4.4.13 system definitions (mapped to gem catalog names), and the modeling rules
(oversizing 8.4.4.8, heating/cooling plant 8.4.4.9/8.4.4.10, fans 8.4.4.18, hydronic
pumps 8.4.4.14, purchased energy 8.4.4.6).

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
