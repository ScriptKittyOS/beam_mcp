# Round 2 — mutation evidence for the header-read sweep

Ran in a copy, not the worktree: `$SCRATCH/mut/base`, a `cp -a` of the worktree with `_build`
and `.git` removed. Baseline there before and after the run: **98 tests, 0 failures**.

Harness: for each mutant, assert the pattern occurs exactly once, apply, assert the mutated
text occurs exactly once, run `mix test`, record failures **by test name**, restore. A mutant
whose pre-count is not 1 is reported as NOT APPLIED, never as a survivor. (SCR-259: a mutation
that never landed is discarded, not scored.)

## How the set of header reads was derived

Not listed — derived, and the derivation is repeatable:

    grep -n 'get_req_header\|req_headers' lib/beam_mcp/transport/http.ex

returns exactly three lines: the definition of `header_values/2`, the one call to it inside
`check_origin/2`, and the `mcp-param-` prefix sweep in `check_param_headers/3`. Every header
this module reads therefore goes through `header_values/2` or the sweep, and every comparison
is `Enum.all?` over all values. A fourth header added later inherits the behaviour instead of
needing a fifth finding.

One honest qualification: `check_origin/2` compares with `Enum.all?(origins, &(&1 in allowed))`
rather than `all_match?/2`, because its comparison is set membership against the host's allow
list, not equality against a body value. It reads through the same helper and applies the same
all-values rule; it does not share the comparison function, and its own mutant below is what
pins it.

## Mutants — one per header read

| # | mutant | result | killed by |
|---|--------|--------|-----------|
| 1 | `Origin`: `Enum.all?(origins, …)` → `Enum.all?(Enum.take(origins, 1), …)` | KILLED 1/98 | `Origin — a second, disallowed Origin is not ignored` |
| 2 | `MCP-Protocol-Version`: `header_values(…)` → `Enum.take(header_values(…), 1)` | KILLED 1/98 | `MCP-Protocol-Version — a second, unsupported version is not ignored` |
| 3 | `Mcp-Method`: call site → first-value-only variant | KILLED 1/98 | `Mcp-Method — a second, disagreeing method is not ignored` |
| 4 | `Mcp-Name`: call site → first-value-only variant | KILLED 1/98 | `Mcp-Name — a second, disagreeing name is not ignored` |
| 5 | `Mcp-Param-{Name}`: call site → first-value-only variant | KILLED 1/98 | `Mcp-Param-{Name} — a second, disagreeing value is not ignored` |

Mutants 3–5 mutate one call site each and add a scaffold function that drops all but the first
value of the named header. Each kills exactly one test, and a different one. That is the point
of running five mutants rather than one: a single shared mutant killed by a single test would
leave the other four reads unpinned while looking green.

## Mutants — the class, and the two MUSTs added this round

| # | mutant | result | killed by |
|---|--------|--------|-----------|
| 6 | `all_match?/2`: `Enum.all?` → `Enum.any?` | KILLED 3/98 | the `Mcp-Method`, `Mcp-Name` and `Mcp-Param-{Name}` multi-value tests |
| 7 | `check_param_headers/3` sweep disabled (validates nothing) | KILLED 3/98 | the multi-value param test and both `x-mcp-header` contract tests |
| 8 | `decode_header_value/1` base64 clause made unreachable | KILLED 1/98 | `an RFC-2047-style Base64 Mcp-Name is decoded before comparison` |
| 9 | 404 keyed on the `-32601` code again (attribute removed with it) | KILLED 1/98 | `an unknown tool is 200 with a JSON-RPC error, not 404` |

Mutant 6 kills three, not five: `Origin` and `MCP-Protocol-Version` do not route their
comparison through `all_match?/2` (membership, and a second supported-version check, respectively),
so they survive it and are pinned by mutants 1 and 2 instead. Reported rather than smoothed over,
because "the class mutant killed everything" would have been the false version of this table.

Mutant 9's first form changed only the `case` pattern and left `@method_not_found` defined but
unused, which `--warnings-as-errors` rejected: the mutant did not compile, so the suite never
ran and a compiler kill would have been scored as a test kill. Removing the attribute in the same
mutant made it a faithful revert; it then failed one test. Recorded because a mutant killed by
the compiler is not evidence that a test pins the behaviour.

## What still has no mutant

The multi-`Origin` fix landed in round 1 with no test at all — `Enum.all?` → `Enum.any?` survived
82/82. That is the finding this whole table answers: the fix was right and unpinned, so nothing
would have caught its removal. Mutant 1 is now the pin.

## Second batch — the crash class (r2's R2-1 and R2-2)

Same harness, same copy, baseline **101 tests, 0 failures** before and after.

| # | mutant | result | killed by |
|---|--------|--------|-----------|
| 10 | outer `rescue`/`catch` removed from `call/2` (and `crash_response/1` with it — the pre-round-2 state) | KILLED 1/101 | `a host authorize/1 that raises, throws or exits is answered, not left as a bare 500` |
| 11 | `param/2` fallback removed, so a non-map `"params"` is reached into | KILLED 1/101 | `a non-map params is refused, not reached into` |
| 12 | refusal message interpolates the raw body value again | KILLED 1/101 | `a non-scalar params.name is refused, not interpolated into a message` |
| 13 | `to_comparable/1` catch-all removed (`:unmatchable` → the value itself) | **SURVIVED**, and equivalent | — |

