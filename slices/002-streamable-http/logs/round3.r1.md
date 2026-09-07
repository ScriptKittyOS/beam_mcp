# Round 3 — review lane r1 (correctness and test quality)

Tree read: `ebaaed0d918fed52e20af9031a1a8a71158bd3c9` (`git rev-parse HEAD^{tree}`, matches the
brief; recorded in `logs/round3.r1.tree`).

Scope: `git diff a5cfb67b8a8854714cde36522292c9fc57e96d6a HEAD` — 13 files, 1845 insertions.

**VERDICT: changes required**

All 13 recorded mutants reproduced exactly as recorded — counts and killing test names. The
problems are not in the table; they are in what the table does not cover, in one new code path
that does not survive a real host, and in two places where the record misdescribes its own
derivation.

---

## Method

All probes ran in a copy, never in the working tree:
`cp -a` of the worktree to
`/tmp/claude-1000/-home-aylac-Projects-hacktui-hermes/775c8d71-6ac1-4653-8798-382001e76089/scratchpad/lane-r1`,
with `.git` and `_build` removed (`git init` re-run inside the copy only so
`tools/probe_optional_deps.sh`, which calls `git rev-parse --show-toplevel`, resolves to the copy).
Harness at `$SCRATCH/mut/harness.py`: for each mutant it asserts a pre-count of exactly 1 for
every pattern, applies, asserts the mutated text is present, runs `mix test`, records failures by
name, restores, and re-asserts the restore. A pre-count other than 1 is reported NOT APPLIED and
never scored. A run with no `N tests, M failures` line is reported COMPILE ERROR and never scored
as a kill or a survivor.

Baseline in the copy, before and after the whole run: **101 tests, 0 failures**. Source verified
byte-identical to the worktree afterwards (`diff` clean). The working tree's index was never
touched; `git write-tree` still yields the tree above.

`mutation.md`'s first batch was measured at 98 tests, the second at 101. The current tree is 101,
so my counts read `/101` throughout. Kill *counts* are what I compare.

---

## The 13 recorded mutants, re-run

| # | mutant | recorded | my re-run | killing test names agree? |
|---|--------|----------|-----------|---------------------------|
| 1 | `Origin`: `Enum.all?(origins, …)` → first value only | KILLED 1/98 | **KILLED 1/101** | yes — `Origin — a second, disallowed Origin is not ignored` |
| 2 | `MCP-Protocol-Version`: `header_values(…)` → `Enum.take(…, 1)` | KILLED 1/98 | **KILLED 1/101** | yes — `MCP-Protocol-Version — a second, unsupported version is not ignored` |
| 3 | `Mcp-Method` call site → first-value-only scaffold | KILLED 1/98 | **KILLED 1/101** | yes — `Mcp-Method — a second, disagreeing method is not ignored` |
| 4 | `Mcp-Name` call site → first-value-only scaffold | KILLED 1/98 | **KILLED 1/101** | yes — `Mcp-Name — a second, disagreeing name is not ignored` |
| 5 | `Mcp-Param-{Name}` call site → first-value-only scaffold | KILLED 1/98 | **KILLED 1/101** | yes — `Mcp-Param-{Name} — a second, disagreeing value is not ignored` |
| 6 | `all_match?/2`: `Enum.all?` → `Enum.any?` | KILLED 3/98 | **KILLED 3/101** | yes — the `Mcp-Method`, `Mcp-Name` and `Mcp-Param-{Name}` multi-value tests, exactly those three |
| 7 | `check_param_headers/3` sweep disabled | KILLED 3/98 | **KILLED 3/101** | yes — the multi-value param test and both `x-mcp-header` contract tests |
| 8 | `decode_header_value/1` base64 clause made a no-op | KILLED 1/98 | **KILLED 1/101** | yes — `an RFC-2047-style Base64 Mcp-Name is decoded before comparison` |
| 9 | 404 keyed on `-32601` again (+ attribute removed) | KILLED 1/98 | **KILLED 1/101** | yes — `an unknown tool is 200 with a JSON-RPC error, not 404` |
| 10 | outer `rescue`/`catch` removed from `call/2` (+ `crash_response/1`) | KILLED 1/101 | **KILLED 1/101** | yes — `a host authorize/1 that raises, throws or exits is answered…`, and **only** that one; the latin-1 test does not fire, as recorded |
| 11 | `param/2` fallback removed, non-map `params` reached into | KILLED 1/101 | **KILLED 1/101** | yes — `a non-map params is refused, not reached into` |
| 12 | refusal message interpolates the raw body value again | KILLED 1/101 | **KILLED 1/101** | yes — `a non-scalar params.name is refused, not interpolated into a message` |
| 13 | `to_comparable/1` catch-all → the value itself | SURVIVED (equivalent) | **SURVIVED** | n/a — equivalence argument checked below and holds |

