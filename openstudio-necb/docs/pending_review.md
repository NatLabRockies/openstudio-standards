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
- [x] The three test sites pinning the unconditional lighting warning were
      updated, not deleted: `test_exterior_and_reference.rb:61`, `:102`,
      `openstudio-necb/test/test_compliance.rb:85`.
      [READ] all three now assert step-scoped semantics
      (`w[:step] == :lighting_reference`) — the old assertions were ALSO
      satisfied by the manifest coverage warning on the same article, so they
      would have passed even if the conditional were broken; a new case
      `test_reference_lighting_daylighting_kwarg_silences_the_gap_warning`
      pins the `daylighting: true` side.
- [x] No behaviour changed by the truth-up itself — the Phase 0 diff is
      strings, one comment and one `unless daylighting` guard.
      [RAN] `ruby test/test_exterior_and_reference.rb` 8 runs 0 failures;
      `ruby test/test_data_integrity.rb` 5 runs 0 failures.
- [ ] STILL OPEN: reviewer to confirm the 8.4.4.13 gap string edit is the ONLY
      hvac change and that dropping (2)(c) is right
      ([READ] `efficiency.rb:617` `align_heat_pump_heating_capacity`,
      `:654` `align_staged_heat_pump`, both audited `8.4.4.13.(2)(c)`).

### Phase 1 — SHW part-load curve

**The phase premise was REFUTED — read D-53 before reviewing.** The plan called
the vendored cubic "wrong form, wrong coefficients". The coefficients quoted
for 8.4.5.9.(2) were correct, but the inference was not: the code curve is a
FUEL-RATIO curve and the EnergyPlus field is a DEGRADATION DIVISOR, related by
`PLF(x) = x / FHeatPLC(x)` (rational, so no exact polynomial exists). The cubic
is that transform's image. **The curve was therefore NOT replaced.** Review the
refutation, not just the diff.

- [x] The 8.4.5.9 quadratic (a=0.021826, b=0.977630, c=0.000543) was verified
      FUNCTIONALLY over a sampled PLR envelope, self-checking ≈1.0 at the
      rating point — not compared coefficient-wise. [RAN]
      `ruby openstudio-necb/scripts/necb_8_4_6_curve_probe.rb` →
      `8.4.6.9 SWH FHeatPLC EQUIVALENT — max dev 0.98% over PLR 0.25-1.0`;
      independent re-derivation table in D-53 (worst 1.47% at PLR 0.20).
- [ ] **Reviewer's own check:** confirm the article text retrieved
      independently agrees that `Fuel_partload = Fuel_design × FHeatPLC` is a
      fuel ratio and not an efficiency multiplier — the whole non-change rests
      on that reading. [READ] `mcp codes get_section('necb','8.4.5.9','2020')`
      and `('necb','8.4.6.9','2025')`.
