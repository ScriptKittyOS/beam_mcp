# Round 4 — lane s1 (security, by exploit)

Tree read: `89f7a2566e687c4247bab9a7f0622b32d67a2aa0` (matches the expected hash; recorded in
`slices/002-streamable-http/logs/round4.s1.tree`).

Scope: `git diff ebaaed0d918fed52e20af9031a1a8a71158bd3c9 HEAD` — round 3's fixes plus the record
commit.

## VERDICT: changes required

Three findings block a publish. Two of them are in **one function**, `value_matches?/2`, which this
delta introduced to replace `to_comparable/1`, and both are **measured regressions against
`ebaaed0d`**: an input that returned `400` before this delta now returns `500`, and an input that
returned `400` before this delta now returns `200` and dispatches. That is the pattern this round
was convened to look for, and it is the same shape as round 3's: the fix for one MUST reopened a
hole the other MUST closes.

The three things I was asked to verify by exploit are, in themselves, **fixed and holding**:
base64 decoding is correctly scoped, the omitted-header MUST is enforced, and the second copy of
the rescue does reach `fault_response/4`. Finding 3 is a consequence of that third fix being
applied to the copy it does not fit.

## Where the probes ran

All probes ran against a live `Bandit 1.12.5` on a real socket, never `Plug.Test`.

- Post-delta server: `cp -a` of the worktree to
  `/tmp/claude-1000/-home-aylac-Projects-hacktui-hermes/775c8d71-6ac1-4653-8798-382001e76089/scratchpad/lane4-s1`,
  with `.git` and `_build` removed and rebuilt. Bound `127.0.0.1:4911`.
- Pre-delta baseline for the regression proof: `git archive ebaaed0d918fed52e20af9031a1a8a71158bd3c9`
  extracted to `.../scratchpad/base-ebaaed0`, `deps/` and `mix.lock` copied in, compiled fresh.
  Bound `127.0.0.1:4912`.
- Nothing in `/home/aylac/Projects/beam_mcp-wt/002-http` was modified except this file and
  `round4.s1.tree`. Nothing in `/home/aylac/Projects/hacktui_hermes` was touched.
- The probe catalog carries seven tools covering the schema shapes named in the brief: colliding
  annotations, an annotation inside `items` and inside `oneOf`, an annotation on a non-primitive
  and on a `number`, a non-map `properties`, and two tools whose dispatch raises — one plain and
  one carrying `plug_status`, each with a planted secret in its message.

---

## Finding 1 — BLOCKS PUBLISH

**An attacker-chosen JSON integer crashes header validation into an unauthenticated `500` with an
error-level stacktrace. Pre-delta the same request was a `400`.**

`lib/beam_mcp/transport/http.ex:414-419`, the raise at **:416**:

```elixir
defp value_matches?(header_value, body_value) when is_integer(body_value) do
  case Float.parse(header_value) do
    {parsed, ""} -> parsed == body_value * 1.0     # <- :416
    _ -> false
  end
end
```

`body_value` is a JSON integer the caller wrote. Erlang integers are arbitrary-precision; floats
are not. `body_value * 1.0` raises `ArithmeticError` for any integer whose magnitude exceeds the
float range (~1.8e308), which JSON expresses in 310 characters.

Observed vs expected: expected `400` `-32020` (header does not match body). Observed `500`
`-32603` plus ~750 bytes of `[error]` stacktrace per request.

**Three independent reachable paths, all before dispatch, none needing a tool:**

```
$ BIG=$(python3 -c "print('9'*400)")

# (a) via _meta protocolVersion -- reached in check_protocol_version, before any catalog lookup
$ curl -s -w '\nHTTP %{http_code}\n' -X POST http://127.0.0.1:4911/ \
    -H 'content-type: application/json' -H 'MCP-Protocol-Version: 1' -H 'Mcp-Method: tools/list' \
    --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":$BIG}}"
{"error":{"code":-32603,"message":"Internal error"},"id":null,"jsonrpc":"2.0"}
HTTP 500

# (b) via params.name on tools/call -- check_name_header
# (c) via a Mcp-Param-{Name} on an annotated integer property -- check_param_headers
# (d) via the method itself:
$ N=$(python3 -c "print('1'+'0'*309)")
$ curl ... -H 'Mcp-Method: 1' --data-binary "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":$N}"
HTTP 500
```

Server log for (a):