**13/13 reproduced.** No mutant was NOT APPLIED; every pattern matched exactly once.

### The compiler-kill claim, verified — and one case the record misses

The record says mutants 9 and 10 needed a companion deletion or the build would fail under
`--warnings-as-errors`, and that a compiler kill would have been scored as a test kill. Both are
true, and I reproduced them by deliberately leaving the companion behind:

- **9a** (`@method_not_found` left defined): `warning: module attribute @method_not_found was set
  but never used` → `Compilation failed due to warnings while using the --warnings-as-errors
  option`. No suite ran.
- **10a** (`crash_response/1` left defined): `warning: function crash_response/1 is unused` →
  same failure.

`mix.exs:14` sets `elixirc_options: [warnings_as_errors: true]`, so this applies to `mix test`,
not only to the gate's `mix compile` step. The record's caution is correct.

**But mutant 7 is a third instance the record does not name.** Disabling the sweep orphans
`argument/2`, which nothing else calls:

- **7a** (sweep disabled, `argument/2` left behind): `warning: function argument/2 is unused` →
  compilation failed. Not a survivor, not a kill — no evidence at all.

The recorded KILLED 3 for mutant 7 is right, so the *result* stands; the record's list of mutants
that needed a faithful companion deletion is incomplete. See finding **L-3**.

### Mutant 13's equivalence argument — sound, with a dependency worth writing down

The argument holds. `to_comparable/1`'s return is used in exactly two places:
`check_named/4:407` (as `expected`, consumed only by `all_match?/2:347`) and
`check_protocol_version/3:452`. `all_match?/2` compares `expected` against
`decode_header_value(&1)`, and both clauses of `decode_header_value/1`
(`http.ex:331` and `:344`) return a binary. The catch-all's inputs, after `Jason.decode/1`, can
only be a list or a map. Neither a list, a map, nor `:unmatchable` can `==` a binary, so both
versions refuse identically. In `compare_versions/3:473` the only test on the value is
`not is_nil(body_version)`, and neither a list/map nor `:unmatchable` is `nil`. Equivalent.

Two things the record could add. First, the equivalence is *contingent* on
`decode_header_value/1` returning a binary; if a future clause returned an atom, `:unmatchable`
would start mattering and mutant 13 would still survive, so nothing would say so. Second, the
clause is not entirely unpinned — I ran **13a**, deleting the catch-all outright rather than
changing its return:

    13a: to_comparable/1 catch-all clause DELETED  →  KILLED 1/101
         killed by: a non-scalar params.name is refused, not interpolated into a message

so the function's *totality* is pinned (a list body value would otherwise raise
`FunctionClauseError` and become a 500); only its return *value* is free. That is a more
precise statement than "survived, equivalent" and it is worth having in the record.

---

## HIGH

### H-1 — `init/1`'s `Code.ensure_loaded?/1` makes the Plug uncompilable for a host whose catalog is in the same project

`lib/beam_mcp/transport/http.ex:142-143` (new in this delta):

    unless is_atom(catalog) and catalog != nil and Code.ensure_loaded?(catalog) and
             function_exported?(catalog, :all, 0) do

`init/1` runs at **compile time** under Plug's default `init_mode` — the moduledoc says so itself
at `http.ex:42-46`. `Code.ensure_loaded?/1` does not wait for a module that the parallel compiler
is still working on; `Code.ensure_compiled/1` is the function that does. So a host writing the
ordinary shape — `plug BeamMCP.Transport.HTTP, tool_catalog: MyApp.Catalog, …` in a
`Plug.Builder`/`Plug.Router` module, with `MyApp.Catalog` in the same project — cannot compile.

