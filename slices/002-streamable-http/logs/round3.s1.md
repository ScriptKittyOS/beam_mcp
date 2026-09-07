# Round 3 — lane s1 (security / specification conformance)

Tree read: `ebaaed0d918fed52e20af9031a1a8a71158bd3c9`
(`git rev-parse HEAD^{tree}`, matches the value the assignment names.)

Scope: `git diff a5cfb67b8a8854714cde36522292c9fc57e96d6a HEAD` — 13 files, 1845 insertions.

VERDICT: changes required

**Where the probes ran.** Every probe, every mutation and every compile ran in
`/tmp/claude-1000/-home-aylac-Projects-hacktui-hermes/775c8d71-6ac1-4653-8798-382001e76089/scratchpad/lane-s1`,
a `cp -a` of the worktree with `.git` and `_build` removed. Mutations asserted their match count
before and after applying and were restored from a saved original; `diff -q` against the worktree
confirms `lib/beam_mcp/transport/http.ex` and `lib/beam_mcp/server.ex` are byte-identical to the
reviewed tree. The worktree itself was only read, apart from this file and `round3.s1.tree`.

Baseline in the copy, before any mutation and with probe files removed:
`mix test` → **101 tests, 0 failures**; `mix format --check-formatted` → clean;
`mix credo --strict` → **no issues**. Every finding below is a gap the suite does not cover, not
a red test.

Spec quotations are from the verbatim archive already in the repo,
`slices/002-streamable-http/logs/spec-streamable-http.md`, cited by line.

---

## F1 — HIGH — the Base64 sentinel is decoded on `Mcp-Method`, which reopens the smuggling this delta exists to close

**file:line** `lib/beam_mcp/transport/http.ex:346-348` (`all_match?/2` calls `decode_header_value/1`
unconditionally), reached for `mcp-method` via `check_method_header/3` at `:366-370` → `check_named/4`
at `:405-423`.

The spec scopes the sentinel to two headers. `spec-streamable-http.md:470` — *"Clients **MUST**
encode **parameter values** before including them in HTTP headers"*; `:491` — *"The same encoding
rule applies to the `Mcp-Name` header value"*; `:502-504` — *"servers **MUST** decode an encoded
`Mcp-Name` or `Mcp-Param-{Name}` value before comparing it"*. `Mcp-Method` is not in that set, and
a conforming client would never encode it: method names (`tools/call`) are always header-safe ASCII.
The delta's own CHANGELOG row says the same — *"an encoded header value is decoded before comparison
| `=?base64?…?=` on `Mcp-Name` / `Mcp-Param-{Name}`"* (CHANGELOG.md, delta hunk at the requirements
table). The code applies it to every header that routes through `all_match?/2`.

**Observed**, over a real Bandit socket on 127.0.0.1:4599, not `Plug.Test`:

```
W3 Mcp-Method: =?base64?dG9vbHMvY2FsbA==?= -> HTTP/1.1 200 OK dispatch={:dispatched, :echo, %{}}
```

Expected: `400` / `-32020`, the same as any other `Mcp-Method` that is not the body's `method`.

