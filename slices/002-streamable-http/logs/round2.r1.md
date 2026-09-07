From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 002-streamable-http, round 2, correctness and conformance
Type: Report

Tree read: `a5cfb67b8a8854714cde36522292c9fc57e96d6a`
(`cd /home/aylac/Projects/beam_mcp-wt/002-review2 && git write-tree`; also written to
`/home/aylac/Projects/beam_mcp-wt/002-review2/logs-r1.tree`)

All probes and mutations ran against a copy at `…/scratchpad/r1b/mut2`, never the review
worktree; every mutant was applied with an asserted count, compiled with `mix compile --force`
(the round-1 mtime trap), and the file restored and re-diffed against the review worktree after.

Round 1's six findings are fixed and I verified each independently rather than reading the log —
details at the end. Two of the fixes reproduce, one function away, the exact defect they fix.

---

## 1. HIGH — a non-map `params` raises **outside** the rescue: bare empty `500`, connection closed

**file:line** `lib/beam_mcp/transport/http.ex:355`

```elixir
defp check_name_header(conn, %{"method" => "tools/call"} = message, id) do
  check_standard_header(conn, "mcp-name", get_in(message, ["params", "name"]), id)
end
```

`check_headers/2` runs inside the `with` in `call/2`; only `dispatch/3` carries the
`rescue`/`catch`. `params` is any JSON value once the body is an object, so `get_in/2` on a
string or a list raises `FunctionClauseError` in `Access.get/3` and the exception leaves `call/2`.

This is the same defect, in the same diff, as the one just fixed twelve lines above — the comment
at `http.ex:293-297` states it exactly: *"`_meta` is any JSON value once the body is an object, so
a non-map one must be refused rather than reached into … producing exactly the bare empty 500 this
module exists to avoid — one JSON scalar away from the crash path a test already covered."*
`body_protocol_version/1` was hardened; `params` was not.

**Expected**: a `400` (or the `-32020` the sibling path returns).
**Observed**, real Bandit on `127.0.0.1:4602`, `params: "not-a-map"` with correct headers:

```
RAW-500-RESPONSE>>>"HTTP/1.1 500 Internal Server Error\r\nconnection: close\r\n\r\n"<<<
```

Empty body, and the connection is gone — the next request on that socket fails `:closed`
(`B4 next on same socket : ERROR :closed`). `params: [1,2,3]` does the same (`B5 … 500`).
Under `Plug.Test` it surfaces as the raise itself:

```
P5 params not a map : RAISED OUT OF call/2: FunctionClauseError -- no function clause matching in Access.get/3
```

The general form is worth fixing once rather than per-field: `check_headers/2` reaches into a
decoded body that is attacker-shaped, and it runs where nothing catches. Either guard every
reach-in the way `body_protocol_version/1` does, or put the `rescue`/`catch` around the whole of
`call/2` instead of only `dispatch/3`.

---

## 2. HIGH — only the **first** `Mcp-Method` / `MCP-Protocol-Version` value is compared; validation is order-dependent

**file:line** `http.ex:340` (`[value | _] when value == body_value`) and `http.ex:282`
(`get_req_header(@protocol_header) |> List.first()`).

`check_origin/2` was fixed in this same diff to check *every* value, with the rationale at
`http.ex:176-178`: *"EVERY Origin header is checked, not the first. A lane sent a good one
followed by a bad one and got 200 with tools/call executed; reversed, 403. Order-dependent
validation is not validation, and intermediaries do merge and append this header."*

That argument is not about `Origin`. It is about repeated headers, and it applies with more force
to `Mcp-Method`, because that header **is** the source-of-truth control: the spec's stated reason
for validating it is that a load balancer may route on the header while the server executes the
body (`spec-streamable-http.md:583-590`). An intermediary that reads the last value, or joins
duplicates per RFC 9110 §5.3, sees a different method from the one this server runs.

**Observed** — body is `tools/call`/`echo` throughout, two `Mcp-Method` headers:

```
P2  dup Mcp-Method (good,bad): status=200 body={"id":1,"jsonrpc":"2.0","result":{...        <- executed
P2b dup Mcp-Method (bad,good): status=400 body={"error":{"code":-32020,...
P3  dup version (good,bad)  : status=200 body={"id":1,"jsonrpc":"2.0","result":{...
```

**Expected**: a repeated standard header is refused, or every value must match. `-32020` covers
it — the spec's own wording is "required headers are missing/**malformed**".

---

## 3. MEDIUM — `Mcp-Param-{Name}` is never validated, and this package advertises `x-mcp-header`

