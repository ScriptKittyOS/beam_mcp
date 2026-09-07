<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 003 — the three live 002 review findings, released as 0.3.1

**Written before any shipping code.** Release **0.3.1**, heading left `unreleased` — dating it is
the owner's step at tag time. Base `origin/main` at `31bcbff` (published `0.3.0`, tagged
`v0.3.0`). Worktree `/home/aylac/Projects/beam_mcp-wt/003-release-0-3-1`, branch
`slice/003-release-0-3-1`, its own `_build` and `deps`.

**Baseline measured before planning**, so every count below is a delta from a known tree:

    $ ./tools/gate.sh
    == beam_mcp gate ==
      format                     pass
      compile                    pass
      test                       pass
      credo                      pass
      optional deps              pass
      docs                       pass
      reuse                      pass (24 commentable files)
      licence files              pass
    Gate OK.

    $ mix test
    138 tests, 0 failures
    TEST_EXIT=0

Archived: `logs/gate-baseline.txt`, `logs/baseline-tests.txt`.

## 0. The original queue, verified independently — four items were already shipped

The coordinator's board queue named five items and measured four as satisfied. **I verified all
five myself against this worktree before accepting that.** I agree with the coordinator on every
one. Recorded here because "already done" is a claim like any other and the next reader should be
able to re-run it rather than trust it.

| item | claim | what I measured | verdict |
|---|---|---|---|
| SCR-269 | `CHANGELOG.md` in `mix.exs` `files:` | `mix.exs:53` — `files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE NOTICE LICENSES)`. Also **pinned**, not merely present: `readme_claims_test.exs:95-105` asserts `"CHANGELOG.md" in Mix.Project.config()[:package][:files]`, and `:399` asserts it again beside the `refute "CONVENTIONS.md" in files`. | shipped |
| SCR-266 | README requirement excludes the next break | `README.md:17` — `[{:beam_mcp, "~> 0.3.0"}]`. **And the owner's policy answer is already recorded as a pinned rule rather than as a correct string**, which was the coordinator's open question: `readme_claims_test.exs:129-149` derives `next_break = "#{major}.#{minor + 1}.0"` from `Mix.Project.config()[:version]` and refutes it, guarded on `major == 0` with a real `else` branch that moves the break to the major at `1.x`; `:174-216` then re-derives **every** requirement string the README offers by regex over the prose and holds each to the same policy. There is nothing left to record. | shipped, policy already pinned |
| SCR-271 | `Transport.Stdio` is `@moduledoc false` | `lib/beam_mcp/transport/stdio.ex:5-27` carries a 23-line `@moduledoc` documenting framing, the `Content-Length` read, the privilege argument and a worked `run/1` example. The gate's `docs` step passes with 0 warnings, so it is not hidden either. | shipped |
| SCR-261 | `ttlMs`/`cacheScope` on `tools/list` | `lib/beam_mcp/server.ex:194-195` emits both; `:92-93` takes them as host options defaulting to the non-permissive `0` / `"private"`. `http_test.exs:471-481` pins both the defaults and host-supplied values. | shipped |
| SCR-275 | colliding `x-mcp-header` names | `http.ex:533` `Map.put(acc, String.downcase(name), …)` and `:541` `Map.merge(acc, annotations(...))` are both still there. | **open** — now item (b) below |

**Two things I found while verifying that are NOT in this slice and are reported rather than
fixed**, since items 1-5 above are the coordinator's to close:

1. **The both-eras emission of `ttlMs`/`cacheScope` is deliberate, documented in a code comment
   (`server.ex:187-190`), and unpinned.** `grep -rn 'ttlMs\|cacheScope\|tools_ttl_ms' test/`
   returns five hits, all in `http_test.exs`, all on the modern-only HTTP path. I built the
   mutant that makes the fields modern-only (the legacy `_meta` branch strips them after
   `handle_message/2`) and reverted it before writing this plan; I did **not** score it, because
   the re-ranking removed SCR-261 from my queue while the mutant was on disk. What I can state is
   the derivation: no test constructs a `tools/list` at `2025-11-25` and asserts either field, so
   nothing in the suite can distinguish the two designs.
2. **It is not a documentation defect.** I checked the three places that could make it one.
   `README.md:24` says the fields are what `2026-07-28` *requires*, which is true and says nothing
   about legacy. `CHANGELOG.md:86-88` says the same. The README's era table (`:255-261`) is a table
   of *differences* between the eras, and a field present at both is not a difference, so its
   absence from the table is correct rather than misleading. **No sentence in either file is
   false.** The gap is an unpinned deliberate behaviour, not a wrong claim, and it belongs on the
   board rather than in a patch release.

