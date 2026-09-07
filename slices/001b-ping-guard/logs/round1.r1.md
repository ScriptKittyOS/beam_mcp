From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 1, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review && git write-tree
a42f1b1e82599b203df0afcaaa8639203fd663d7
```

Written to `/home/aylac/Projects/beam_mcp-wt/001b-review/logs-r1.tree`. Re-checked at the end of the review: `git write-tree` still `a42f1b1e82599b203df0afcaaa8639203fd663d7`, so the index did not move under me. Only untracked files present are `logs-r1.tree` and `logs-r2.tree`.

Spec fetched, not recalled, on 2026-09-06: `.../2026-07-28/basic/versioning`, `.../2026-07-28/changelog`, and `.../2025-11-25/basic/index`.

---

## 1. Is the chosen behaviour right? (A) yes; rejection of (B) holds; rejection of (C) is right on design but is **not** the MUST the record implies

**Severity: note (two sub-points), one non-blocking (1c).**

**(a) (A) is defensible, and I reach that independently.** The versioning page says "Every request declares the protocol version it is using in its `_meta` field" and "If the server does not implement the requested version ... it **MUST** respond with an `UnsupportedProtocolVersionError` listing the versions it does support", with the page's own example carrying `"supported": ["2026-07-28", "2025-11-25"]`, and "The client **SHOULD** select a mutually supported version from the `supported` list and retry the request." This server *does* implement `2025-11-25`, and says so twice — verified live, not read:

```
1. server/discover + _meta modern
  -> {"result":{"protocolVersions":["2026-07-28","2025-11-25"],...}}
18. _meta version = null
  -> {"error":{"code":-32022,"data":{"requested":null,"supported":["2026-07-28","2025-11-25"]},...}}
```
(`mix run` probe against the reviewed `server.ex`, full output below in §4.)

**(b) (B) is incoherent for *this* server, so its rejection holds.** Answering `-32022` to a `_meta` naming `2025-11-25` would be a response whose own `data.supported` field asserts support for the version the same response is refusing. The one sentence that could support (B) — "A request carrying modern per-request `_meta` is served statelessly according to this revision" — sits under *Backward Compatibility with Initialization-Based Versions*, in a bullet pair whose contrast is **stateless vs. session** ("An `initialize` request selects legacy semantics, scoped to the stdio process (stdio) or the session (HTTP)"). PLAN.md:137-145 reads it as fixing statelessness, not the revision. I agree, and I add the argument the PLAN does not make: under (B) the spec-prescribed retry loop is non-terminating *against this server's own advertisement*, which the spec cannot intend.

**(c) The rejection of (C) is right, but the record overstates its basis. Non-blocking.**
`slices/001b-ping-guard/FINDINGS.md:51-53` says the `2026-07-28` changelog item 8 MUST "is only coherent if an earlier-revision result omits it". That is an inference, presented adjacent to two verbatim quoted MUSTs. Two spec facts cut against reading it as normative:
- Changelog item 8's MUST is addressed to **clients** ("Clients **MUST** treat results from earlier-protocol servers that omit the field as `"complete"`"), not to servers, and it governs *omission*, not *emission*.
- `2025-11-25`'s own base-protocol page states of a result response: "The `result` **MAY** follow any JSON object structure." `_meta` is a reserved-but-permitted property in that revision. So shape (C) — keeping `resultType` and `_meta` `serverInfo` on a `2025-11-25` result — would have violated **no** normative requirement in either revision.

So (C) loses on honesty (it decorates a result with fields the declared revision does not define), not on conformance. (A) remains the right shape; the FINDINGS sentence should be softened to say so. No different shape is right.

---

## 2. Does the code do what the PLAN and CHANGELOG say?

### Finding 2.1 — **BLOCKING.** The moduledoc still states the rule this diff deletes

`lib/beam_mcp/server.ex:16-18` (unchanged by the diff; its truth-value was flipped by it):

> a request carrying per-request `_meta` is served statelessly under **the modern revision**, and an `initialize` request selects legacy semantics.

**Observed:** after this change a `_meta` naming `2025-11-25` is served under the **legacy** revision — that is the entire point of the slice. **Expected:** the module's published documentation says what the module does. This is the `@moduledoc`, i.e. the hexdocs front page for `BeamMCP.Server`; it is the highest-visibility statement of this rule in the package, and it now asserts the pre-fix behaviour. The inline clause comment (`server.ex:119-124`) and `README.md` were both updated; the moduledoc was missed.

This is exactly the defect class the slice exists to close. `FINDINGS.md:19-21` describes the bug as "the comment named `2026-07-28`; the code names no revision". Shipping a moduledoc that names the modern revision while the code no longer does is the same mismatch, one file up. `CONVENTIONS.md:8` — "each entry exists because something went wrong once" — and PLAN.md in-scope item 3 (documentation of the era rule) both put this inside the slice, not outside it.

```
$ sed -n '16,18p' lib/beam_mcp/server.ex
  It serves `2026-07-28` and `2025-11-25`, and tells them apart the way the specification says
  a dual-era server should: a request carrying per-request `_meta` is served statelessly under
  the modern revision, and an `initialize` request selects legacy semantics. A request naming