- [x] Whether the curve legitimately applies to electric and instantaneous
      water heaters was decided from the article text ("Fuel-Fired Service
      Water Heater"), and the answer is stated in `how` rather than left as a
      silent skip. Electric = OUT (audited on every electric heater, not a
      silent branch); fuel-fired instantaneous = IN (was the one real gap;
      `efficiency.rb` early-returned before setting the curve).
- [ ] **Energy-affecting, unswept:** the instantaneous fix is the only
      behaviour change. It fires ONLY on heaters with tank ≤ 7.6 L or named
      `instantaneous`; the gem's own autosized reference tanks are far above
      that bound, so no archetype should move. **Verify that claim in the
      sweep** — if any archetype moves on Phase 1 alone, this reasoning is
      wrong.
- [x] `test_shw.rb:11` moved deliberately: the bare coefficient pin became a
      functional gate (`test_part_load_curve_is_functionally_the_code_fheatplc`)
      plus form/scope/article pins. `test_shw.rb`'s coverage-warning assertion
      still passes — closing (5) did NOT remove the last warning, because
      `6.2.2.1.` (partial), `6.2.3.-6.2.7.` (not_implemented) and
      `8.4.4.20.(3)-(4)` (still partial for (9)) all still warn.
- [ ] The `part_load_curve` builder now honours the ruleset's `form` and raises
      on a mis-shaped spec. Confirm no other caller passed a spec relying on
      the old assume-Cubic behaviour.

### Phase 2 — daylighting default ON
- [x] Runtime cost measured and recorded in D-51 (wall-clock before vs after).
      [RAN] whole week-run pipeline, twice per archetype: SmallOffice
      31.9 s -> 32.2 s (+0.9%), MediumOffice 32.6 s -> 33.2 s (+1.8%). The
      feared sweep blow-up does not happen.
- [x] Reference interior-lighting energy fell (the expected direction) on the
      archetype where controls are actually placed. [RAN] SmallOffice
      230.6 -> 158.3 kWh/wk (-31%), reference total -3.0%, percent-of-target
      91.4 -> 94.2 (STRICTER).
- [ ] **REVIEWER DECISION OWED: the flip is inert on 10 of 17 archetypes.**
      [RAN] `scratchpad/d51_placement.rb` — `placement: :necb_default` (the
      legacy-exact 4.2.2 selection, which excepts any space failing ANY single
      criterion, so window-only spaces are always excepted) yields ZERO
      eligible spaces on FullServiceRestaurant, HighriseApartment, LargeHotel,
      LargeOffice, LowriseApartment, MediumOffice, MidriseApartment,
      QuickServiceRestaurant, RetailStandalone, RetailStripmall. Whether the
      REFERENCE building should instead use `placement: :all` is unruled and
      was deliberately NOT decided during implementation. Expect ten unmoved
      buildings in the fleet sweep; that is this, not a regression.
- [ ] ONE stale string left deliberately untouched (Phase 2 was scoped out of
      openstudio-hvac): `reference_rules_{2020,2025}.json` article `8.4.4.5.` /
      `8.4.5.5.` still says "reference_daylighting (opt-in)". It is the HVAC
      manifest's cross-gem delegation note; someone with the hvac file open
      should change "opt-in" to "on by default (D-51)".
- [x] `test_compliance.rb:85` still meaningful now that the default flipped.
      [READ] it now asserts the D-51 ruling entry fired, stamped
      `reference building`, AND that the `:lighting_reference` "(5)-(12) NOT
      modeled" warning is absent. Note the old assertion would still have
      passed unchanged — the manifest coverage warning carries the same
      article — so it was strengthened, not merely moved.

### Phase 3 — DCV copy
- [x] DCV is read from the proposed's `controllerMechanicalVentilation` and
      applied to the REFERENCE controller — confirmed on a model that actually
      has DCV on. The fixtures do NOT have it, so
      `test/test_necb_dcv.rb#proposed` builds a PSZ proposed and switches DCV
      on before the transform. [RAN] `ruby test/test_necb_dcv.rb` → 8 runs,
      31 assertions, 0 failures.
      The freshness of the reference controller is proved, not assumed, by
      `test_peak_rate_method_is_not_copied`: the proposed is
      `Standard62.1VentilationRateProcedure`, the reference comes out `ZoneSum`
      with DCV **on** — only a rebuilt controller plus `apply_dcv` produces
      that pair.
- [x] Legacy's misspelled `'NECB_Defualt'` guard (L-13) was NOT ported.
      [RAN] `test_legacy_misspelled_sentinel_is_not_ported` greps the whole of
      `openstudio-hvac/lib/**/*.rb` for the string; empty.
      [READ] the legacy site is `necb_2011.rb:1932`.
- [ ] **REVIEWER DECISION OWED (the real judgement call in this phase):**
      D-54 copies the DCV FLAG always, but copies the `systemOutdoorAirMethod`
      only when it is itself a demand-control method (`IndoorAirQualityProcedure*`,
      `ProportionalControlBasedOn*`) and NOT when it is a peak-rate method
      (`ZoneSum`, `Standard62.1VentilationRateProcedure`), on the reading that
      peak rate is sentence **(1)**'s subject and the reference realizes (1)
      through the cloned DSOA under `ZoneSum`. If the reviewer reads (1)
      instead as "identical to whatever the proposed computed", VRP would have
      to be copied too and reference peak OA would move. Stated in D-54 rather
      than left implicit.
- [ ] **Scope caveat to confirm.** [READ]
      `get_section('necb','5.2.3.4','2020')`: the DCV that (2) points at is
      5.2.3.4's — enclosed vehicle spaces and commercial kitchen exhaust — not
      general occupant CO2 control. Models carry no marker separating a
      5.2.3.4-required DCV from a voluntary one, so the implementation copies
      whatever DCV the proposed carries. That direction is conservative
      (copying LOWERS reference ventilation energy → STRICTER target); confirm
      the reviewer agrees that is the right way to be wrong.
- [ ] **Energy-affecting, unswept.** Fires only where a proposed air loop has
      DCV on. The 15 archetypes this toolchain authors do not set it, so no
      archetype should move; **verify in the sweep** — if any does, this
      reasoning is wrong.

### Phase 4 — humidification
- [x] The pre-teardown over-count is fixed: humidifiers surviving on
      `:copy_proposed` loops no longer trigger the "not rebuilt" warning.
      [RAN] `test_humidifier_surviving_on_a_copy_proposed_loop_does_not_warn`
      — a residential FPFC MAU block (`:copy_proposed`, so its loop is never
      replaced) leaves the humidifier untouched and produces ZERO D-55
      warnings; the loop is audited `info` "retained on this reference loop".
- [x] Rebuilt humidifiers carry the SAME energy source as the proposed's, and
      a setpoint manager that actually controls them.
      [RAN] `scratchpad/d55_humidification_gate.rb` (both fuels, E+ sizing +
      January week, clean, unmet htg 1.75 h): gas proposed → reference
      Humidification **Natural Gas 0.58 GJ/wk, Electricity 0.00**; electric
      proposed → **Electricity 0.46 GJ/wk, Natural Gas 0.00**; Water 0.18 m³
      in both. Same moisture, different source — E+ OPERATES it, it is not
      merely present. The same gate runs in-suite as
      `test_rebuilt_humidifier_consumes_its_energy_source_in_energyplus`.
      Control provenance is pinned too: the humidistat is the PROPOSED's,
      surviving on the thermal zone (`test_rebuilt_humidifier_carries_a_working_control`),
      and the scheduled fallback reuses the proposed's own schedule object.
- [x] A test exists — the T8 warning was unpinned by anything.
      [RAN] `ruby test/test_necb_humidification.rb` → 9 runs, 57 assertions,
      0 failures, 0 skips.
- [ ] **REVIEWER: confirm the DIRECTION is acceptable.** Rebuilding
      humidification RAISES reference energy, i.e. makes the target more
      LENIENT than the previous silent-drop behaviour. D-55 argues note (1)
      presupposes it (it legislates the reference humidifier's energy source,
      which is meaningless if the reference has none), but this is the one
      place in the backlog where the fix moves the target the permissive way.
- [ ] **The no-control case is a judgement call.** Where the proposed has
      neither a zone humidistat nor a scheduled minimum-humidity setpoint, NO
      humidifier is built (warned, SHOUTED "INERT") rather than one built with
      an invented setpoint schedule. Confirm that is preferred over inventing
      a default RH setpoint.
- [ ] **Energy-affecting, unswept.** Fires only on proposeds that humidify.
      None of the 15 archetypes does, so no archetype should move; verify in
      the sweep.

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

## Reviewer items raised during implementation (2026-07-29)

- [ ] **D-51 is largely INERT and needs a ruling.** `reference_daylighting`
      uses `placement: :necb_default`, whose selection excepts a space failing
      ANY single 4.2.2 criterion (`daylighting.rb#necb_default_spaces`:
      `side_area <= 100 || side_ea <= 0.1 || sky_area <= 400 || sky_ea <=
      0.006`). A window-only space therefore always fails the skylight test
      (0 <= 400) and gets NO controls. Measured eligible spaces: **0 on 10 of
      17 archetypes**; nonzero only for SmallOffice 4/4, Hospital 8/153,
      Outpatient 4/76, SecondarySchool 2/45, PrimarySchool 1/25, SmallHotel
      1/67, Warehouse 1/3. So the default flip changes almost nothing, and ten
      unmoved buildings in the sweep must NOT be read as a regression.
      The open question: should the REFERENCE use `placement: :all` instead?
- [x] ~~BLOCKED on a codes-MCP ingestion gap~~ **RESOLVED 2026-07-29 — there is
      NO MCP gap and no issue was filed.** `4.2.2.6` is "Special Applications"
      and its text runs straight into `4.2.3. Exterior Lighting Power`, so
      Subsection 4.2.2 ENDS at 4.2.2.6: articles 4.2.2.7-4.2.2.10 do not exist
      in NECB 2020, and our audit string citing them is itself wrong. The real
      requirement is **4.2.2.1.(10)-(15)** — see **L-26**. This nearly became
      false premise #7; the refuting check was one `get_section` call.
- [ ] **RULING NEEDED (supersedes the D-51 inertness item above).** Our
      selection uses NECB 2011 area/effective-aperture criteria, ANDed, while
      NECB 2020 4.2.2.1.(10)/(13) uses INPUT-POWER thresholds (>=150 W
      sidelit, >=300 W primary+secondary, >=150 W toplit) gated by the space
      type's Table 4.2.1.6 control column, with (12)/(15) exceptions — and
      sidelighting and toplighting are INDEPENDENT requirements, not
      conjunctive. That is why D-51 is inert on 10 of 17 archetypes. Decide:
      implement the 2020 rule for the reference (and keep the 2011 port only
      behind the legacy parity gate), or keep parity and document the
      deviation. Fix the bogus `4.2.2.7.-4.2.2.10.` article citation either
      way.
- [ ] `openstudio-hvac` `reference_rules_{2020,2025}.json` articles
      `8.4.4.5.`/`8.4.5.5.` still say "reference_daylighting (opt-in)" —
      stale after D-51; outside the Phase 0 agent's scope.
- [ ] **Parallel-agent artifact:** `test_decisions_registry.rb` can fail
      spuriously while phases land concurrently (one agent cites an id another
      has not yet registered). Re-run it after ALL phases, not per-phase.
      Confirmed green after phases 0/1/2: 12 runs, 861 assertions.
- [ ] The three lighting warning assertions were previously satisfied by the
      MANIFEST coverage warning on the same article string, so they passed
      even with the conditional broken. Now scoped to
      `step == :lighting_reference`. Check no other assertion in the suite has
      the same weakness.