**The slice is therefore smaller than the board suggested, and I say so plainly**: of the five
original items, one was open.

## 1. What this slice is, after the re-ranking

Four defects, all in `lib/beam_mcp/transport/http.ex`, all found by the 002 review lanes and all
filed rather than fixed at the time. Ordered as the owner ranked them.

## 2. (a) and (b) — the owner's explicit question, answered

> *"Your PLAN must state which of (a) and (b) you fix first, and whether they share a fix."*

**They share a fix, and (a) goes first.**

They are the same defect wearing two schemas. In both, a host writes an `x-mcp-header` annotation
that the `2026-07-28` transport specification forbids; in both, this transport accepts the invalid
definition **silently**, advertises the annotation to clients through `tools/list`, and then
produces a wrong runtime outcome that names the wrong party. The two forbidden shapes are two
MUSTs the module already quotes in its own comments:

    "x-mcp-header MUST only be applied to parameters with primitive types
     (integer, string, boolean)"            -- quoted at http.ex:439-441
    "x-mcp-header values MUST be case-insensitively unique"
                                            -- quoted at http.ex:596-598

Both quotes sit beside code that assumes the MUST holds and does not check it. That is one
mechanism missing, not two:

- **(a)** `value_matches?/2`'s catch-all (`http.ex:443`) returns `false` for a map, a list or a
  float, so an annotated non-primitive can never match. Both branches of `check_each_param/4`
  close: omit the header and it is *"required: the body carries a value to mirror"*; send one and
  it *"does not match the corresponding request body value"*. The tool is permanently uncallable
  and **the `400` blames the caller for the host's schema**.
- **(b)** `annotations/2` accumulates into a map keyed by `String.downcase(name)`
  (`http.ex:602-616`), so `Dup` and `DUP` collapse to one entry — `Map.put` loses the sibling and
  `Map.merge(acc, annotations(subschema, …))` lets a nested annotation overwrite an outer one.
  One annotated property is then **never checked at all**, and which one survives depends on map
  iteration order.

**The shared fix.** The annotation set is derived from the tool's `inputSchema` — the authority,
per `CONVENTIONS.md`'s *"deriving from attacker-controlled input is not deriving a population"* —
and that same derivation is where its validity is decided. An annotation set that violates either
MUST is a **host fault**, answered exactly as this module already answers a host catalog that
raises: `500`, `-32603` `Internal error`, with the diagnosis in `Logger.error` naming the tool and
the offending annotation. No detail reaches the caller.

Two consequences, both deliberate:

- **The caller stops being blamed for the host's bug.** (a)'s `400` becomes a `500`, which is the
  honest status: the request was well-formed and the server is misconfigured.
- **(b) stops failing open.** An unenforceable annotation set refuses rather than silently
  enforcing a subset of what `tools/list` advertised.

**Why not at `init/1`, which is what lane s1 proposed for both.** I measured the cost and it is
not acceptable. `init/1` cannot enumerate the catalog, because `Plug.Router.forward/2` — the
mounting form this package's own README documents at `README.md:121-139` — calls the target plug's
`init/1` **at the host's compile time**, so `catalog.all()` would run during the host's build,
before its application, its config and anything the catalog reads are started. That is the same
family as round 3's finding that `Code.ensure_loaded?` in `init/1` rejected a valid catalog living
in the host's own project: `init/1` runs somewhere the host's world does not exist yet. Deriving
at the point of use costs one map walk per `tools/call` on a schema this module already walks.

**Order, and why it is not arbitrary.** (a) is ranked higher by the owner and it is also the one
that needs the plumbing: it introduces the "an invalid annotation set is a host fault" path
through `mirrored_params/2`. (b) is then one predicate on the set that path already derives. Two
commits, each with its own red, because they answer two different MUSTs and a reader auditing
either should find one commit.

**Scope limit, stated rather than discovered later.** (a) refuses an annotation whose subschema
**declares** a non-primitive `"type"`. A property with no declared `"type"` cannot be judged from
the schema, so it is left alone and keeps today's behaviour. Refusing it would be judging the host
on the caller's value, which is the wrong side of the boundary and would turn a caller sending a
wrong-typed value into a host fault. The residual gap is recorded, not closed.

## 3. (c) — the lost request id, and the anchor it costs

**The defect, measured, not reasoned.** `slices/002-streamable-http/logs/probe-fault-ids.txt`
already carries the table:

    host tool raises (dispatch/3)                  500  -32603  id=4242
    host tool_catalog RAISES (header validation)   500  -32603  id=4242
    host tool_catalog returns a malformed spec     500  -32603  id=nil
    host authorize/1 raises                        500  -32603  id=nil