$ git diff base/main HEAD -- lib/beam_mcp/server.ex | grep -c '^@@ -1[0-9][0-9]'
1                       # the only hunk starts at line 116; the moduledoc is untouched
```

### Finding 2.2 — non-blocking. Two clause-ordering counterexamples falsify the newly-added README claim

`README.md:101-103` (new in this diff): "**A revision, not a carrier, decides the semantics.** ... Which revision the `_meta` *names* then decides **the method table and the result envelope**."

Both halves have a reachable counterexample, because `server/discover` (`server.ex:92`) and `initialize` (`server.ex:102`) are matched **before** the `_meta` clause (`server.ex:125`), and their patterns permit an extra `_meta` key:

```
# method table: `initialize` is removed in 2026-07-28, and README.md:99 says it is "at legacy only"
4. initialize + _meta modern (params protocolVersion 2026-07-28)
  resp     -> {"result":{"protocolVersion":"2026-07-28","capabilities":{...},"serverInfo":{...}},"id":1,...}
  shutdown?-> false   initialized?-> true

# result envelope: server/discover is MANDATORY in 2026-07-28 and its result carries neither decoration
1. server/discover + _meta modern
  resp     -> {"id":1,"jsonrpc":"2.0","result":{"capabilities":{...},"protocolVersions":[...],"serverInfo":{...}}}
```

Observed: a request declaring `2026-07-28` gets a successful `initialize` handshake claiming `2026-07-28` — a revision in which `initialize` does not exist — and it flips `initialized?` to `true`, i.e. a request that declared the *stateless* revision mutates session state. And a modern `server/discover` result carries no `resultType`, which changelog item 8 makes required on all results ("All results now carry a required `resultType` field"). Expected per the new README row at `README.md:96` and paragraph at 101-103: `resultType` and `_meta` `serverInfo` on every `2026-07-28` result.

**Both behaviours are pre-existing** (identical clause order at `base/main`) and are legitimately out of this slice's scope. What is *in* scope is that PLAN.md:151 puts README in scope precisely because it "currently states the intended rule and not the shipped one" — and the replacement text has the same property for two of the six methods the same page lists. Either qualify the paragraph ("except `server/discover` and `initialize`, which are matched before the `_meta` clause") or record the two counterexamples under "Out of scope, recorded rather than fixed". Neither is recorded now.

### Finding 2.3 — no defect. State threading through both new branches is correct

The brief asked specifically about `shutdown`. Measured, not reasoned:

```
6. shutdown + _meta legacy
  resp     -> {"id":1,"jsonrpc":"2.0","result":{}}
  shutdown?-> true   initialized?-> false
7. shutdown + _meta modern
  resp     -> {"result":{"_meta":{...serverInfo...},"resultType":"complete"},...}
  shutdown?-> true   initialized?-> false
12. exit (no id) + _meta modern
  resp     -> nil (no response)
  shutdown?-> true   initialized?-> false
