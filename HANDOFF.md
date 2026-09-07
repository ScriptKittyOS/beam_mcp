# HANDOFF — beam_mcp, slice 002 (stateless Streamable HTTP), release 0.3.0

Rounds 4-7 complete. **Round 4's three publish blockers are closed, and nothing blocks a
publish.** Tag and publish are owner steps — never `mix hex.publish`, never push a tag.

## State

- Branch `slice/002-streamable-http`, HEAD **`bdb032f`**, tree **`450d9f7f`**.
- Gate green: format, compile, test, credo, optional deps, **docs**, reuse (24 commentable
  files), licence files. Every step line reads `pass`. `logs/gate-round7.txt`.
- **138 tests, 0 failures.** Was 126 at the handoff.
- Version `0.3.0`, unreleased. `0.2.0` is published and is not amended.

## What the four rounds produced

    8d4d8c8  integer header values compared as integers      round 4 blockers 1 and 2
    00b6242  a host tool's exception stays in the envelope    round 4 blocker 3
    c0036d3  the read-before-refusal measurement              round 4's open question
    dad94ee  every host call routed through one rule          round 5
    c2e3fdf  atom keys and the recompilation step, stated     round 5
    5bc49ad  round 5's anchors made able to move              round 6
    bdb032f  probe captured whole, mutants re-scored          round 7

**The pattern is worth reading before the next slice.** Rounds 1-4 each found a fix
reintroducing a defect. Round 5's fixes were correct and two of their test anchors could not
move — the suite reported them pinned and they were not. Round 6 fixed the anchors and got the
records about them wrong. Round 7 found no defect in `lib/` at all: both its blockers were
record-integrity defects. The failure keeps moving one level away from the code — defect, then
test, then record — and at each level the same three rules catch it: derive the population,
quote the count from output, capture the whole output.

`slices/002-streamable-http/FINDINGS.md` carries the round-by-round table.

## Owner decisions still open

1. **The pinning policy (SCR-266).** The README says `{:beam_mcp, "~> 0.3.0"}` and that is
   correct. Whether `~> 0.MINOR.0` is the *rule* while `0.x` breaks at the minor is undecided,
   and the release is the moment the recommendation ships.
2. **Should release notes ship in the tarball (SCR-269)?** They do now — `CHANGELOG.md` is in
   `files:` and in ex_doc `extras:`. Reversible before the tag.
3. **Sequencing.** `SECURITY.md`'s supported-versions table says `0.2.x — superseded`. That is
   true the moment `0.3.0` is on Hex and wrong for any window between merging to `main` and
   publishing. **Publish and merge together, or merge second.**
4. **Date the `[0.3.0]` heading** at tag time. It reads `unreleased`, correctly, until then.

## Known gaps, recorded rather than fixed

- **`fault_response/4`'s re-raise branch is unpinned.** Measured: the never-re-raise mutant
  survives. Detecting it needs a non-500 `:plug_status` exception from code that is not the
  host's, which now means the adapter's read path alone; `Plug.Test` produces neither shape.
  **Needs a Bandit-backed test.**
- **Pre-read refusals answer without `connection: close`**, so Bandit drops the connection and a
  pipelined second request goes unanswered. Pre-existing — it applies equally to the Origin
  `403`, the authorize `403` and the `405` — and it fails closed.
- **A host DATA fault loses the request id** where a host RAISE two lines earlier keeps it,
  because `annotations(spec.input_schema)` is read outside `host_call/1`. Measured table in
  `logs/probe-fault-ids.txt`. Moving that read inside `host_call/1` is mutant M13 and wants its
  own red.
- **`authorize/1` cannot read the body**, so body-signature auth is structurally impossible and
  fails as a hang rather than an error. Documented; the post-read hook is deferred to `0.4.0`.
- **`readme_claims_test.exs` does not deliver what `CONVENTIONS.md` asks.** The rule says every
  behavioural README claim is pinned; the file pins every claim *listed in it*, and nothing
  derives the claim set. Stated in that file's moduledoc. Closing it needs a mechanism or an
  owner decision to narrow the rule.
- Three FILE findings from round 4 are on the board: colliding `x-mcp-header` names (SCR-275),
  an `x-mcp-header` on a non-primitive property, and `ToolCatalog.fetch/2`'s `@spec` honesty.
  The last two could not be filed — the Linear workspace is at its free issue limit — and are
  recorded verbatim in a comment on SCR-253.

## To release

1. Merge to `main` (PR; the ruleset requires two green checks).
2. Date the `[0.3.0]` heading.
3. `mix hex.publish`, then tag `v0.3.0` signed — or tag first and publish immediately after.
   Note the GitHub ruleset targets **branches, not tags**, so a tag push is unprotected.