**Why it is HIGH and not cosmetic.** `spec-streamable-http.md:246-248` states the reason the header
exists: *"so that intermediaries (load balancers, gateways, observability tooling) can route and
inspect requests without parsing the body."* A gateway with a denylist rule on `Mcp-Method:
tools/call` does not match `=?base64?dG9vbHMvY2FsbA==?=`; this server runs `tools/call`. That is
precisely the header/body divergence at `:588-593` (*"a load balancer routing on the header value
while the MCP server executes based on the body value"*) — reintroduced by the decoder's placement,
in the same commit that fixed it for duplicate values.

No mutant in `logs/mutation.md` pins the *scope* of decoding. Mutant 8 disables the base64 clause
entirely and is killed by the `Mcp-Name` test; nothing fails if decoding is applied too widely.

**Fix.** Decode only for `mcp-name` and `mcp-param-*`. Either split `all_match?/2` into an
encoded-permitted and a literal variant, or pass the permission as an argument from `check_named/4`.
Add a test asserting an encoded `Mcp-Method` is `400`, and a mutant that widens the scope again.

---

## F2 — HIGH — the `Mcp-Param-{Name}` population is derived from the request, so the spec's "client omits the header" MUST is unenforced, and the README claims otherwise

**file:line** `lib/beam_mcp/transport/http.ex:390-403`. The comment at `:388-389` states the design
choice openly: *"The population is derived from the request rather than from the schema: every
`mcp-param-*` header present must match the argument of that name."*

The spec's server-behaviour table is four rows, `spec-streamable-http.md:564-569`:

| Scenario | Client Behavior | Server Behavior |
|---|---|---|
| Parameter value provided | Client MUST include the header | Server MUST validate header matches body |
| Parameter value is `null` | Client MUST omit the header | Server MUST NOT expect the header |
| Parameter not in arguments | Client MUST omit the header | Server MUST NOT expect the header |
| **Client omits header but value is in body** | **Non-conforming client** | **Server MUST reject the request** |

Rows 1–3 are implemented. Row 4 is not, and it is the row with a security consequence.

**Observed**, real socket, catalog tool `:echo` whose `inputSchema` annotates
`"region": {"x-mcp-header": "Region"}`:

```
W4 no Mcp-Param-Region -> HTTP/1.1 200 OK dispatch={:dispatched, :echo, %{region: "eu-west1"}}
```

Expected: `400` / `-32020`. An attacker (or a hop that strips headers it does not know) simply omits
`Mcp-Param-Region`; the gateway routes on its default and the server executes `eu-west1`.

**The delta's prose asserts the opposite.** README.md:210 — *"`Mcp-Param-{Name}` is enforced because
`tool_definition/1` passes a schema's `x-mcp-header` annotation through to `tools/list` verbatim."*
The passthrough is real — I confirmed `server.ex:249` emits `"inputSchema" => tool.input_schema`
untouched, and a live `tools/list` returns
`{"properties":{"region":{"type":"string","x-mcp-header":"Zone"},...}}` — but the transport never
reads the annotation back. The enforcement is grounded in something it does not consult. The
README's Implemented list likewise says the three headers are *"required where the revision requires
them"*; `Mcp-Param-{Name}` is never required, only validated when volunteered.

**Fix.** Either (a) resolve the annotated set from `opts.server_opts[:tool_catalog]`'s `input_schema`
for the named tool and require a header for every annotated property that has a value in
`arguments`; or (b) if that is deferred to a later release, delete the enforcement claim from
README.md:210 and the "required where the revision requires them" sentence, and record row 4 as not
implemented in the same list that already carves out sessions and SSE. What is not acceptable is the
current pairing: the claim shipped, the control did not.

---

## F3 — HIGH — the header suffix is treated as a top-level, case-sensitive argument key, so a conforming client is rejected with no recovery

**file:line** `lib/beam_mcp/transport/http.ex:396`
(`arg_name = String.replace_prefix(header, "mcp-param-", "")`) and `:441-442` (`argument/2`).

The spec does not say the name portion is the property key, and does not say the property is
top-level. `spec-streamable-http.md:375` — *"The `x-mcp-header` property specifies the **name
portion** used to construct the header name `Mcp-Param-{name}`"*, constrained only to be a non-empty
HTTP token (`:379-381`). `:389-395` — *"**MUST** only be applied to properties that are statically
reachable ... **Nested object properties are permitted** as long as every step in the chain is a
`properties` key."* `:398-401` — *"Header extraction is defined as reading the instance value at the
**exact property path** of the annotated property."*

Three shapes a conforming client cannot get past. All measured; all `400` / `-32020`:

```
S1  schema: "region": {"x-mcp-header": "Zone"};   client sends Mcp-Param-Zone: eu-west1
    -> 400 {"error":{"code":-32020,"message":"Header mismatch: mcp-param-zone header does not
            match the corresponding request body value"}}

S2  schema: "filter": {"properties": {"tenant": {"x-mcp-header": "Tenant"}}};
    body arguments {"filter":{"tenant":"acme"}}; client sends Mcp-Param-Tenant: acme
    -> 400 ... mcp-param-tenant header does not match ...

C1  schema: "Region": {"x-mcp-header": "Region"}; body {"Region":"eu-west1"};
    client sends Mcp-Param-Region: eu-west1
    -> 400 ... mcp-param-region header does not match ...

C2  schema: "maxRows": {"x-mcp-header": "MaxRows"}; body {"maxRows":10};
    client sends Mcp-Param-MaxRows: 10
    -> 400 ... mcp-param-maxrows header does not match ...
```

C1/C2 are the ones that will actually be hit. `spec-streamable-http.md:598-602` makes header *names*
case-insensitive, so Bandit downcases `Mcp-Param-MaxRows` to `mcp-param-maxrows`; `:396` then strips
the prefix and uses the downcased remainder as a **case-sensitive JSON object key**. `args["maxrows"]`
is `nil`, and every camelCase or capitalised argument key is unreachable over HTTP. The spec's own
examples are capitalised throughout (`Mcp-Param-Region`, `Mcp-Param-Greeting`, `Mcp-Param-Text`,
`Mcp-Param-Val`, `:515-519`).

This is the same failure shape round 2 recorded for base64 `Mcp-Name` at `round2.r1.md:125-141`: the
recovery the spec advises for a `HeaderMismatch` — re-read `tools/list` and retry (`:541-546`) —
cannot help, because `tools/list` returns the identical annotation. That defect was fixed; this one
is its twin and was not found because the delta's three `x-mcp-header` tests
(`test/beam_mcp/transport/http_test.exs:585-620`) all use `region` for both the property key and the
header suffix — the one naming convention where the bug is invisible.

**Fix.** Build the mapping from the tool's schema: walk `properties` chains, collect
`{downcase(x-mcp-header value) => property path}`, and resolve the header suffix through that map
rather than assuming suffix == top-level key. This is the same catalog read F2 needs, so the two
fixes share their mechanism. Add tests for a differing name portion, a nested path, and a
camelCase key.

---

## F4 — MEDIUM — non-canonical Base64 is accepted, so several distinct raw header values satisfy one body value

**file:line** `lib/beam_mcp/transport/http.ex:334-336`.

`Base.decode64/1` discards non-zero trailing bits rather than rejecting them:

```
P5 decode64("ZWNobw==") = {:ok, "echo"}
P5 decode64("ZWNobx==") = {:ok, "echo"}
```

so four different header values all pass the `Mcp-Name: echo` comparison. Over a real socket:

```
W5 Mcp-Name==?base64?ZWNobw==?= -> HTTP/1.1 200 OK dispatch={:dispatched, :echo, %{}}
W5 Mcp-Name==?base64?ZWNobz==?= -> HTTP/1.1 200 OK dispatch={:dispatched, :echo, %{}}
```

(In-process, `ZWNobx==` and `ZWNoby==` behave identically: `P5 ... -> 200`.)

An intermediary that compares the header bytes against the canonical encoding it would have
produced, or that uses a strict decoder, sees a value this server does not. That is the same
divergence primitive as F1, one layer down. It is MEDIUM rather than HIGH because exploiting it
needs an intermediary that decodes or canonicalises, which is a narrower population than one that
string-matches.

**Fix.** After decoding, require canonicality: `Base.encode64(decoded) == encoded`, otherwise fall
through to the literal comparison (or refuse). One line, and it makes the encoding a bijection.

---

## F5 — MEDIUM — `argument/2` falls back to `params`, so `Mcp-Param-{Name}` can be satisfied by a value that is not an argument

**file:line** `lib/beam_mcp/transport/http.ex:441-442`:

```elixir
defp argument(%{"params" => %{"arguments" => %{} = args}}, key), do: args[key]
defp argument(message, key), do: param(message, key)
```

When `params.arguments` is absent or is not a map, the second clause compares `Mcp-Param-X` against
`params["X"]` — a field of the RPC envelope, not a tool argument.

**Observed** (in-process; the body has no `arguments` key at all):

```
P8  body params {"name":"echo"}; headers mcp-name: echo, mcp-param-name: echo
    -> 200, dispatched {:dispatched, :echo, %{}}
P8b body params {"name":"echo","arguments":"not-a-map"}; same headers
    -> 200
```

The request is accepted while asserting, in a header an intermediary is invited to read, that
argument `name` has the value `echo`. The dispatched arguments are `%{}` — the tool never receives a
`name` argument. Expected per `spec-streamable-http.md:566-567` (*"Parameter not in arguments |
Client MUST omit the header | Server MUST NOT expect the header"*, and the header was sent anyway,
making the client non-conforming): `400` / `-32020`.

**Fix.** `argument/2` should return `nil` when `params.arguments` is not a map, rather than falling
through to `param/2`. The `param/2` fallback is right for `Mcp-Name` (which genuinely reads
`params.name`) and wrong for `Mcp-Param-*`.

---

## F6 — LOW — integer values are compared as strings, against an explicit SHOULD

**file:line** `lib/beam_mcp/transport/http.ex:429-433` (`to_comparable/1`).

`spec-streamable-http.md:583-586`: *"When validating integer parameter values, servers **SHOULD**
compare the header value and the body value numerically rather than as strings (e.g., `42.0` and
`42` are considered equal)."*

**Observed:**

```
P3 body n=42    header=42     -> 200
P3 body n=42    header=42.0   -> 400
P3 body n=42.0  header=42     -> 400
P3 body n=42.0  header=42.0   -> 200
```

Fails closed, so it is interop rather than security, and `x-mcp-header` forbids the `number` type
(`:385-386`), which narrows it further. But the README's "Implemented" list does not carve it out,
and the CHANGELOG table does not mention it. Either implement the numeric compare or name it in the
"not implemented" list.

---

## F7 — LOW — the attacker's header name is reflected verbatim into the refusal body

**file:line** `lib/beam_mcp/transport/http.ex:417-421`.

```
P6 status 400 body={"error":{"code":-32020,"message":"Header mismatch:
   mcp-param-x\"><script>alert(1)</script> header does not match the corresponding
   request body value"},"id":1,"jsonrpc":"2.0"}
P6 resp content-type=["application/json; charset=utf-8"]
```

The delta's own test at `test/beam_mcp/transport/http_test.exs:731-737` argues the case for the body
*value* — *"the value is also attacker-chosen text being reflected to an unauthenticated caller, so
the message names the header and says nothing about what was in it"* — and then names the header,
which for `mcp-param-*` is equally attacker-chosen. Content-type is `application/json`, and a
conforming HTTP adapter rejects a field name that is not a token, so the reachable surface is
narrow (a Plug feeding this one, per the `Plug.Router` mount the delta's README now documents).
Reflecting the caller's own input back to the caller is not a disclosure of host state, hence LOW.
Fix: use a fixed label, or the fact that a mismatch occurred without naming which header.

---

## F8 — LOW — the new README paragraphs are asserted, not pinned, and one of them is false

`test/beam_mcp/readme_claims_test.exs` is **not** in the delta (`git diff --stat` lists only
`test/beam_mcp/transport/http_test.exs` under `test/`). Its own moduledoc already says the mechanism
*"does not catch a claim added without a test"*, so this is a disclosed gap rather than a false
guarantee — I am not scoring the gap itself.

What I am scoring is what went through it. The delta adds prose carrying precise measurements —
`119 bytes 200`, `16 KiB and 200 KiB both 408 after 15.0 s`, `1,769,325 bytes read before the 413`,
`8,000 concurrent (+8.16 GiB RSS)`, `100 × 16,384 = 1,638,400`, `16,500 connections held 243 MiB` —
and one behavioural claim, README.md:210, which F2 measures to be false. A false claim is exactly
the class `readme_claims_test.exs` exists for, and it entered in the release where nothing was added
to the list. At minimum: correct README.md:210 per F2, and add it to the pinned list so the
correction cannot silently regress.

---

## What I tried that did NOT find anything

Reported so the lane is measurable rather than a list of hits.

- **The derived-set claim holds.** `grep -n 'get_req_header\|req_headers'
  lib/beam_mcp/transport/http.ex` returns exactly three lines: `:320` (the comment asserting it),
  `:323` (`header_values/2`), `:391` (the `mcp-param-` sweep). Widening to all of `lib/` and to
  `get_req_headers`, `fetch_query_params`, `Plug.Parsers` and any other `Plug.Conn.` call adds
  nothing. There is no pattern match on `%Plug.Conn{req_headers: ...}` anywhere. The sweep at `:391`
  reads only header *names*; every value still goes back through `header_values/2` via
  `check_named/4`. I could not find a header read outside the set.
- **Header-name case-insensitivity is satisfied**, by the adapter rather than by this code, and I
  checked that rather than assuming it. Over a real Bandit socket with `MCP-Protocol-Version`,
  `Mcp-Method`, `Mcp-Name` and `Mcp-Param-Region` sent in mixed case, both `get_req_header` and the
  `String.starts_with?(name, "mcp-param-")` sweep saw them: `W1 -> HTTP/1.1 400 Bad Request
  dispatch=:no_dispatch` on a mismatched param, which requires the sweep to have matched.
- **Duplicate-value validation is real on all five reads.** `W2 dup Origin -> HTTP/1.1 403
  Forbidden` over the wire, plus the five in-process duplicate tests in the delta. I re-derived
  mutant 9 independently (rekey `404` on the bare `-32601`, `@method_not_found` removed in the same
  edit so the mutant compiles rather than being a compiler kill): killed `an unknown tool is 200
  with a JSON-RPC error, not 404`, 1 failure of 51. `logs/mutation.md`'s honest 3/5 note for mutant
  6 matches what the code does — `check_origin/2` and the version check genuinely do not route
  through `all_match?/2`.
- **The `404` rekey is pinned in both directions.** Rewording the core: `sed -i 's/Method not
  found:/Unimplemented method:/g' lib/beam_mcp/server.ex`, asserted 2 matches before and 2 after,
  killed 3 tests — `an unimplemented method is still 404`, `the core's wording that 404 keys on is
  pinned here`, and `an unimplemented method is 404, not 200`. So a reword of the core fails a test
  rather than silently turning every `404` into a `200`, as the comment at `http.ex:540-542` claims.
- **Leak hunt found nothing new.** Planted `bearer-SEKRET` and `postgres://u:p@h/db` in an
  `authorize/1` `{:error, reason}` and in a `raise` from `dispatch`. Neither reached a response:
  `403 {"error":{"code":-32600,"message":"Forbidden"}}` and
  `500 {"error":{"code":-32603,"message":"Internal error"}}`; both reached the log only. Round 1's
  defect is closed. A `dispatch` returning `{:error, %{token: "bearer-SEKRET"}}` *does* relay the
  token to the caller, but that is `server.ex`'s `tool_failure/1` relaying the host's own returned
  value, it is unchanged by this delta, and it is post-`authorize`. Not scored.
- **Crash hunt found nothing outside the rescue.** `_meta` as a list and as a string, `method` as a
  map, `method` absent, `id` as a map, `params` as a string, `arguments` as a string, a header named
  exactly `mcp-param-` (empty suffix), a header name containing `"`/`<`/`>`, a non-UTF-8 `Mcp-Name`
  (`<<0xFF,0xFE>>`), and a notification with no `id`. Every one answered with `conn.state == :sent`
  and a JSON body: `400` for the malformed shapes, `202` for the notification. No bare bodyless
  `500`, no missing response, no `Jason.EncodeError` escaping. Claim 4 holds against everything I
  could throw at it.
- **Comma-folded header values fail closed.** `Mcp-Method: tools/list, tools/call` on a single line
  arrives as one value and does not equal the body's `method`: `W6 -> HTTP/1.1 400 Bad Request`.
- **The protocol-version header does not inherit F1** — but only by accident, and the record should
  say so. An encoded `MCP-Protocol-Version` is refused: `P4 -> 400
  {"error":{"code":-32022,"data":{"requested":"=?base64?MjAyNi0wNy0yOA==?=","supported":["2026-07-28"]}}}`.
  That is `compare_versions/3:477` comparing the **raw** value against `@modern_version`, not intent.
  If that branch ever moved to `all_match?/2`, F1 would extend to the version header immediately.
- **`Origin` does not inherit F1.** `check_origin/2:229` is set membership on raw values with no
  decoding, so `=?base64?...?=` cannot launder an origin.
- **The `-32022` `data.requested` reflection is the caller's own header** and is required by the
  spec's `UnsupportedProtocolVersionError` shape. Not scored.
- **`check_origin/2` runs before `authorize/2`**, so an unauthenticated caller can distinguish
  `"Origin not allowed"` from `"Forbidden"` and enumerate the host's allow list. The spec mandates
  the `403` for a bad Origin (`:57-61`), and an allow list is not normally a secret. Judged not a
  finding; recorded because it is a real ordering property someone may want to revisit.
- **`:tool_catalog` behaviour check (claim 6)** — the delta's test covers `true`, a string, `Enum`
  and `:not_a_module`. I found no value that passes `is_atom and != nil and Code.ensure_loaded? and
  function_exported?(:all, 0)` while failing at the first `tools/list`. No finding.

---

## Summary of what would clear the verdict

F1, F2 and F3 are the blocking three. F1 and F4 are one function each. F2 and F3 share a mechanism —
read the catalog's `x-mcp-header` annotations and resolve suffix → property path through them — so
they are one piece of work, and the alternative for F2 (delete the enforcement claim and record it
as not implemented) is a valid resolution if the schema read is deferred. F5 is one clause. F6–F8
are recorded, not blocking, but F8's first half is a consequence of F2 and goes away with it.
