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
