# legacy_pin — the parity oracle, pinned

The `openstudio-*` gem family's parity suites compare against the legacy
NECB/BTAP implementation in **this fork** of openstudio-standards. This
directory pins that oracle to ONE git revision, so the comparison target is
explicit and reproducible instead of "whatever the working tree holds".

- `REF` — the full SHA of the pinned oracle revision. **The single source
  of truth**: the Gemfile reads it, and the archetype-generation cache keys
  derive from it.
- `Gemfile` / `Gemfile.lock` — bundler wiring. The lock is COMMITTED
  (tbd/osut/topolys resolved reproducibly). `.bundle/config` shares the
  repo's `vendor/bundle`.

## Running a parity suite against the pin

```bash
BUNDLE_GEMFILE=/workspaces/openstudio-standards/legacy_pin/Gemfile \
  bundle exec ruby test/test_shw_parity.rb
```

Set `LEGACY_PIN_REQUIRED=1` to turn "oracle not bundled" from a skip into a
FAILURE (CI and verification runs should always set it — a skipped parity
gate is a green-but-vacuous gate).

## Bumping the pin (absorbing upstream)

1. Edit `REF` to the new fork revision (full SHA).
2. `BUNDLE_GEMFILE=legacy_pin/Gemfile bundle install` (re-resolves the git
   source; refresh the lock).
3. Run ALL parity suites with `LEGACY_PIN_REQUIRED=1` plus the archetype
   regeneration gates. Flipped assertions = the upstream change reached a
   compared behavior — attribute every one (the D-68 discipline) before
   accepting.
4. Commit `REF` + `Gemfile.lock` together with the attribution notes and
   any gem-side flips.

## Remotes

Default remote is the local repository (fast, offline). Outside the
monorepo — e.g. after the gems move to their own repo — set
`LEGACY_PIN_REMOTE=https://github.com/NatLabRockies/openstudio-standards.git`.

**Never** point the pin at the published `openstudio-standards` RubyGems
release: that is NREL's release line and does not carry this fork's
NECB/BTAP state.