```
14:00:xx [error] ** (ArithmeticError) bad argument in arithmetic expression
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:416: BeamMCP.Transport.HTTP.value_matches?/2
    (elixir 1.19.2) lib/enum.ex:4312: Enum.predicate_list/3
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:618: ... compare_versions/3
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:435: ... check_headers/3
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:224: ... handle/2
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:185: ... call/2
```

**Proof this is a regression, not pre-existing.** Same request, same Bandit, pre-delta tree
`ebaaed0d` on port 4912:

```
$ curl -s -w '\nHTTP %{http_code}\n' -X POST http://127.0.0.1:4912/ ...same request...
{"error":{"code":-32020,"message":"Header mismatch: mcp-protocol-version header does not match the body value"},"id":1,"jsonrpc":"2.0"}
HTTP 400
```

The delta deleted `to_comparable/1`, whose numeric clause was `to_string(value)` — total, never
raising — and replaced it with float arithmetic. The comment deleted alongside it said, in terms,
*"a refusal should not depend on the rescue to be a refusal."* That is now exactly what happens:
the header check crashes and the outer rescue converts it to `500`.

Cost to an attacker: one request, ~330 bytes. Return: a `5xx` on a `4xx` path, and an error-level
log line per request, on a path the module's own `authorize/1` docs describe as *"possibly
unauthenticated, since authorize/1 is the host's and may permit anyone"*.

**Not pinned.** `mix test` in the copy: `126 tests, 0 failures`. No test in the tree uses an
integer above 2^53 or beyond float range —
`grep -rn '9007\|e1[0-9]\|999999999' test/` returns nothing.

## Finding 2 — BLOCKS PUBLISH

**The same function accepts a header value that is a *different integer* from the body value, so
`Mcp-Param-{Name}` no longer prevents the header/body disagreement it exists to prevent.
Pre-delta this was a `400`.**

`lib/beam_mcp/transport/http.ex:414-419`. `Float.parse(header_value) == body_value * 1.0` compares
two IEEE-754 doubles. Above 2^53 that map is not injective: distinct integers land on one float.

```
$ curl -s -w '\nHTTP %{http_code}\n' -X POST http://127.0.0.1:4911/ \
    -H 'content-type: application/json' -H 'MCP-Protocol-Version: 2026-07-28' \
    -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
    -H 'Mcp-Param-maxRows: 9007199254740992' \
    --data-binary '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"max_rows":9007199254740993}}}'
{"id":1,...,"result":{...,"structuredContent":{"max_rows":9007199254740993}}}
HTTP 200
```

The header says `...992`. The tool ran with `...993`. `200`, dispatched. This is the load-balancer
disagreement quoted verbatim at `http.ex:357-361` as the reason the whole mechanism exists.

Pre-delta, `ebaaed0d` on 4912, same request (header name `mcp-param-max_rows` under the old
lowercase-the-suffix derivation):

```
{"error":{"code":-32020,"message":"Header mismatch: mcp-param-max_rows header does not match the corresponding request body value"},"id":1,"jsonrpc":"2.0"}
HTTP 400
```

**The window is ±½ulp and grows with magnitude**, so this is not a 2^53 curiosity — it is a
proportional tolerance on every mirrored integer:

```
  body=9007199254740993    header=9007199254740992    -> HTTP 200
  body=9007199254740994    header=9007199254740992    -> HTTP 400
  body=1000000000000000001 header=1000000000000000000 -> HTTP 200
  body=1000000000000000064 header=1000000000000000000 -> HTTP 200
  body=1000000000000000128 header=1000000000000000000 -> HTTP 400
  body=1000000000000000000 header=1000000000000000064 -> HTTP 200   (symmetric)
  body=-9007199254740993   header=-9007199254740992   -> HTTP 200   (negative)
```

At 10^18 an attacker has ±64 of free divergence between what the hop in front reads and what the
tool executes — enough for the ids, offsets, quotas and byte counts an integer parameter is
normally used for.

Reachable through `Mcp-Name` and `MCP-Protocol-Version` too, wherever the body value is a JSON
integer, since `value_matches?/2` is shared by `check_named/4` and `compare_versions/3`.

The SHOULD this implements (`42.0` and `42` are equal) is satisfied by comparing decimal
representations or by an exact integer parse; it does not require float arithmetic. Note also
`Mcp-Param-maxRows: 4.2e1` against body `42` returns `200` — defensible under the SHOULD, but
worth knowing that the accepted header spellings of one integer are now unbounded.

**Not pinned.** `test/beam_mcp/transport/http_test.exs:932` tests `42` against `"42.0"` and stops
there.