```

The legacy branch (`server.ex:145`) returns the recursion's tuple whole, so `next` is propagated. The modern branch (`server.ex:138-139`) destructures and returns `next`. Correct in both.

**Note (not a finding):** `server.ex:139` passes the **pre-recursion** `state` to `modernise/2`, not `next`. Harmless today — `modernise/2` reads only `state.server_name`, which no handler mutates — but it is a latent trap if the server name ever becomes mutable. Cheap to change to `next`.

### Finding 2.4 — no undisclosed silent behaviour change

I enumerated every path the rewritten clause can take and compared before/after. The only behaviour deltas are (i) `ping` at legacy `_meta`, and (ii) the removal of the decorations for every method reaching the legacy branch — which the CHANGELOG covers with `ping` and `tools/list` as exemplars. `shutdown` and `tools/call` also lose their decorations (probes 6 and 8) and are not individually named, but they are instances of the stated rule, not separate changes. Errors were never modernised (`modernise/2` only matches `%{"result" => payload}`), before or after — verified at probes 9 and 16. Notifications (no `id`) never entered the clause, before or after — probe 10.

**Both CHANGELOG "before" strings reproduce exactly.** Not taken on trust — measured by reverting `server.ex` to `base/main` in an isolated copy:

```
=== BEFORE (server.ex = base/main) ===
ping + _meta 2025-11-25   -> {"error":{"code":-32601,"message":"Method not found: ping"},"id":1,"jsonrpc":"2.0"}
tools/list + _meta 2025-11-25 -> {"id":2,...,"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete","tools":[...]}}
=== AFTER (server.ex = reviewed) ===
ping + _meta 2025-11-25   -> {"id":1,"jsonrpc":"2.0","result":{}}
tools/list + _meta 2025-11-25 -> {"id":2,"jsonrpc":"2.0","result":{"tools":[...]}}
```

---

## 3. Are the new tests real? Yes — verified by mutation, two of the three

Method, per the brief: fresh directory created and verified empty (`entry count: 0`), populated by `git archive HEAD | tar -x` (index bytes, not worktree), `deps/`+`_build/` copied, `git init`. Nothing under `deps/` was mutated, so the `deps.compile --force` caveat does not apply. Mutation asserted applied before scoring:

```
--- diff line count: 42 (must be > 0)
=== confirm mutant server.ex == base/main:server.ex ===
0f649f35823983fbaa27822abd12a90cbbaaed9930d4f9e1b37df1b64922698c  -
0f649f35823983fbaa27822abd12a90cbbaaed9930d4f9e1b37df1b64922698c  .../mutant/lib/beam_mcp/server.ex
```

Control (unmutated copy): `36 tests, 0 failures`, `exit=0`.

Mutant (`lib/beam_mcp/server.ex` reverted to `base/main`, everything else at the reviewed index):

```
  1) test ... a ping declaring 2025-11-25 through _meta is answered
     test/beam_mcp/negotiation_test.exs:167
  2) test ... a result for a request declaring 2025-11-25 carries neither
     test/beam_mcp/negotiation_test.exs:186
12 tests, 2 failures
exit=2
36 tests, 2 failures    # full suite
```

Byte-for-byte the same two failures, with the same messages, as `slices/001b-ping-guard/logs/red.txt`. The tests are real and the recorded red is reproducible.

The **third** new test — `negotiation_test.exs:179`, "a 2026-07-28 result carries resultType and serverInfo `_meta`" — passes at `base/main`. It is a regression guard, not a red. That is fine and desirable; it is the source of the miscount in Finding 6.1.

---

## 4. Under-tested: `shutdown` through the new `@legacy_version` branch

**Severity: non-blocking.**

`negotiation_test.exs:43` — `defp send_msg(msg), do: state() |> Server.handle_message(msg) |> elem(1)` — **discards the returned state**. Every test in the file, new and old, throws the state away. So the new `@legacy_version` branch at `server.ex:142-145` returns the recursion's state tuple whole and **no test asserts that it does**. `shutdown` is the specific reachable input: it is the only request method that changes state, it reaches the new branch, and nothing covers it.

I verified the behaviour is correct (probe 6, above) — this is a coverage gap, not a bug. A one-line test that keeps `elem(0)` and asserts `Server.shutdown?/1` after a `shutdown` carrying legacy `_meta` closes it. Also uncovered but lower value: `tools/call` at legacy `_meta` (probe 8, correct), and the legacy branch's `-32601` for an unknown method (probe 9, unchanged).

Full probe output (18 inputs, run against the reviewed `server.ex`) is at `/tmp/claude-1000/-home-aylac-Projects-hacktui-hermes/775c8d71-6ac1-4653-8798-382001e76089/scratchpad/r1/`.

---

## 5. The gate — read per step, not by exit code

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review && ./tools/gate.sh; echo "gate exit=$?"
== beam_mcp gate ==
  format                     pass
  compile                    pass
  test                       pass
  credo                      pass
  reuse                      pass (17 commentable files)
  licence files              pass
Gate OK.
gate exit=0
```