Row 3 is the defect: `mirrored_params/2` calls `ToolCatalog.fetch/2` **inside** `host_call/1` and
then reads `spec.input_schema` and walks it **outside**, in the `with` body (`http.ex:582-583`).
A host catalog that *raises* keeps the id; the same host catalog returning *malformed data* — a
plain map where a `%ToolSpec{}` was promised — raises `KeyError` one line later, escapes to
`call/2`'s outer rescue, and answers `id: null`. One host bug, two envelopes, decided by which
line it lands on. Row 4 is **not** a defect and is not touched: `authorize/1` runs before the body
is read, so there is genuinely no id to echo.

**The fix** is M13 from `logs/mutation-round7.txt`, applied as a fix rather than scored as a
mutant: the spec read and the annotation walk move inside `host_call/1`.

**M13 is its own red, and this is the part that needs saying.** The reason M13 exists as a mutant
is that `http_test.exs:1160-1191` — *"an exception with no status of its own, raised outside
host_call/1, keeps the envelope"* — **asserts `body!(conn)["id"] == nil`**, and its own comment
says in terms that moving this read inside `host_call/1` would reroute the test and silently
disarm the mutant it exists to kill. So the red for (c) is that assertion inverting: the test
that today demands `id == nil` is the test that must demand `id == 4242`.

**And that anchor is load-bearing for something else, which I am not going to lose quietly.**
`fault_response/4` is reached from exactly one place — `call/2`'s rescue (`http.ex:199`);
`dispatch/3`'s rescue goes to `host_fault/5` instead (`http.ex:734-737`). The `BadSpecCatalog`
test is therefore the **only** thing in the suite that reaches `fault_response/4`'s answer branch,
and (c) removes the path it uses. Fixing (c) without replacing it would leave the always-re-raise
mutant — which serves a bodyless `500`, the exact failure this module exists to avoid — unpinned,
which is round 5's failure shape exactly.

So (c) is **two things in one commit and they cannot be split**: move the read, and re-anchor
`fault_response/4`'s answer branch on a path that survives the move. I have one candidate and it
is a measurement, not a plan: invalid UTF-8 bytes in `MCP-Protocol-Version` are echoed back in the
refusal's `data.requested` (lane s1 named that reflection), and `Jason.encode!` on invalid UTF-8
raises inside `send_json/3` in `handle/2`'s `else` — outside every inner rescue. **I will measure
whether that path is live before relying on it.** If it is, it is also a second finding — a caller
turning a `400` into a `500` — which I will report rather than fold in. If it is not, I will say
so and the commit will re-anchor by driving `call/2` with an opts map `init/1` did not build,
flagged to the review lanes as the weaker of the two.

**If neither anchor survives review, (c) does not ship.** A fix that trades a real defect for an
unpinned branch is the trade this repository has spent three rounds learning not to make, and I
will report rather than take it unilaterally.

## 4. (d) — pre-read refusals answer without `connection: close`

Measured by round 6 lane s3 and recorded in `slices/002-streamable-http/FINDINGS.md`:

    ok authorize (baseline, 200)              second-request-answered=True
    authorize raises -> 500                   second-request-answered=False
    catalog raises (after read_body) -> 500   second-request-answered=True

A refusal that fires before `read_body_bounded/1` answers on a conn with an unread body. Bandit
then drops the connection, and it drops it **without saying so** — no `Connection: close` — so a
client that pipelined a second request loses it silently instead of learning the connection ended.
`read_body_bounded/1`'s own `413` already calls `close_after/1` (`http.ex:331`); the three
refusals in front of it do not.

**The population is derived structurally rather than listed**, per `CONVENTIONS.md`'s "every place
a mechanism reads the same kind of input is one mechanism". Today's set is the Origin `403`, the
`405`, and `authorize/1`'s `403`/`500`/contract-violation `403` — but naming five sites is how the
fourth header read got missed. Instead `handle/2` splits at the body read: everything refused
*before* it is answered through one `send_json(close_after(conn), …)`, so a step added in front of
`read_body_bounded/1` later inherits the behaviour without needing a new finding.

**The red is Bandit-backed**, which this suite has never had and which two recorded gaps in
`slices/002-streamable-http/FINDINGS.md` say is the missing instrument. A real listener on a real
socket, one connection, two pipelined requests: today the refusal carries no `connection: close`
and the second request is never answered; after the fix the refusal says the connection is ending.
**What the fix does not do is get the second request answered** — it cannot, and I will not claim
it does. Reading the body of a caller we have already refused is worse than closing on them.
The control in the same test is an ordinary `200`, which must keep the connection and must answer
the second request, so the test can distinguish "closes correctly" from "closes always".