## Finding 3 — BLOCKS PUBLISH

**`fault_response/4` is correct for the `call/2` copy and wrong for the `dispatch/3` copy: it
re-raises an exception a *host tool* raised, escaping the JSON-RPC envelope entirely.**

`lib/beam_mcp/transport/http.ex:249-256`, reached from `http.ex:663` (the `dispatch/3` rescue).

First, the verifications asked for, both positive:

- **The second copy does reach it.** A host tool raising a plain `RuntimeError` returns
  `{"error":{"code":-32603,...},"id":7,...}` with `HTTP 500`. The `id` is echoed, and only the
  `dispatch/3` copy knows `message["id"]` — `call/2` passes `nil`. The first fix did not miss half
  the problem this time.
- **Round 3's Bandit fix works.** A malformed chunked body (`Bandit.HTTPError`,
  `plug_status: :bad_request`), raw socket:

  ```
  post-delta 4911:  HTTP/1.1 400 Bad Request
  pre-delta  4912:  HTTP/1.1 500 Internal Server Error
  ```

Now the cost. The rule "re-raise anything whose `Plug.Exception.status/1` is not 500" is derived
from adapter-raised conditions, which only ever arrive in `call/2` (from `read_body_bounded/1`).
In `dispatch/3` the exceptions come from **host application code**, and Elixir host code raises
`plug_status`-carrying exceptions routinely — `Ecto.NoResultsError` is `404`, `Ecto.Query.CastError`
is `400`. (I measured a synthetic exception with `plug_status: 404`; I did not have `ecto` in the
tree, so treat the Ecto names as the well-known instance rather than as something I ran.)

```
$ curl -s -D - -X POST http://127.0.0.1:4911/ -H 'content-type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: boom_status' \
    --data-binary '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"boom_status","arguments":{}}}'
HTTP/1.1 404 Not Found
connection: close

(empty body)
```

Observed vs expected: expected `500` with `{"jsonrpc":"2.0","id":8,"error":{"code":-32603,
"message":"Internal error"}}`, per this module's documented contract at `http.ex:651-654`
(*"The response carries NO detail... an HTTP caller learns only that the request failed"*).
Observed a bare `404`, no body, no `jsonrpc`, no `id`, and the connection closed.

Two consequences, both concrete:

1. **`404` is load-bearing in this transport and now collides.** `http.ex:692-700` spends ten lines
   explaining that an unknown *tool* must be `200` and not `404`, because *"a conforming client
   responds by abandoning the endpoint and falling back. One mistyped tool name would have taken
   down the whole connection."* A host tool doing `Repo.get!(X, id)` on a tool argument now emits
   that exact `404` on a missing row — and the argument is caller-controlled, so the caller
   chooses when to fire it. The failure mode the delta reasoned its way out of is back through a
   different door.
2. **The envelope contract breaks silently.** No `id`, so a client cannot correlate the failure to
   its request; no JSON, so a client that parses every response body errors on it.

The leak check on this path is **clean**: I planted `planted-secret-PLUGSTATUS-sk_live_AAA111` in
the `plug_status` exception's message and `planted-secret-PLAIN-sk_live_BBB222` in the plain one,
and grepped every response body. Neither appears — the re-raised response has no body at all, and
the `500` path carries the constant string. Nothing leaks; the defect is availability and contract,
not disclosure.

Neither `CHANGELOG.md` nor `README.md` mentions this behaviour change —
`grep -n -i 'plug_status\|plug.exception\|re-rais\|reraise\|numerically\|integer' CHANGELOG.md README.md`
returns nothing. A host upgrading gets a new HTTP status class out of its own tool code with no
note.

Minimal fix: keep the rule in `call/2`, where the adapter raises, and let `dispatch/3` answer `500`
for everything host code throws at it — or re-raise in `dispatch/3` only for the exception modules
the adapter is known to raise. Both copies going through one function is the right instinct; the
rule they share is the outer one's.

## Finding 4 — FILE

**Case-insensitively colliding `x-mcp-header` names silently collapse, leaving one annotated
parameter entirely unenforced, with no warning.**

`lib/beam_mcp/transport/http.ex:529-542`. `annotations/2` accumulates into a map keyed by
`String.downcase(name)` (`:533`) and merges recursively (`:541`), so two properties annotated `Dup`
and `DUP` produce one entry and one of the two properties is never checked.

Probe tool `collide`: `alpha` → `"Dup"`, `beta` → `"DUP"`.

