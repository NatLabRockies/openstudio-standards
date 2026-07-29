# PENDING REVIEW — NECB reference-generation backlog (opened 2026-07-29)

**Status: OPEN. The work below was implemented WITHOUT a review pass.**

The backlog closing NECB 8.4.4.13.(2)(b)/(g), 5.2.2.9 water-side economizers,
8.4.4.15.(2) DCV copy, humidification rebuild, 8.4.4.20.(5) SHW part-load
curves and 8.4.4.5.(5)-(12) daylighting was implemented on 2026-07-29 with the
review deferred (no reviewer available that day).

Until every box below is ticked with evidence:

- do NOT quote the post-backlog fleet numbers as validated,
- do NOT flip any manifest entry to `implemented`,
- treat the D-46 full-annual table in `necb_decisions.md` as the last
  VALIDATED fleet baseline.

Tick with evidence — `[RAN]` plus the command, or `[READ]` plus file:line —
never with assertion. The full plan this came from is summarised in the
decision log; the phase numbering below matches it.

Written 2026-07-29 because the review pass could not run the same day. Each
item is a check the implementer cannot self-certify; tick with evidence
(`[RAN]` + the command, or `[READ]` + file:line), not with assertion.

### Cross-cutting (apply to EVERY phase)

- [ ] **Fleet sweep, week mode**, compared line-by-line against the D-46 final
      table in `necb_decisions.md`. Command:
      `SWEEP_MODE=annual ruby openstudio-necb/scripts/necb_archetype_sweep.rb <15 types>`
      (run from the repo root with an absolute script path — a relative path
      from a gem directory fails with LoadError).
      **Every building that moves needs an attributed cause before commit.**
      Precedent: staging moved the fleet 7-9 points in the LENIENT direction
      from a fan-schedule bug that every unit test passed through.
- [ ] **Reference vs proposed sanity ratios**, not just totals. The staging
      regression was only visible as `reference fans / proposed fans = 2.68`
      (normally ~1.0). Check fans, heating and cooling ratios per building.
- [ ] **A control building.** LargeOffice (system 6, hydronic) should be
      bit-identical end-use for end-use through any change that targets PSZ,
      DX, furnaces or staging. If it moves, the change is leaking.
- [ ] `test_decisions_registry.rb` green — every new D-XX both registered in
      `decisions.json` AND cited by a `ruling:` literal; the six
      `audit_log.rb` copies still byte-identical modulo module line.
- [ ] Manifest lint: `test_necb_energy_recovery.rb:163` and `:192` (22 entries,
      status enum, gaps required for `partial`, per-vintage article prefix).
- [ ] `ruby openstudio-necb/scripts/necb_orphan_keys.rb` → OK (any newly
      vendored rule key must actually be read by `lib/`).
- [ ] **Before calling anything a defect, run the refuting check first.** Five
      false premises so far on this project; the most recent (staged airflow
      "violates constant-volume") was refuted by one IDD lookup that should
      have preceded the claim.

### Phase 0 — truth-up
- [ ] The three test sites pinning the unconditional lighting warning were
      updated, not deleted: `test_exterior_and_reference.rb:61`, `:102`,
      `openstudio-necb/test/test_compliance.rb:85`.
- [ ] No behaviour changed — diff should be docs/strings/conditionals only.

### Phase 1 — SHW part-load curve
- [ ] The 8.4.5.9 quadratic (a=0.021826, b=0.977630, c=0.000543) was verified
      FUNCTIONALLY over a sampled PLR envelope, self-checking ≈1.0 at the
      rating point — not compared coefficient-wise (vendored rounding reads as
      fake deviation; D-03/D-13 precedent).
- [ ] Whether the curve legitimately applies to electric and instantaneous
      water heaters was decided from the article text ("Fuel-Fired Service
      Water Heater"), and the answer is stated in `how` rather than left as a
      silent skip.
- [ ] `test_shw.rb:11` (pins the old cubic) moved deliberately, and
      `test_shw.rb:103` (requires ≥1 coverage warning) still passes.

### Phase 2 — daylighting default ON
- [ ] Runtime cost measured and recorded in D-51 (sweep wall-clock before vs
      after) — detailed daylighting on 15 archetypes is the risk.
- [ ] Reference interior-lighting energy fell (the expected direction) and the
      per-building shift is attributed.
- [ ] `test_compliance.rb:85` still meaningful now that the default flipped.

### Phase 3 — DCV copy
- [ ] DCV is read from the proposed's `controllerMechanicalVentilation` and
      applied to the REFERENCE controller — confirm on a model that actually
      has DCV on (the fixtures may not; build one if needed).
- [ ] Legacy's misspelled `'NECB_Defualt'` guard (L-13) was NOT ported.

### Phase 4 — humidification
- [ ] The pre-teardown over-count is fixed: humidifiers surviving on
      `:copy_proposed` loops no longer trigger the "not rebuilt" warning.
- [ ] Rebuilt humidifiers carry the SAME energy source as the proposed's, and
      a humidistat/setpoint manager that actually controls them (an
      uncontrolled humidifier is silently inert).
- [ ] A test exists — the T8 warning is currently unpinned by anything.

### Phase 5 — HP (2)(b) + (2)(g)
- [ ] **The pipeline reorder is the risk item.** Confirm nothing mutates the
      proposed between its sizing run and the reference build before relying
      on the earlier annual run; confirm capacity iteration still re-runs what
      it must; confirm `simulate: :sizing`/`:none` still work (no annual data).
- [ ] The structural proxy remains as an audited fallback and the audit says
      WHICH path elected the fuel.
- [ ] (2)(b): whether the global 1.10 cooling factor compounds with the
      per-zone 1.0 was MEASURED, not assumed, before any change.
- [ ] Existing pins moved knowingly: `test_audit_fixes.rb:97-108`, `:22-33`;
      `test_reference_hp.rb:23`, `:27-28`; `test_necb_reference.rb:185-190`.

### Phase 6 — water-side economizer
- [ ] The Phase-0 SDK gate ran in a scratchpad BEFORE any repo change, and a
      clean E+ sizing + week run was obtained with the HX in place.
- [ ] The QAQC checker no longer flags "NO economizer" on loops that now have
      one (`checker.rb:41-59`).
- [ ] 8.4.4.12 still `partial` (DX staging 5.2.2.8.(4)-(5) remains open), so
      `test_necb_energy_recovery.rb:174` still passes.
- [ ] Capability actually verified against the code text: 100% of the cooling
      load at OA wet-bulb ≤ 7 °C (evaporative) or dry-bulb ≤ 10 °C (sensible)
      — not merely "an HX exists".

### Final, once all phases land
- [ ] ONE `SWEEP_MODE=full` run; the resulting table replaces D-46's in
      `necb_decisions.md` with an explicit note of what it supersedes.
- [ ] `docs/NECB_GEM_COVERAGE.md` regenerated (`rake necb:coverage_doc`).
- [ ] `pending_review.md` deleted or emptied — a stale checklist is worse than
      none.
