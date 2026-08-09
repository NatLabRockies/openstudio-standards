# data/necb — Part 6 rules provenance

`shw_rules_2020.json` / `shw_rules_2025.json` — one ruleset per vintage. Top
keys: `autosize` (tank/loop sizing parameters), `efficiency` (Table 6.2.2.1
performance: electric standby-loss inputs, gas/oil UEF bins, large-equipment
Et, parasitic fractions, the 8.4.5.9/8.4.6.9 part-load curve spec),
`solar_pool_minimums` (D-63: solar SEF + pool-heater minimums, applied only
when the model carries the equipment), `article_coverage` (the Section 6 /
8.4.4.20 manifest), and `provenance` (generation method + verification dates).

**The formula strings are documentation, not configuration.** Rows like
`"sl_w_small_low_volume": "40 + 0.2 x V_litres (V < 270, bottom inlet)"`
record WHERE a coefficient comes from; the live coefficients are transcribed
in `necb/efficiency.rb` (named constants + formulas, declared a verbatim port
of the legacy NECB2020 `water_heater_mixed_apply_efficiency`, pinned by
`test_shw_parity.rb`). Editing a formula string here changes nothing at
runtime — change the code and the string together.

Numeric values that ARE consumed at runtime (bin intercepts/slopes,
thermal-efficiency floors, parasitic fractions, curve coefficients, the
solar/pool minimums) are read through `NECB.rules(vintage)` and covered by
the orphan-key lint: a vendored key nobody reads fails the build.

Verification trail: transcribed from the legacy pass, cross-verified against
the printed NECB Table 6.2.2.1 via the building-codes MCP (see each file's
`provenance` block for dates); the 6.2.2.1 solar/pool values were re-verified
against hbix's restored table extraction (D-61/D-63, 2026-08). NEVER edit
values here without re-running `test_shw.rb` (rules lint) and
`test_shw_parity.rb` (legacy parity) — and the fleet week sweep if anything
energy-affecting moves.