## 5. Order, and one commit does one thing

    1  (a)  an x-mcp-header on a non-primitive property is a host fault      red: a FLOAT annotation
    2  (b)  colliding x-mcp-header names are a host fault                    red: Dup / DUP
    3  (c)  the spec read and annotation walk move inside host_call/1        red: M13 / the malformed spec
    4  (d)  a refusal before the body read signals connection: close         red: Bandit-backed pipelining
    5       README and CHANGELOG for 1-4                                     every claim pinned
    6       0.3.1 in mix.exs, CHANGELOG [0.3.1] unreleased

Each red is archived by the command that produced it — `… 2>&1 | tee logs/<name>.txt` — before its
fix exists, per `CONVENTIONS.md`'s verbatim-archive rule. Commits 1-4 each carry their red output
in the message. `git commit -s` on every commit; no tool-attribution trailers.

## 6. The README moves in this slice, because behaviour moves in it

`CONVENTIONS.md` is explicit that the README moves with the behaviour and that every behavioural
claim in it is pinned in `test/beam_mcp/readme_claims_test.exs`. Three claims change:

1. An `x-mcp-header` annotation the specification forbids is a **host** fault — `500`, logged,
   with nothing about it in the response — not a `400` blaming the caller. (a) and (b).
2. A refusal issued before the body is read ends the connection and says so. (d).
3. A host catalog returning a malformed spec answers inside the envelope with the request's id.
   (c) — CHANGELOG only unless a reviewer argues it is a README-level claim; it is a property of
   the error envelope rather than of the interface a host wires.

Each of 1 and 2 gets a test in `readme_claims_test.exs` that quotes the sentence **and** exercises
the behaviour, not a `claims/1` quote alone. A quote-only pin catches a sentence that moves and
misses a sentence that becomes false, which is the gap that file's own moduledoc records.

## 7. Acceptance criteria

1. Four reds demonstrated and archived by the command that produced them, before their fixes.
2. A host annotating a `number` property gets `500` and a log naming the tool; the caller's body
   is not in the response. The same for an annotated `object` and an annotated `array`.
3. `Dup`/`DUP` on two properties gets `500` and a log; neither property is served unchecked.
4. A catalog returning `%{name: :echo}` answers `500` `-32603` **with the request's id**.
5. `fault_response/4`'s answer branch is still pinned after (c), demonstrated by mutation, or
   (c) does not ship.
6. A pre-read refusal carries `connection: close` against a live Bandit listener; an ordinary
   `200` on the same listener does not, and its pipelined second request is answered.
7. Every mutant in `logs/mutation.md` is asserted **applied** before it is scored, and a survivor
   is recorded as a survivor with the argument for why.
8. `./tools/gate.sh` exits 0 with **every step line reading `pass`**, read as lines and not as an
   exit code.
9. Version `0.3.1` in `mix.exs`; `## [0.3.1] — unreleased` in `CHANGELOG.md`; `0.3.0`'s section
   not amended.
10. A PR against `main`, not merged, with every check's conclusion read from the jobs API.

## 8. Out of scope, named so it is not folded in

- The `fault_response/4` **re-raise** branch pin and `ToolCatalog.fetch/2`'s `@spec` honesty —
  the owner excluded both.
- SCR-269, SCR-266, SCR-271, SCR-261 — verified shipped in §0, the coordinator's to close.
- The unpinned both-eras `ttlMs`/`cacheScope` emission (§0.1) — reported for the board.
- Anything under `tools/`, `.githooks/` or `.github/`. If a fix here wants a gate step I stop and
  report rather than reaching into subagent "gate"'s files.

## 9. Review

Per `slices/002-streamable-http/PLAN.md` §6 and the owner's three-round cap: **two review lanes
plus a security lane**, scoped to the shipped artefact — `lib/`, `test/`, `README.md`,
`CHANGELOG.md`, `mix.exs`. Findings about slice records are filed, not blocking. Each lane records
the tree hash it read. I do not review my own diff and I do not commit on a changes-required
verdict.

Lanes are briefed on the failure pattern `slices/002-streamable-http/FINDINGS.md` records rather
than on the diff alone: across seven rounds the failure moved one level away from the code each
time — defect, then test anchor, then record. **Lanes are told to score anchors by mutation and
not to read a test and agree with it**, and (c)'s anchor replacement is named to them as the
specific place this slice is most likely to reproduce that pattern.
