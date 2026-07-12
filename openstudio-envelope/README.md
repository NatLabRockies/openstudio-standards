# openstudio-envelope

NECB building-envelope prescriptive rules and reference-envelope transforms for
OpenStudio models — the second domain gem following the
[openstudio-hvac](../openstudio-hvac) pattern: SDK-only model manipulation, vendored
article-tagged rule data (generated/verified offline via the building-codes MCP, zero
MCP dependency at runtime), a gem-wide AuditLog with article-coverage accounting, and
parity/EnergyPlus gates.

**Status: incubating (P1 of 5).** Currently ships the vendored NECB 2020 + 2025 rule
data (effective U-values by HDD zone, FDWR piecewise formula, skylight cap, Table C-1
climate data) with integrity/provenance tests. Coming per the plan: lookups + HDD
resolution (P2), prescriptive application + FDWR/SRR mutators (P3), thermal bridging
via the tbd gem (P3b — NECB 3.1.1.7 effective transmittance), and the greenfield
reference-envelope transform (P4, composing with openstudio-hvac's `reference_hvac`
for the full NECB reference building).

See `lib/openstudio_envelope/data/necb/README.md` for data provenance.