```
$ curl ... -H 'Mcp-Param-Dup: B' \
    --data-binary '{...,"params":{"name":"collide","arguments":{"alpha":"A","beta":"B"}}}'
{"id":1,...,"structuredContent":{"alpha":"A","beta":"B"}}
HTTP 200
```

`beta` is mirrored and checked; `alpha` carries a value, is annotated, has no header, and passes.
The MUST at `check_param_headers` — omitted header while the body carries the value — is not
enforced for it. Deterministic across three runs, and which of the two wins depends on map
iteration order, so with more properties it is not predictable from reading the schema.

Why FILE and not blocking: the spec makes such a tool definition invalid, so a host that hits this
has already violated a MUST. But the server accepts the invalid definition **silently** and serves
a weaker contract than the one it advertises in `tools/list` — the annotation is published to
clients and then not enforced. A `Logger.warning` at `init/1`, or a raise, would cost little.

## Finding 5 — FILE

**An `x-mcp-header` on a non-primitive property makes the tool permanently uncallable, with a
refusal that does not say why.**

`lib/beam_mcp/transport/http.ex:421-425`. The catch-all `value_matches?/2` returns `false` for
maps, lists, floats and everything else, so an annotated non-primitive can never match:

```
$ ...{"name":"nonprimitive","arguments":{"obj":{"k":"v"}}}   (no header)
{"error":{"code":-32020,"message":"Header mismatch: Mcp-Param-Obj header is required: the body carries a value to mirror"}}  HTTP 400

$ ...same, with -H 'Mcp-Param-Obj: anything'
{"error":{"code":-32020,"message":"Header mismatch: Mcp-Param-Obj header does not match the corresponding request body value"}}  HTTP 400

$ ...{"num":1.5} with -H 'Mcp-Param-Num: 1.5'
{"error":{"code":-32020,"message":"Header mismatch: Mcp-Param-Num header does not match the corresponding request body value"}}  HTTP 400
```

Both branches are closed: the client cannot omit the header and cannot supply one. Note `number`
is caught by this too, so a host that annotates a float property — an easy mistake, since the spec
allows `integer` — ships a tool nobody can call, and the refusal blames the client's header. Same
FILE reasoning as 4: the definition is invalid per spec, but the diagnosis belongs at `init/1`, not
as a permanent runtime `400` pointing at the caller. Refusing rather than interpolating the value
is right and I am not asking for that to change.

## Finding 6 — FILE

**`BeamMCP.ToolCatalog.fetch/2` is now public API and its `@spec` is not honest.**

`lib/beam_mcp/tool_catalog.ex:22-32`. `@spec fetch(module(), String.t() | atom()) :: {:ok, t} | :error`,
but three host-authored catalog shapes raise instead:

```
spec.name is a binary        -> RAISES ArgumentError          (Atom.to_string/1, :29)
all/0 returns a non-list     -> RAISES Protocol.UndefinedError (:29)
module not loaded            -> RAISES UndefinedFunctionError  (:29)
```

`init/1` guards the third for the transport's own use, and all three are host bugs rather than
attacker inputs, so this is low. But the function is documented as the one lookup every caller
should use, and a public function that says `:error` and raises will be called without a rescue.
Either widen the `@spec` and say so in the `@doc`, or make the clauses total.

## Out of the delta, noted so it is not lost

A host schema whose `properties` is not a map crashes the **core**, not the transport:

```
$ ...{"name":"badschema","arguments":{"x":1}}   ->  HTTP 500
** (BadMapError) expected a map, got: "not-a-map"
    (stdlib 7.1) :maps.find("x", "not-a-map")
    (beam_mcp 0.3.0) lib/beam_mcp/schema.ex:71: anonymous fn/3 in BeamMCP.Schema.check_properties/2
```

`lib/beam_mcp/schema.ex:71` is untouched by this delta and the trigger is host misconfiguration,
not caller input. The transport's own `annotations/2` handles the same schema correctly (falls to
the `%{}` clause). Recording it rather than counting it against this round.

---

## What I tried that found nothing

Every item below was probed against the live server and came back correct.