All six lines read `pass`; no step printed `pass` while a `FAIL` line appeared elsewhere. Acceptance criterion 5 is met. Byte-identical to `slices/001b-ping-guard/logs/gate.txt`. Note that the `reuse` step derives its population from `git ls-files`, so my untracked `logs-r1.tree` is invisible to it and could not have skewed the `17` — which matches the archived count exactly.

---

## 6. Are the FINDINGS claims supported? Mostly yes; three counts are wrong

### Finding 6.1 — non-blocking. Three typed-fresh counts in FINDINGS.md are wrong

`CONVENTIONS.md:70` — "Counts are quoted from command output, never typed fresh." These three were not.

**(a) `FINDINGS.md:64`** — "Both new tests failed; the **ten** pre-existing tests passed, so the red is the **two** additions and not a broken file."

Observed: there are **three** new tests and **nine** pre-existing ones.
```
$ git show base/main:test/beam_mcp/negotiation_test.exs | grep -c '^\s*test '
9
$ grep -c '^\s*test ' test/beam_mcp/negotiation_test.exs
12
```
The sentence's arithmetic (10 + 2 = 12) is self-consistent and still lands on a true total, which is exactly why it survived. The correct statement is: three additions, two of which are red at `base/main` and one of which (`:179`) is green there as a regression guard.

**(b) `FINDINGS.md:104`** — "**Four** edits, each applied by a Python replace...". The table immediately under it has **six** rows.

**(c)** consequently `FINDINGS.md:113`/`114` list `mix.exs` and `CHANGELOG.md` rows that the "four" does not account for.

### Finding 6.2 — spot-checks that hold

Re-run by me, not taken on trust:
- `36 tests, 0 failures` (`logs/full-suite.txt`) — reproduced: control run, `exit=0`. ✔
- `12 tests, 0 failures` (`logs/green-negotiation.txt`) — reproduced. ✔
- `12 tests, 2 failures` (`logs/red.txt`) — reproduced by mutation, same two tests, same messages. ✔
- gate, six `pass` lines, `17 commentable files` (`logs/gate.txt`) — reproduced byte-identical. ✔
- "the pre-existing test at `negotiation_test.exs:145` was not edited" — true; it is now at `:160` and its body is unchanged (`git diff base/main HEAD -- test/` shows only additions, no `-` line in that describe block). Acceptance criterion 2 is met by an unmodified assertion. ✔

### Finding 6.3 — note. `logs/probe-after.txt` predates the `mix.exs` bump

`logs/probe-after.txt` line 3 reads `beam_mcp version: 0.1.1`, and its modern `tools/list` result carries `"version":"0.1.1"`. The reviewed tree's `mix.exs:7` is `0.1.2`, and `@server_version` is read from it (`server.ex:49`), so re-running the same probe now yields `0.1.2`. The log is a genuine command archive of a real intermediate state (fix applied, version not yet bumped), not a transcription — consistent with `CONVENTIONS.md:73-79`. But `FINDINGS.md`'s "## Green" section quotes it as the post-fix state without saying the version bump came after, and a reader diffing the log against the tree will find a version string that exists nowhere in the reviewed bytes. One sentence would close it. Same applies to the CHANGELOG's "Measured against `0.1.1`" block, which is accurate but is the pre-bump run.

### Finding 6.4 — note. PLAN fetch date is one day in the future

`PLAN.md:12` — "fetched on **2026-09-07**". Today is 2026-09-06. Probably a timezone or typo; recorded because a fetch date is the load-bearing part of the claim that the `2026-07-28` text was fetched rather than recalled. I independently re-fetched both pages today and every quoted line in `PLAN.md:85-108` matches the live text verbatim, so the substance is sound.

---

## Summary

The fix itself is correct, minimal, well-argued against the fetched spec, and genuinely demonstrated red-before-green by mutation. Shape (A) is the right shape and I reach that independently. State threading is right in both new branches; no silent behaviour change is undisclosed. The gate is green on every line.

One blocking item: the `@moduledoc` at `lib/beam_mcp/server.ex:16-18` — the module's published documentation — still states the pre-fix rule this diff deletes. That is a two-line edit in a file already in scope, and it is the same doc/code mismatch the slice was written to close.

VERDICT: changes required