**file:line** `http.ex:269-279` (`check_headers/2` validates three headers and no others);
`lib/beam_mcp/server.ex` `tool_definition/1` passes `input_schema` through verbatim.

**Spec** (`spec-streamable-http.md:552-562`): *"Any server that processes the message body **MUST**
validate that encoded header values, after decoding if Base64-encoded, match the corresponding
values in the request body. Servers **MUST** reject requests with a `400 Bad Request` HTTP status
and JSON-RPC error code `-32020` (`HeaderMismatch`) if any validation fails."*

`x-mcp-header` is optional *for servers to designate* — but the designation lives in the tool's
`inputSchema`, which this package neither constrains nor strips, so a host can turn it on and
conforming clients then **MUST** mirror those parameters into headers. At that point the server
must validate them, and this one does not.

**Observed** — catalogue tool `echo` with `"region": {"x-mcp-header": "Region"}` in its schema:

```
XMCPHEADER-ADVERTISED>>>yes<<<                      # the annotation reaches the client via tools/list
MCPPARAM-MISMATCH>>>HTTP/1.1 200 OK<<<              # Mcp-Param-Region: us-west1  vs  body region "eu-west1"
```

Header says one region, body says another, the call runs on the body. That is finding 2 of round 1
for the custom-header half, and it is reachable through a supported, documented host configuration.
If the intent is not to support `x-mcp-header`, the honest form is to reject a `tools/list`
schema carrying the annotation (or strip it) rather than advertise a contract the transport
does not keep.

---

## 4. MEDIUM — the Base64 sentinel form of `Mcp-Name` is not decoded before comparison

**file:line** `http.ex:335-350`, `http.ex:354-356`.

**Spec** (`spec-streamable-http.md:500-507` and `:620-628`): *"servers **MUST** decode an encoded
`Mcp-Name` or `Mcp-Param-{Name}` value before comparing it to the corresponding request body value
during Server Validation."* Tool names are only SHOULD-constrained to header-safe characters, and
this package places no constraint at all on them — `tool_definition/1` does
`Atom.to_string(tool.name)`.

**Observed**, tool `:"café_search"`, client encoding exactly as the spec requires:

```
P4 base64 Mcp-Name (=?base64?Y2Fmw6lfc2VhcmNo?=) : status=400
   body={"error":{"code":-32020,"message":"Header mismatch: mcp-name header
   '=?base64?Y2Fmw6lfc2VhcmNo?=' does not match body value 'café_search'"},"id":1,"jsonrpc":"2.0"}
```

A fully conforming client cannot call that tool over HTTP, and the recovery the spec advises for a
`HeaderMismatch` (`spec-streamable-http.md:541-546` — re-read `tools/list`, retry) cannot help,
because the client was already right. It is one `String.starts_with?("=?base64?")` /
`Base.decode64` in `check_standard_header/4`.

---

## 5. MEDIUM — `404` is applied to every `-32601`, including one where the method **is** implemented

You asked whether the `404` mapping is right in every case. Two of the three sites, yes; one, no.

**file:line** `http.ex:393-396` matches on the code alone:

```elixir
{_state, %{"error" => %{"code" => -32_601}} = response} -> send_json(conn, 404, response)
```

`lib/beam_mcp/server.ex` emits `-32601` at three places:

| site | meaning | `404` correct? |
|---|---|---|
| `server.ex:235` `"Method not found: #{method}"` | method table miss | yes |
| `server.ex:155` `"Method not found: ping"` (modern era) | method removed in `2026-07-28` | yes |
| `server.ex:222` `"Unknown tool: #{name}"` | `tools/call` **is** implemented; the tool is not | **no** |

**Spec** (`spec-streamable-http.md:271-275`): the `404` is conditioned on *"the server does not
implement the requested **RPC method**"*. An unknown tool is a parameter that does not resolve
inside a method that exists.

**Observed** — the two are indistinguishable on the wire:

```
P1  unknown TOOL          : status=404 body={"error":{"code":-32601,"message":"Unknown tool: no_such_tool"},...}
P1b unimplemented METHOD  : status=404 body={"error":{"code":-32601,"message":"Method not found: resources/list"},...}
```

Key the status off the method table (or have `server.ex:222` stop reusing `-32601` — the
`2026-07-28` changelog moved the analogous "resource not found" to `-32602 Invalid Params`,
`spec-changelog.md:39`), rather than off the code. The moduledoc table (`http.ex:59`) and
`CHANGELOG.md:52` both say "unknown method | `404`, `-32601`", which describes the intent and not
the behaviour.