**Base64 sentinel scoping (round 3's fix 1) — holds.**
- `Mcp-Method: =?base64?dG9vbHMvbGlzdA==?=` with body `tools/list` → `400` `-32020`. Not decoded.
  This is the exact round-3 exploit; it is closed.
- `MCP-Protocol-Version: =?base64?MjAyNi0wNy0yOA==?=` → `400` `-32022`. Not decoded, and the
  refused value is echoed in `requested` rather than `List.first/1` of everything sent.
- `Mcp-Name: =?base64?ZWNobw==?=` with `params.name = "echo"` → `200`. The legitimate case works.
- Non-canonical trailing bits, `=?base64?ZWNobx==?=` → `400`. The re-encode round-trip at
  `http.ex:398` admits exactly one spelling, as claimed.
- **Sentinel wrapping a sentinel**: outer payload decoding to `=?base64?ZWNobw==?=` → `400`. One
  decode pass only; no recursion.
- **Mixed plain and sentinel on one header**: `Mcp-Name: echo` + `Mcp-Name: =?base64?ZWNobw==?=`
  → `200`. Every value is decoded and compared, not just the first.
- I looked for a sentinel whose decoded content is another header's value and found no path: the
  decode set is decided by the *canonical name this module passes in*, never by anything the
  client writes, and the header names themselves are matched by `get_req_header/2` byte-for-byte.

**Multi-value validation.** Duplicate `Mcp-Param-Region`, good-then-hostile and hostile-then-good
→ `400` both orders. `Enum.all?` over every value holds on the new param path too.

**The `Mcp-Param-{Name}` derivation (round 3's fix 2) — the MUST is enforced.**
- Header omitted, `region` in body → `400` `-32020` *"is required: the body carries a value to
  mirror"*. This is the spec row round 3 found unenforced; it is closed.
- Same for a **nested** annotation (`outer.inner` → `Nested`) → `400` when omitted, `200` when
  supplied. The property-path walk works.
- Header lies → `400`. Header matches → `200`.
- Header sent with no such value in the body, and with an explicit JSON `null` → `400` both.
- Annotation inside `items` and inside `oneOf` → **ignored**, request served `200`. `annotations/2`
  recurses through `properties` only (`http.ex:541`), which is what the spec's forbidden-chain rule
  requires. I confirmed the annotated values were present in the body and still not demanded.
- A `mcp-param-*` header the schema does not name → ignored (`200`), per the quoted
  forward-and-ignore rule. A hostile suffix (`Mcp-Param-../../etc/passwd`) never reaches this code:
  Bandit rejects the malformed header name at the parser with `400`.
- `Mcp-Param-*` on a non-`tools/call` method → ignored, `200`.

**Malformed JSON shapes into the new derivation — no crash, correct refusals.**
`params` a list, `params.name` a map, `params.arguments` a list, an annotated argument whose value
is a map, and a nested path whose parent is a list. All `400` or a `200` carrying the core's
`isError` result; none reached a `500`.

**`@removed_in_modern` — no bypass found.** `ping`, `initialize`, `notifications/initialized` with
an id → `404` `-32601`; as notifications → `202`; `"Ping"` (case) → `404` via the core;
`" ping"` (whitespace) → `400` at the header check; `"id": null` explicitly → `202`; a batch
array body → `400` *"Expected a JSON object, got an array"*; `initialize` carrying
`_meta` `"2025-11-25"` → `400`, so the legacy-era discriminator cannot be smuggled past the
transport's modern stamp. The pre-fix behaviour the CHANGELOG describes — `200` with
`protocolVersion: "2025-11-25"` — is gone.

**Leak sweep — clean.** Planted `sk_live_`-shaped secrets in a host exception message (plain and
`plug_status`-carrying), and checked the authorize-refusal, unknown-tool, unknown-method, header
mismatch, unsupported-version, oversized-body and parse-error bodies. Grepping every captured
response for `planted-secret`, `Elixir.`, `lib/beam_mcp` returns nothing. No reason term, no
stacktrace, no schema fragment and no body value reaches the caller. `authorize/1`'s reason goes to
`Logger.info` only, as `http.ex:298-301` claims. The one caller-visible reflection is the attacker's
own rejected header value in `data.requested`, which is their input coming back JSON-encoded.

**Header-population derivation.** `grep -n 'get_req_header' lib/beam_mcp/transport/http.ex` returns
one hit, `header_values/2` at `:377`. The claim at `http.ex:365-369` that every header read goes
through it is true of the delta; the `mcp-param-` sweep the old comment mentioned is gone with the
schema derivation.

**Ordering.** `check_headers/3` validates `Mcp-Name` (`:437`) before the param headers (`:438`), and
`mirrored_params/2` looks the tool up by `params.name` — so there is no window in which the
transport reads tool A's schema while tool B is dispatched.

**Suite state.** `mix test` in the copy: `126 tests, 0 failures`. The suite is green with findings
1, 2 and 4 live.