Two of these need saying rather than tabulating.

**Mutant 13 survived and I am not adding a test to kill it, because it is an equivalent mutant.**
Returning the raw value instead of `:unmatchable` still fails the comparison — a map never equals
a header string — so behaviour is identical. The clause looked like the protection and is not:
what actually stopped the crash was removing the body value from the refusal message, which is
mutant 12, and that one dies. Recording a survivor as equivalent with the argument for why is the
honest form; the alternative was writing a test that asserts an implementation detail so the table
could read all-killed.

**Mutant 10 was killed by one test, not two.** The latin-1 `Mcp-Name` test passes with the outer
rescue and without it: `Plug.Test` builds the conn in-process, so it does not reproduce the
socket-level failure the lane measured, where that request got **no response at all**. That test
documents the case; it does not pin it. The pin is the `authorize/1` crash test, and the socket
evidence stays the lane's.

Mutant 10 also needed `crash_response/1` deleted in the same mutation, for the same reason as
mutant 9: left behind it is an unused function, `--warnings-as-errors` rejects the build, and a
compiler kill would have been scored as a test kill.

## Note on `dispatch/3`'s inner rescue

It is now inside `call/2`'s and looks redundant. It is kept because it is not: it answers with
`message["id"]`, which is known by then, while `crash_response/1` answers with `id: nil` because a
crash before decoding has no id to use. Removing it would silently downgrade every dispatch-time
crash to an unidentifiable error response.

## Corrections to the round-2 table above

Two things in this file were wrong, both found by round 3, and both are the kind that make a
record read as stronger evidence than it is. They are corrected here rather than edited away.

**"One mutant per header read" was one mutant per header NAME.** `compare_versions/3` performs
*two* value comparisons on `MCP-Protocol-Version` — one against the body's `_meta`, one against
the supported set — and mutant 2 pinned only the first. A first-value-only mutant on the second
comparison **survived the entire suite**, and that branch is the only version check that runs on
a body carrying no `_meta`, which is every request that does not declare its era in the body. So
the round-2 headline was false in exactly the way the round-2 finding was: a set counted by the
names I had in mind rather than by what the code does. Round 3 makes both comparisons read every
value and pins the second one directly (mutant 18).

**The derivation grep was misreported.** This file and the code comment both said
`grep -n 'get_req_header'` returns "only `header_values/2` and the `mcp-param-` sweep". It does
not: the sweep does not call `get_req_header` at all — it reads `conn.req_headers` — and the grep
also matches the comment describing itself. The claim the argument actually needs is over two
patterns, `get_req_header\|req_headers`, and the honest statement of the result is: one
definition, one call site, one `req_headers` sweep, plus the comments that name them. A
completeness argument resting on a command whose output is quoted wrongly is not a completeness
argument.

## Round 3 — mutants for the round-3 fixes

Same harness and rules; baseline in the copy **126 tests, 0 failures** before and after.

| # | mutant | result | killed by |
|---|--------|--------|-----------|
| 14 | status-aware rescue reverted (swallow every exception again) | KILLED 1/126 | `it is re-raised rather than answered as -32603` |
| 15 | Base64 sentinel decoded for every header again | KILLED 1/126 | `Mcp-Method is NOT decoded` |
| 16 | round-trip check dropped, non-canonical Base64 accepted | KILLED 1/126 | `a non-canonical Base64 encoding is not accepted as a second spelling` |
| 17 | mirrored-parameter population no longer read from the schema | KILLED **8**/126 | the eight `Mcp-Param` tests |
| 18 | second version comparison reads only the first value | KILLED 2/126 | both `two comparisons` tests |
| 19 | nested annotation paths not walked | KILLED 1/126 | `an annotated property at a nested path is read at that path` |
| 20 | omitted-but-present-in-body no longer refused | KILLED 1/126 | `a header the schema requires and the client omits is refused` |
| 21 | integer compared as a string again | KILLED 1/126 | `an integer parameter is compared numerically` |
| 22 | notification with a lying `Mcp-Method` accepted again | KILLED 1/126 | `a notification WITH a lying Mcp-Method is still refused` |
| 23 | `@removed_in_modern` emptied | KILLED 1/126 | `initialize, notifications/initialized and ping are all method-not-found` |

**Mutant 17 needed three completions, not one.** Replacing the schema lookup orphaned the
`ToolCatalog` alias; removing that orphaned `annotations/1` and `annotations/2`. Each time,
`--warnings-as-errors` failed the build and the suite never ran, and each time the naive reading
of that is a kill. This is the third instance of the compiler-kill family in this slice, and it is
now a rule in `CONVENTIONS.md`. The completed mutant is killed by **eight** tests — the strongest
kill in the table, and it would have been recorded as a one-line compile failure.