---

## 6. MEDIUM — the multi-`Origin` fix has no test; the mutant survives

**file:line** `http.ex:187`. The behaviour and its rationale are in the code
(`http.ex:176-178`), but nothing pins it.

```
== N12 only the first Origin checked (round-1 fix reverted)
   applied: old 1 -> 0 ; new occurrences 1        # Enum.all? -> Enum.any?
   82 tests, 0 failures  exit=0
   >>> SURVIVOR
```

Proven by effect rather than by the green suite alone — `allowed_origins: ["https://good.example"]`:

```
--- under the Enum.any? mutant ---
ORIGIN good,evil -> 200      ORIGIN evil,good -> 200      (suite: 82 tests, 0 failures)
--- restored ---
ORIGIN good,evil -> 403      ORIGIN evil,good -> 403      (suite: 82 tests, 0 failures)
```

The three existing `Origin` tests all send a single header, so none can distinguish. This is the
same gap round 1 recorded for the body cap — the fix landed, the regression test did not — and
the fix is the one the diff singles out as found by a lane.

---

## 7. LOW — `Mcp-Method` is required on **notification** POSTs, which the revision leaves undefined

**file:line** `http.ex:273` (applied to every message, id or not).

**Spec** (`spec-streamable-http.md:93-103`): *"The notification rules above describe the transport
mechanics for a notification POST; **header requirements for notification POSTs are not defined by
this revision**."*

```
P6 notification, no Mcp-Method: status=400
   body={"error":{"code":-32020,"message":"Header mismatch: Missing mcp-method header; it is required"},"id":null,...}
```

Requiring it is defensible strictness, but it is a hard `400` for a client that follows that Note,
and neither the moduledoc table ("`Mcp-Method` on every request") nor `CHANGELOG.md:48` says the
transport is stricter than the revision here. Either say so in the table, or exempt bodies with no
`id`.

---

## Verified fixed — checked on the artefact, not the log

* **R1-1, the package would not compile without `plug`.** Built a fresh consumer whose only dep is
  `{:beam_mcp, path: …}`. `mix compile`'s **own** exit status (not a pipeline's): `0`.
  `ls deps` → `jason` only. `{Code.ensure_loaded?(HTTP), Stdio, Server}` → `{false, true, true}` —
  the HTTP module is correctly absent while the rest of the package works.
* **R1-2, `Mcp-Method` / `Mcp-Name`.** Both required and both compared to the body. My case B is
  pinned: mutants N1 (missing-header branch → `:ok`), N2 (mismatch branch → `:ok`) and N3
  (`Mcp-Name` never checked) are all killed.
* **R1-3, `404` for an unimplemented method.** N4 (`404` → `200`) killed. See finding 5 for the
  over-broad half.
* **R1-4, `-32020`.** N5 (`-32020` → `-32600`) killed by 6 tests.
* **R1-5, the `403` leak.** N11 (reason re-interpolated into the body) killed. The reason goes to
  `Logger`, and the non-`:ok`/`{:error, _}` return now fails closed rather than raising.
* **R1-6, the cap and the 413.** N6 (`413`→`200`), N7 (`connection: close` removed) and N8 (cap
  removed) are all killed — the three round-1 survivors are gone.
* **The keep-alive diagnosis is right and the fix works.** Measured over one raw socket, 16 KB body
  on a post-`read_body` refusal:
  `B1 16KB body, missing Mcp-Method : HTTP/1.1 400 Bad Request` then
  `B2 next on same socket : HTTP/1.1 200 OK`. Recording that the first diagnosis was wrong, in the
  shipped `CHANGELOG.md`, is the right call.
* **`throw`/`exit` coverage.** N10b (whole `catch` block deleted) killed.
* **Non-map `_meta`.** N9 (`_other -> :invalid` → `nil`) killed. See finding 1 for its sibling.
* **`handle_message/2` is still 13 clauses**, and `lib/beam_mcp/server.ex` is untouched in this
  delta — acceptance criterion 6 continues to hold.
* **Gate, read line by line rather than by exit code**:
  `format pass · compile pass · test pass · credo pass · reuse pass (22 commentable files) ·
  licence files pass · Gate OK` — `82 tests, 0 failures`.
* **`Allow: POST` on the 405** (round-1 finding 9) is in, and `CHANGELOG.md:53` now correctly calls
  the 405 a SHOULD.
* **The archived spec pages are unchanged in this delta**, and remain faithful to the live page I
  re-fetched in round 1.

VERDICT: changes required