Observed. Throwaway consumer project at `$SCRATCH/inittest`, depending on the copy by path, with
a valid catalog (`def all, do: []`, `@behaviour BeamMCP.ToolCatalog`):

    $ mix compile
    ==> host_probe
    Compiling 2 files (.ex)

    == Compilation error in file lib/a_router.ex ==
    ** (ArgumentError) BeamMCP.Transport.HTTP requires a :tool_catalog option: a module
    implementing the BeamMCP.ToolCatalog behaviour, that is, exporting all/0.

    Got: HostProbe.Catalog

        (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:144: BeamMCP.Transport.HTTP.init/1
        (plug 1.20.3) lib/plug/builder.ex:358: Plug.Builder.init_module_plug/4
        ...
    exit=1

Expected: compiles, because `HostProbe.Catalog` *is* a module exporting `all/0`. Observed: an
`ArgumentError` naming the correct module as invalid, at build time, with a message that tells the
host to fix something that is not wrong. This is the same failure class as the bug the guard at
`http.ex:10` exists to prevent — a check that is correct in this tree and wrong in a consumer's —
and the delta added it without a consumer-side probe, even though it added
`tools/probe_optional_deps.sh` for exactly that class in the same diff.

Fix — one line, verified:

    match?({:module, _}, Code.ensure_compiled(catalog)) and

With that change the consumer project compiles (`exit=0`) and the delta's own init test is
unaffected: `mix test test/beam_mcp/transport/http_test.exs` → **51 tests, 0 failures**. `Enum`,
`true`, `"MyApp.Catalog"` and `:not_a_module` are all still rejected, because
`function_exported?/3` and the `is_atom` guard do that work.

Worth adding to `tools/probe_optional_deps.sh` (or a sibling): the consumer project already exists
there; adding a `Plug.Builder` module that plugs the transport with a same-project catalog would
have caught this before the round.

### H-2 — one header read is *not* pinned as all-values, which is the exact claim `mutation.md` makes

`mutation.md`'s headline is "13 mutants, one per header read, proving each read is individually
pinned by a test", and the CHANGELOG repeats it: *"Every header is validated in all of its values,
not the first … one mutant per header proving each is pinned."*

`compare_versions/3` has **two** value comparisons on the `MCP-Protocol-Version` header, not one:

    http.ex:473   not is_nil(body_version) and not all_match?(values, body_version) ->
    http.ex:477   not Enum.all?(values, &(&1 == @modern_version)) ->

Recorded mutant 2 pins the *first* one only. Line 477 is a separate all-values read and nothing
pins it:

    N3: `not Enum.all?(values, &(&1 == @modern_version))`
        -> `not (List.first(values) == @modern_version)`
        SURVIVED | 101 tests, 0 failures

This is not an unreachable branch. Line 477 is the branch a request takes whenever the body has no
`_meta`, which is legal and normal — `do_dispatch/3:520` injects `_meta` precisely because a body
may omit it. Measured on the unmutated tree (probe `D1`), body
`{"jsonrpc":"2.0","id":1,"method":"tools/list"}` with headers
`mcp-protocol-version: 2026-07-28` **and** `mcp-protocol-version: 1999-01-01`:

    D1 (no _meta, dup version): status=400
      {"error":{"code":-32022,"data":{"requested":"2026-07-28","supported":["2026-07-28"]},
       "message":"Unsupported protocol version"},"id":1,"jsonrpc":"2.0"}

So the code is correct today and refuses the second value. Under N3 it would accept and serve the
request, and the suite would stay green — the identical smuggling shape (satisfying value first,
hostile value second) that mutants 1–5 exist to close, on the one header that carries two reads.

Fix: add a test sending duplicate `MCP-Protocol-Version` values on a body with **no** `_meta`, and
assert `-32022`; then add the mutant to the table. The recorded mutant 2 also deserves a note that
it pins the body-match branch, not the version-support branch (see **L-1**).

---

## MEDIUM

### M-1 — the notification exemption is new, relaxes a previously-enforced MUST, and no test touches it

`http.ex:366-370` (new in this delta):

    defp check_method_header(conn, message, id) do
      if Map.has_key?(message, "id"),
        do: check_named(conn, "mcp-method", message["method"], id),
        else: :ok
    end

At the round-2 reviewed tree the equivalent line was unconditional
(`a5cfb67:lib/beam_mcp/transport/http.ex:273`, `check_standard_header(conn, "mcp-method",
message["method"], id)`). The delta introduces the exemption. Nothing pins it:

    N1: `if Map.has_key?(message, "id"),` -> `if is_map(message),`  (exemption removed)
        SURVIVED | 101 tests, 0 failures

The suite *has* a notification test — `test/beam_mcp/transport/http_test.exs:462`, "a notification
gets 202 and no body" — but it calls `post/1` with default headers, and `std_headers/1:52-54` adds
`{"mcp-method", "notifications/initialized"}` from the body whenever `body["method"]` is present.
So the one test that reaches the notification path supplies the very header the exemption exists to
waive, and the exemption branch is never executed by any test. That is a test passing without
exercising the behaviour it appears to cover.

The behaviour it waives is observable (probe `D3`/`D3b`, unmutated tree). Same body, same headers,
the only difference being the `"id"` key:

    D3  (no "id", method tools/call, Mcp-Method: tools/list): status=202 body=""
    D3b (with "id", identical otherwise):                     status=400 -32020
        "mcp-method header does not match the corresponding request body value"

A POST whose `Mcp-Method` header disagrees with its body is accepted with 202 as long as it carries
no `id`. Nothing is executed today, because every `tools/call` clause in `BeamMCP.Server` requires
`"id"` and an id-less message falls through to `server.ex:242` `handle_message(state, _message) ->
{state, nil}`. So the safety of this exemption rests entirely on a coupling to the core — and that
coupling is unstated and untested, in a delta that elsewhere pins exactly this kind of coupling on
purpose (`test/…/http_test.exs:411`, "the core's wording that 404 keys on is pinned here").

Fix: a test that a notification POST with **no** `Mcp-Method` is accepted (the exemption's positive
case, which kills N1), and a test that an id-less `tools/call` reaches no dispatch (the coupling to
`server.ex:242`). If the exemption is meant to apply to notifications rather than to id-less
messages generally, key it on the method (`String.starts_with?(message["method"],
"notifications/")`) rather than on the absence of `id`.

### M-2 — `check_param_headers/3` is only ever tested with one mirrored header

`http.ex:390-403` reduces over every distinct `mcp-param-*` header. Every test in the delta sends
exactly one such header name, so the loop is never exercised past its first iteration:

    N9: insert `|> Enum.take(1)` after `Enum.uniq()` (validate only the first param header)
        SURVIVED | 101 tests, 0 failures

The behaviour is real and reachable (probe `D2`, unmutated tree): body arguments
`{"region":"eu-west1","user":"alice"}` with headers `mcp-param-region: eu-west1` (matching) and
`mcp-param-user: mallory` (not) →

    D2: status=400 {"error":{"code":-32020,"message":"Header mismatch: mcp-param-user header
        does not match the corresponding request body value"},...}

Under N9 that request is served. This is the same "a satisfying value first, a hostile one second"
shape as mutants 1–5, one level up — across headers instead of within one header — and it is the
shape a real mirrored-parameter deployment produces, since `x-mcp-header` can be set on more than
one property of a schema.

Fix: a test with two distinct `mcp-param-*` headers where the first matches and the second does
not; add the mutant.

By contrast the *halt* is pinned — I checked:

    N13: reduce_while never halts (last result wins)  ->  KILLED 3/101

### M-3 — `argument/2`'s fallback lets `Mcp-Param-{Name}` be satisfied by `params.{Name}`

`http.ex:441-442`:

    defp argument(%{"params" => %{"arguments" => %{} = args}}, key), do: args[key]
    defp argument(message, key), do: param(message, key)

The second clause is unpinned:

    N6: `defp argument(message, key), do: param(message, key)`
        -> `defp argument(_message, _key), do: nil`
        SURVIVED | 101 tests, 0 failures

and it changes the answer. `Mcp-Param-{Name}` is defined against a tool *argument*, but when
`params.arguments` is not a map the check silently compares against a *param* of the same name
instead. Probe `D4`, unmutated tree: body `params: {"name":"echo","arguments":"not-a-map"}`, header
`mcp-param-name: echo` →

    D4: status=200  ... "invalid arguments: arguments must be an object" ...

Header validation **passed** — the transport's MUST was satisfied by `params.name`, a different
field from the one the header names — and the request went through to the core, which rejected the
arguments for an unrelated reason. The refusal came from the wrong layer for the wrong reason; had
the tool tolerated non-map arguments, the mirrored-parameter contract would have been satisfied by
a value no client ever mirrored.

Fix: for `tools/call`, `argument/2` should look only in `params.arguments` and return `nil`
otherwise (which refuses, since a non-empty header can never match `nil`). If the fallback exists
to serve `resources/read`/`prompts/get`, which this package does not implement, say so and gate it
on the method. Either way, pin it with a test.

### M-4 — `dispatch/3`'s inner rescue is unpinned, and `mutation.md` says why it matters

`mutation.md`'s closing note argues the inner rescue at `http.ex:506-514` must be kept because it
answers with `message["id"]` while `crash_response/1` answers `id: nil`, and that "removing it would
silently downgrade every dispatch-time crash to an unidentifiable error response." The argument is
correct — and nothing enforces it:

    N11: dispatch/3's inner rescue removed, call site retargeted at do_dispatch/3
         SURVIVED | 101 tests, 0 failures

The two tests that could have caught it, `test/…/http_test.exs:253` and `:266`, assert `status ==
500`, `error.code == -32_603` and `error.message == "Internal error"` — all three identical on both
paths. Neither asserts the `id`. Probe `D5` confirms the id is the only observable difference:

    D5 (dispatch crash, raising dispatch): status=500
       {"error":{"code":-32603,"message":"Internal error"},"id":1,"jsonrpc":"2.0"}

Fix: one line in the existing test — `assert body!(conn)["id"] == 1`. That is the assertion the
record's own reasoning calls for, and it turns the note into evidence.

### M-5 — the moduledoc's "What it enforces" table was left behind while the CHANGELOG's copy of it was updated

`http.ex:50-59` is untouched by this delta (`git diff … | grep -c 'Mcp-Method\` on every request'`
→ **0**), while `CHANGELOG.md` updates the same table in the same diff. The module's own published
documentation now:

- says ``| `Mcp-Method` on every request | missing or mismatched -> `400`, `-32020` |`` — which is
  no longer true (M-1), and the CHANGELOG's copy now reads "(**not** on notifications, which the
  revision leaves undefined)";
- omits `Mcp-Param-{Name}` entirely, a MUST this delta added and enforces;
- omits the encoded-header-value decoding this delta added;
- says ``| unknown method | `404`, `-32601` |`` with no unknown-**tool** row, the distinction this
  delta introduced and tested.

This is the module's `@moduledoc`, so it is what `ex_doc` publishes and what a host reads. Fix:
apply the CHANGELOG's four table edits to `http.ex:50-59`.

### M-6 — `mutation.md` and `http.ex:320` both misreport the output of the derivation they rest on

The "how the set was derived" argument is the reason the table is claimed to be complete, so its
command has to say what it is said to say. It does not.

`mutation.md` states the two-pattern grep "returns exactly three lines: the definition of
`header_values/2`, the one call to it inside `check_origin/2`, and the `mcp-param-` prefix sweep."
Observed:

    $ grep -n 'get_req_header\|req_headers' lib/beam_mcp/transport/http.ex
    320:    # The set is derived rather than listed: `grep -n 'get_req_header' …`
    323:    defp header_values(conn, name), do: get_req_header(conn, name)
    391:      conn.req_headers

Three lines, but not those three: line 320 is the comment describing the grep, and
`check_origin/2`'s call is absent — it calls `header_values/2`, not `get_req_header`.

The in-source claim is worse. `http.ex:320-322` says the single-pattern grep "returns only
`header_values/2` and the `mcp-param-` sweep." Observed:

    $ grep -n 'get_req_header' lib/beam_mcp/transport/http.ex
    320:    # The set is derived rather than listed: `grep -n 'get_req_header' …`
    323:    defp header_values(conn, name), do: get_req_header(conn, name)

The sweep is not in the output, because it reads `conn.req_headers` directly. The comment names a
command whose output does not contain one of the two things it says the output contains.

The underlying property — one choke point plus one direct sweep — is true, and I verified the read
sites are exactly four:

    $ grep -n 'header_values(' lib/beam_mcp/transport/http.ex
    224:      case header_values(conn, "origin") do
    323:    defp header_values(conn, name), do: get_req_header(conn, name)
    406:      values = header_values(conn, header_name)
    445:      values = header_values(conn, @protocol_header)

which is also how H-2 becomes visible: line 445's values feed **two** comparisons, and the table
counts one. Fix: state the grep as `get_req_header\|req_headers`, quote its actual three lines, and
enumerate the comparisons rather than the call sites.

---

## LOW

### L-1 — the `MCP-Protocol-Version` multi-value test does not exercise the branch its name claims

`test/…/http_test.exs:512-519`, "MCP-Protocol-Version — a second, unsupported version is not
ignored", sends `[{@hdr, @modern}, {@hdr, "1999-01-01"}]` on a body built by `msg/2`, which always
carries `_meta` with the modern version (`http_test.exs:78`). So `body_version` is non-nil and the
request takes `compare_versions/3`'s **first** branch — a `-32020` header/body mismatch — never the
`-32022` unsupported-version branch the name promises. Probe `D1b`:

    D1b (with _meta, dup version): status=400
        {"error":{"code":-32020,"message":"Header mismatch: mcp-protocol-version header does not
         match the body value"},...}

The assertion is `conn.status == 400`, which both branches return, so the test cannot tell them
apart. It still kills mutant 2, so it is not worthless — but it is named for a behaviour it does
not reach, and that mis-naming is what hides H-2. Fix: assert the code (`-32_020`) and rename, or
drop the `_meta` from the body so it really does exercise the unsupported branch (which is the H-2
test).

### L-2 — "a malformed Base64 sentinel is compared literally" pins the "not crashed on" half only

`test/…/http_test.exs:397-405` asserts `status == 400`. The literal-passthrough returns at
`http.ex:336` and `:340` are free to return anything that fails the comparison:

    N5: both `"=?base64?" <> rest` fallbacks -> `""`
        SURVIVED | 101 tests, 0 failures

Literal passthrough is the observable behaviour and it does matter — probe `D6`, a tool literally
named `=?base64?!!!not-base64!!!?=`, reaches dispatch and gets `Unknown tool:
=?base64?!!!not-base64!!!?=` (200, `-32601`), i.e. the header did match the body. Fix: a test where
a tool's *name* is a malformed sentinel and the matching header is accepted, which is what
"compared literally" means.

### L-3 — `mutation.md`'s list of mutants needing a companion deletion is incomplete

The record names mutants 9 and 10. Mutant 7 needs one too (`argument/2`); see **7a** above. Fix: add
the sentence to the mutant 7 row, so the "a compiler kill is not a test kill" discipline reads as
the rule it is rather than as two special cases.

### L-4 — the `-32022` payload reports the first value as `requested` even when a later one is the offender

`http.ex:485`: `"data" => %{"supported" => [@modern_version], "requested" => List.first(values)}`.
With duplicate headers the refused value need not be the first. Probe `D1` produces a
self-contradictory diagnostic:

    "message":"Unsupported protocol version",
    "data":{"requested":"2026-07-28","supported":["2026-07-28"]}

The client is told the version it requested is unsupported and then handed that same version as the
supported one. The spec's recovery for `-32022` is "pick from `supported` and retry", so a
conforming client retries the identical request forever. Fix: report the offending value —
`Enum.find(values, &(&1 != @modern_version))` — or all of them.

---

## Re-run and found consistent (coverage, not just discrepancies)

Everything below I measured and it behaved as the code and the record claim.

- **13/13 recorded mutants**, counts and killing test names, as tabulated above.
- The compiler-kill caution for mutants 9 and 10 (`9a`, `10a` both fail to compile).
- Mutant 10's honest caveat: it kills exactly one test, and the latin-1 `Mcp-Name` test
  (`http_test.exs:766`) is *not* among them — the record's admission is accurate.
- Mutant 13's equivalence argument, traced through both call sites; plus `13a` showing the clause's
  totality is pinned even though its return value is not.
- `Keyword.drop(opts, @plug_opts)` at `http.ex:155` — the comment claims a `Keyword.take` list once
  silently dropped `tools_ttl_ms`/`tools_cache_scope` and a test caught it. Verified:
  `N7b` (`Keyword.take(opts, [:tool_catalog, :dispatch])`, `@plug_opts` removed) → **KILLED 1/101**
  by `the host chooses the cacheable values, and the default is not permissive`. The claim is true
  and the regression is still pinned.
- `init/1`'s behaviour-not-truthiness check is pinned: `N8` (`unless catalog do`) → **KILLED 1/101**
  by the new `:tool_catalog` test. All four bad values in that test are discriminating.
- `compare_versions/3`'s branch **ordering** is pinned: `N4` (the two `cond` branches swapped) →
  **KILLED 1/101** by `a header disagreeing with the body's _meta is a HeaderMismatch`. Body/header
  mismatch correctly takes precedence over version support.
- `check_named/4`'s missing-header branch: `N12` (missing header accepted) → **KILLED 2/101**.
- `check_param_headers/3`'s halt-on-mismatch: `N13` → **KILLED 3/101**.
- `check_origin/2`'s "an absent Origin is not an invalid one": `N14` → **KILLED 1/101**.
- `check_name_header/3`: `N15` (clause deleted) → **KILLED 7/101**, the widest blast radius in the
  module.
- `Enum.uniq()` at `http.ex:394`: `N10` (removed) → SURVIVED, and it is genuinely equivalent —
  `check_named/4` reads all values for a name, so a repeated name only repeats an identical check.
  No action; noted so it is not re-found as a gap.
- **`tools/probe_optional_deps.sh` is a real gate.** Unmodified in the copy: `pass: consumer
  compiles without plug; Server present, Transport.HTTP absent`, exit 0. Two independent breakages,
  two reds:
  - guard removed (`if Code.ensure_loaded?(Plug) do` wrapper deleted, matching `end` dropped) →
    `FAIL: a consumer without plug cannot compile beam_mcp (exit 1)`, with `error: module Plug.Conn
    is not loaded and could not be found … lib/beam_mcp/transport/http.ex:81`, exit 1.
  - `optional: true` removed from `{:plug, "~> 1.16"}` in `mix.exs` → `FAIL: plug was fetched into a
    consumer that never asked for it -- it is not optional`, exit 1.

    The artefact assertions (Server present / Transport.HTTP absent) are unreachable given those
    two guards fire first, which is fine — they are the belt to that braces. Note H-1: the probe
    builds a bare consumer, not one that *plugs* the transport at compile time, which is why it did
    not catch H-1.
- Full gate in the copy at the reviewed tree: `format pass, compile pass, test pass, credo pass,
  optional deps pass, reuse pass (23 commentable files), licence files pass — Gate OK.`
- Copy verified byte-identical to the worktree after the run; the worktree index never moved
  (`git write-tree` still `ebaaed0d918fed52e20af9031a1a8a71158bd3c9`).

## Summary of required changes

| id | severity | change |
|---|---|---|
| H-1 | HIGH | `Code.ensure_loaded?(catalog)` → `match?({:module, _}, Code.ensure_compiled(catalog))` at `http.ex:142`; extend the optional-deps probe to plug the transport at compile time |
| H-2 | HIGH | test duplicate `MCP-Protocol-Version` on a body with no `_meta`, asserting `-32022`; add the mutant; stop claiming one mutant per header read until the second comparison on that header is pinned |
| M-1 | MEDIUM | test the notification exemption (positive case) and the id-less-`tools/call` coupling to `server.ex:242`; consider keying the exemption on the method rather than on `id` |
| M-2 | MEDIUM | test two distinct `mcp-param-*` headers, second disagreeing; add the mutant |
| M-3 | MEDIUM | make `argument/2` look only in `params.arguments` for `tools/call`, or gate the fallback on method; pin it |
| M-4 | MEDIUM | `assert body!(conn)["id"] == 1` in the dispatch-crash test |
| M-5 | MEDIUM | apply the CHANGELOG's table edits to the `@moduledoc` table at `http.ex:50-59` |
| M-6 | MEDIUM | correct the derivation claim in `mutation.md` and at `http.ex:320-322` |
| L-1 | LOW | assert the error code in the `MCP-Protocol-Version` multi-value test, or rename it |
| L-2 | LOW | pin literal passthrough with a tool named like a malformed sentinel |
| L-3 | LOW | record that mutant 7 also needed a companion deletion |
| L-4 | LOW | report the offending version in the `-32022` `data.requested` field |
