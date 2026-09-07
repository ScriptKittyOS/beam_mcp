# Round 3 — lane r2 (resilience and documentation truth)

Tree read: `ebaaed0d918fed52e20af9031a1a8a71158bd3c9` (matches the brief; written to `logs/round3.r2.tree`).
Scope: `git diff a5cfb67b8a8854714cde36522292c9fc57e96d6a HEAD` — 13 files, 1845 insertions.

VERDICT: changes required

All probes ran in a copy at
`/tmp/claude-1000/-home-aylac-Projects-hacktui-hermes/775c8d71-6ac1-4653-8798-382001e76089/scratchpad/lane-r2`
(`cp -a` of the worktree, `.git` and `_build` removed, `MIX_ENV=dev mix compile`). The round-2
baseline comparison ran in a second copy at `.../scratchpad/lane-r2-round2`
(`git archive a5cfb67 | tar -x`, deps copied in). Every request below went over a real
`:gen_tcp` socket against a live `Bandit.start_link/1` on `127.0.0.1`, port 0 — no `Plug.Test`.
Probe scripts are in `.../scratchpad/probes/`. Nothing in
`/home/aylac/Projects/beam_mcp-wt/002-http` was modified except this file and
`logs/round3.r2.tree`.

Machine: 125 GiB RAM, ephemeral port range 32768–60999 (28,231 ports). Concurrency probes were
capped at **4,000** simultaneous in-flight at-cap requests and **12,000** held connections,
both well under port exhaustion. The 8,000-concurrent figure was reached by linear
extrapolation from five points, not measured directly; that is stated where it is used.

---

## Half 1 — the round-2 fixes hold. The delta reopened something else.

### The round-2 defects are closed. Measured, over sockets, at both body sizes.

`probes/p1_keepalive.exs`, 18 early-return paths × {16 KiB, 200 KiB} body. Every one returned a
bodied response, and a second request on the **same socket** was framed correctly every time.

```
########## BODY SIZE 16384 ##########
origin-refused-403         r1=403 (18ms)  body1=82   close=false  keepalive_r2=200 (7ms)
authorize-refused-403      r1=403 (0ms)   body1=73   close=false  keepalive_r2=403 (0ms)
authorize-badreturn-403    r1=403 (0ms)   body1=73   close=false  keepalive_r2=403 (0ms)
authorize-raise            r1=500 (2ms)   body1=78   close=false  keepalive_r2=500 (0ms)
authorize-throw            r1=500 (0ms)   body1=78   close=false  keepalive_r2=500 (0ms)
authorize-exit             r1=500 (0ms)   body1=78   close=false  keepalive_r2=500 (0ms)
missing-protocol-hdr       r1=400 (0ms)   body1=143  close=false  keepalive_r2=200 (0ms)
version-mismatch           r1=400 (0ms)   body1=150  close=false  keepalive_r2=200 (0ms)
method-hdr-mismatch        r1=400 (0ms)   body1=147  close=false  keepalive_r2=200 (1ms)
name-hdr-mismatch          r1=400 (0ms)   body1=145  close=false  keepalive_r2=200 (0ms)
dup-origin-good-then-bad   r1=403 (0ms)   body1=82   close=false  keepalive_r2=200 (0ms)
non-map-params             r1=400 (0ms)   body1=145  close=false  keepalive_r2=200 (0ms)
non-map-meta               r1=400 (1ms)   body1=118  close=false  keepalive_r2=200 (0ms)
map-body-value-in-msg      r1=400 (0ms)   body1=145  close=false  keepalive_r2=200 (0ms)
list-body-value-in-msg     r1=400 (0ms)   body1=145  close=false  keepalive_r2=200 (0ms)
mcp-name-invalid-utf8      r1=400 (0ms)   body1=145  close=false  keepalive_r2=200 (0ms)
parse-error-badjson        r1=400 (0ms)   body1=99   close=false  keepalive_r2=200 (0ms)
unknown-method-404         r1=404 (0ms)   body1=88   close=false  keepalive_r2=200 (0ms)
```
(The 200 KiB block is identical in status, body size and keep-alive outcome for all 18.)

Specifically:

* `Mcp-Name: \xFF\xFE`, which round 2 measured as **no response at all**, is now `400` with a
  145-byte JSON-RPC body. Closed.
* `authorize/1` raising, throwing and exiting — round 2's bare empty `500` — is now `500` with a
  78-byte `-32603` body. Closed.
* A non-map `"params"`, and a map or list body value that would have been interpolated into a
  refusal message, are now `400` with a real body. Closed.
* Keep-alive survives every path at 200 KiB, including the pre-`read_body` refusals
  (`origin`, `check_method`, `authorize`) where the conn still carries an unread 200 KiB body.
  The round-1 size-dependent misframing does not reproduce.

The cap boundary is exact (`probes/p4b.exs`): body `1_048_576` → `200`; body `1_048_577` → `413`
with `connection: close`. `2_000_000` → `413`.

### HIGH-1 — the widened rescue swallows Bandit's protocol statuses. `408` and `400` become `500`.

`lib/beam_mcp/transport/http.ex:160-170`

The delta moved the `rescue`/`catch` from wrapping `do_dispatch/3` to wrapping the whole of
`handle/2` (diff hunk at `+50..+57`). `Plug.Conn.read_body/2` is now inside it. Bandit signals
protocol-level failures by **raising `Bandit.HTTPError` with a `plug_status`** — see
`deps/bandit/lib/bandit/http_error.ex:5` (`defexception message: nil, plug_status: :bad_request`)
and `deps/bandit/lib/bandit/http1/socket.ex` `handle_timeout_with_disconnect_check!/1`
(`request_error!("Read timeout", :request_timeout)`). The transport's `rescue exception ->` now
catches those and answers `crash_response(conn)` = **`500`**.

Observed vs expected, same probe against both trees (`probes/p6_regress.exs`, `p8_cmp.exs`):

| input | round-2 tree `a5cfb67` | HEAD `ebaaed0` | expected |
|---|---|---|---|
| stalled body, `Content-Length: 16384` | `408` at 15.0 s, empty body | **`500`** at 15.0 s, `-32603` body | `408` |
| drip 1 B / 3 s, declared 16 KiB | (n/a) | **`500`** at 15.0 s | `408` |
| drip 1 B / 3 s, declared 1 MiB | (n/a) | **`500`** at 15.0 s | `408` |
| `Transfer-Encoding: gzip` | `400` | **`500`** | `400` |
| chunked, malformed chunk size | `400` | **`500`** | `400` |

```
===== ROUND-2 TREE (a5cfb67) =====
DRIP/STALL 16KiB declared -> status=408 at 15.0s body=""
===== HEAD TREE (ebaaed0) =====
DRIP/STALL 16KiB declared -> status=500 at 15.0s body="{\"error\":{\"code\":-32603,\"message\":\"Internal error\"},\"id\":null,\"jsonrpc\":\"2.0\"}"

=== ROUND-2 (a5cfb67) ===        === HEAD (ebaaed0) ===
Transfer-Encoding: gzip  400     Transfer-Encoding: gzip  500
malformed chunk size     400     malformed chunk size     500
```

Why this matters beyond the status code:

1. **It falsifies the delta's own documentation.** `README.md:156` and `CHANGELOG.md:95` both
   claim `408`. Measured at HEAD: `500`. See DOC-1.
2. **It is a semantic loss.** `408` tells a client to retry; `500` tells it the server is broken.
   `400` tells a client its framing is wrong; `500` does not.
3. **It is an unauthenticated log-and-alert amplifier.** Every dripped connection now emits an
   `[error]`-level stacktrace naming Bandit internals, and a 5xx that any 5xx-rate monitor will
   alarm on. One stalled connection, no authentication required:

```
13:29:19.127 [error] ** (Bandit.HTTPError) Read timeout
    (bandit 1.12.5) lib/bandit/http1/socket.ex:619: ...request_error!/2
    (plug 1.20.3) lib/plug/conn.ex:1184: Plug.Conn.read_body/2
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:268: BeamMCP.Transport.HTTP.read_body_bounded/1
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:188: BeamMCP.Transport.HTTP.handle/2
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:161: BeamMCP.Transport.HTTP.call/2
```

The moduledoc comment at `http.ex:172-183` argues the wide rescue "fixes the class, including
whatever nobody has thought of yet". That argument is sound for *host* and *decode* crashes. It
did not account for the fact that the transport's own framing layer uses exceptions as its
status-signalling channel. The fix is to re-raise rather than flatten: match
`Bandit.HTTPError`/`Plug.Exception`-implementing exceptions (or check
`Plug.Exception.status/1 != 500`) and re-raise them so Bandit maps them, and keep
`crash_response/1` for everything else. Both `rescue` sites need it — the one at `162` and the
one at `506`.

### Header handling: bounded, but by Bandit, not by this package.

`check_param_headers/3` (`http.ex:390-403`) iterates `conn.req_headers`. The brief's three
questions, measured (`probes/p2_headers.exs`, `p3_raw.exs`):

| input | result | who bounded it |
|---|---|---|
| 40 `Mcp-Param-*` headers | `400`, 149-byte body | reached the Plug |
| 49 / 60 / 200 / 10,000 `Mcp-Param-*` headers | `HTTP/1.0 431 Request Header Fields Too Large` | Bandit, `max_header_count` default **50** (`deps/bandit/lib/bandit/http1/socket.ex:151`) |
| `mcp-param-` + 5,000 B suffix | `400`, **5,147**-byte body | reached the Plug |
| `mcp-param-` + 9,900 B suffix | `400`, **10,047**-byte body | reached the Plug |
| `mcp-param-` + 100,000 B suffix | `431` | Bandit, `max_header_length` default **10,000** (`socket.ex:150`) |
| `Mcp-Name: =?base64?<9,500 B>?=` | `400`, 145-byte body | reached the Plug |
| `Mcp-Name: =?base64?<10 MB>?=` | `431` | Bandit, `max_header_length` |
| header name with `\xFF\xFE` | `HTTP/1.0 400 Bad Request` | Bandit's header parser |

So: **no unbounded work, no crash, no hang, and the bound comes entirely from Bandit's HTTP/1
defaults, not from this package.** `Base.decode64` is fed at most 10,000 bytes.
`Enum.uniq |> Enum.reduce_while` runs over at most 50 names. That is the right answer, but it is
an inherited one — see DOC-5.

### LOW-2 — the attacker-controlled header *name* is reflected verbatim into the refusal body.

`lib/beam_mcp/transport/http.ex:411` and `:418-421`

`check_named/4` interpolates `header_name` into the `-32020` message, and for `mcp-param-*` that
name comes straight from `conn.req_headers`. A 9,910-byte header name produced a 10,047-byte
response body:

```
mcp-param name 9900B (max-ish)
  HTTP/1.1 400 Bad Request ... content-length: 10047 ...
  {"error":{"code":-32020,"message":"Header mismatch: mcp-param-aaaaaaaa…
```

Observed: attacker-chosen bytes echoed to the caller. Expected: either a fixed message, or the
name truncated. It is **not** an amplification vector — ratio is ~1:1 and Bandit caps the input
at 10,000 bytes — and the value is JSON-encoded so there is no injection. But it is the same
shape as the defect the delta fixed three functions away (`http.ex:425-428`: body values must not
be interpolated); header *names* were not brought into that rule, and the mitigation is a
dependency default rather than anything this module does. Recommend truncating the name in the
message, or dropping it in favour of a count.

### LOW-1 — `decode_header_value/1` is applied wider than the MUST it cites, and inconsistently.

`lib/beam_mcp/transport/http.ex:325-348`, `:466-492`

The code's own quoted MUST (`:325-326`) scopes decoding to "an encoded `Mcp-Name` or
`Mcp-Param-{Name}` value". `CHANGELOG.md` documents it the same way: "`=?base64?…?=` on
`Mcp-Name` / `Mcp-Param-{Name}`". But decoding lives in `all_match?/2`, which every header read
goes through. Measured (`probes/p12_impl.exs`):

| header, base64-encoded | result | documented? |
|---|---|---|
| `Mcp-Name: =?base64?ZWNobw==?=` | `200`, dispatched | yes |
| `Mcp-Param-region: =?base64?ZXUtd2VzdDE=?=` | `200`, dispatched | yes |
| `Mcp-Method: =?base64?dG9vbHMvY2FsbA==?=` | **`200`, dispatched** | **no** |
| `MCP-Protocol-Version: =?base64?MjAyNi0wNy0yOA==?=` | **`400` `-32022`**, `"requested":"=?base64?MjAyNi0wNy0yOA==?="` | **no** |

Two separate issues. First, `Mcp-Method` is decoded although the spec's decode MUST does not
name it: a load balancer routing on the raw `=?base64?dG9vbHMvY2FsbA==?=` and a server executing
the decoded `tools/call` is precisely the header/body divergence the MUST was scoped to bound,
and this widens that surface by one header without saying so. Second, `compare_versions/3` is
internally inconsistent — the body-match branch (`:473`, via `all_match?`) decodes, and the
supported-version branch (`:477`, `&(&1 == @modern_version)`) compares raw. The outcome today is
a refusal, which is safe; it is a trap for whoever next adds a version to the supported set.
The CONVENTIONS.md rule the delta adds ("every place a mechanism reads the same kind of input is
one mechanism") produced the single read path correctly, and then applied its *transformation*
to two headers the derivation never argued for.

---

## Half 2 — the documented numbers

Every number in the new README/CHANGELOG paragraphs is transcribed from
`logs/round2.r2.md:172-350`, which measured the **round-2 tree**. The same delta then changed the
behaviour behind two of them. That is the failure mode CONVENTIONS.md's own new section names —
a record written once and not re-derived after the tree moved under it.

### Claim table

| # | claim | file:line | measured at `ebaaed0` | verdict |
|---|---|---|---|---|
| 1 | `authorize/1` reading a 119-byte body → `200` | README:156, CHANGELOG:95 | `200` (my minimal body was 151 B; small body succeeds) | **holds** (kind) |
| 2 | 16 KiB body read in `authorize/1` → `408` at 15.0 s | README:156, CHANGELOG:95 | **`500`** at 15.0 s | **FALSE** |
| 3 | 200 KiB body read in `authorize/1` → `408` at 15.0 s | README:156, CHANGELOG:95 | **`500`** at 15.0 s | **FALSE** |
| 4 | connection dead afterwards | README:155, CHANGELOG:94 | follow-up on same socket → `:error` | **holds** |
| 5 | ~1.05 MiB per in-flight request at the cap | README:166 | 1,047 KiB (1.023 MiB) BEAM total; 1,094–1,228 KiB RSS | **holds** |
| 6 | linear, no plateau | README:166-167 | 256.4 / 511.4 / 1023.1 / 2044.4 / 4090.4 MiB at N = 250/500/1000/2000/4000 — linear to 4 significant figures | **holds** |
| 7 | to 8,000 concurrent, +8.16 GiB RSS | README:167 | not measured (capped at 4,000); RSS delta 4,274.7 MiB at 4,000 → 8.35 GiB extrapolated | **corroborated, not reproduced** |
| 8 | ceiling `num_acceptors * num_connections` | README:168 | `acceptor_supervisor.ex:51` sets `max_children: config.num_connections` per acceptor | **holds** |
| 9 | defaults 100 × 16,384 = 1,638,400 | README:169 | `num_acceptors` = **100** counted live at runtime; `num_connections` default **16_384** (`thousand_island.ex:122,137`). 100 × 16,384 = 1,638,400 | **holds** |
| 10 | `@max_body_bytes` is a floor, not a ceiling | README:170-172 | 1,064,960–1,568,768 bytes written before the `413`, vs a 1,048,576 cap | **holds (shape)** |
| 11 | 1,769,325 bytes read before refusing a declared 32 MiB body | README:172 | not reproduced in 20 trials; range 1,064,960–1,568,768 | **FALSE as stated** |
| 12 | read timeout is 15,000 ms | README:174 | 15.0 s measured on every timeout path | **holds** |
| 13 | it is Bandit's and inherited | README:173-174 | `Keyword.get(opts, :read_timeout, 15_000)` at `deps/bandit/lib/bandit/http1/socket.ex:251,302,333`; `read_body_bounded/1` passes only `length:` (`http.ex:268`) | **holds** |
| 14 | whole-body deadline, not a per-read reset | README:175 | drip 1 B/3 s answered at 15.0 s for both a 16 KiB and a 1 MiB declared body | **holds in practice** (see note) |
| 15 | drip client answered `408` at 15 s | README:175-176 | **`500`** at 15.0 s | **FALSE** |
| 16 | 16,500 held connections = 243 MiB | README:176 | 12,000 opened → +50.8 MiB BEAM total / +79.5 MiB RSS, but connections die at the 15 s deadline so the count is not a steady state | **not reproducible as stated** |
| 17 | a legitimate request still served in 0.00 s | README:176-177 | `200` in 0.01 s / 0.0 s / 0.0 s at 2,000 / 6,000 / 12,000 held | **holds** |
| 18 | `405` on non-POST | README:213 | `405` + `Allow: POST` for GET and DELETE | **holds** |
| 19 | `404` for an unimplemented method | README:213 | `404`, `-32601`, `"Method not found: zz/zz"` | **holds** |
| 20 | `200` + JSON-RPC error for an unknown tool | README:213 | `200`, `-32601`, `"Unknown tool: nosuch"` | **holds** |
| 21 | every header checked in all values | README:213-215 | good-then-bad `Origin` → `403`; five duplicate-header tests in the delta | **holds** |
| 22 | sessions / `Mcp-Session-Id` not implemented | README:215-216 | `Mcp-Session-Id: abc` ignored, no session state | **holds** |
| 23 | `initialize` not implemented | README:216-217 | **`200`** with a full initialize result | **FALSE** |

Note on 14: the claim is true at the sizes this package uses, but for the reason the README does
not give. `read_exactly!/5` (`socket.ex:400-425`) passes `read_timeout` to *each* `recv`, so the
mechanism is per-read. It behaves as a whole-body deadline only because `:gen_tcp.recv/3` with an
explicit length is an absolute deadline for that call and `read_length` defaults to 1,000,000 —
so a body at the 1,048,576 cap needs at most two reads. Measured at both 16 KiB and 1 MiB: 15.0 s.
The claim holds; the stated reason does not, and it would stop holding if `@max_body_bytes` were
raised much above 1 MiB.

### HIGH-2 — README:216-217 says `initialize` is not implemented. It is, and it answers with the wrong revision.

`README.md:215-217` vs `lib/beam_mcp/server.ex:118-130` and `lib/beam_mcp/transport/http.ex:516-521`

```
$ POST /mcp  {"method":"initialize", "_meta":{"…/protocolVersion":"2026-07-28"}, …}
HTTP initialize -> 200
{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{"listChanged":false}},
 "protocolVersion":"2025-11-25","serverInfo":{"name":"beam_mcp","version":"0.3.0"}}}
```

Observed: `200` with a legacy-revision handshake result. Expected per README:216: not
implemented — and per the transport's stated contract, `404` (it is a method this revision does
not have), or at minimum not a `2025-11-25` negotiation from an endpoint whose moduledoc
(`http.ex:13`) says it serves `2026-07-28` and nothing else.

This is not a subtle inference. **The README contradicts itself 31 lines later**, at
`README.md:247`: "`initialize` are matched *before* the revision switch, so neither is affected
by what a `_meta` says." That sentence is correct and is exactly why the transport cannot exclude
it: `do_dispatch/3` (`http.ex:520-521`) stamps `_meta` with `2026-07-28` and then hands the
message to `Server.handle_message/2`, whose `initialize` clause (`server.ex:119`) matches ahead
of the era switch. The code comment at `http.ex:517-519` — "the core decides era from the
message, and the transport guarantees the message says so" — is therefore false for exactly one
method, and that method is the one the README lists as absent.

Mitigating: `Server.new(opts.server_opts)` is called fresh per request (`http.ex:523`), so the
`initialized?: true` transition does not survive the response and there is no cross-request state.
The defect is the false documentation plus a caller being handed a revision the endpoint does not
speak.

### DOC-1 — the two `408` claims (severity: HIGH, folded into HIGH-1)

`README.md:156`, `CHANGELOG.md:95`. Both state `408`; both measure `500` at HEAD. Both are
verbatim from `logs/round2.r2.md:172-173`, taken against `a5cfb67` where `408` was correct. The
correct remedy is to fix the code (HIGH-1) rather than the sentence — `408` is the right answer.

### MEDIUM-1 — `1,769,325` is a single-run artifact of the measuring client, stated as a property.

`README.md:172`

`round2.r2.md:304` says "**up to** 1,769,325 bytes". README:172 states it as "a declared 32 MiB
body **had** 1,769,325 bytes read", turning the maximum of a run into a point measurement of the
package. 20 trials at four different client `sndbuf` settings (`probes/p4c.exs`):

```
sndbuf 16 KiB   [1286144, 1150976, 1085440, 1064960, 1155072]  min=1064960 max=1286144
default sndbuf  [1114112, 1208320, 1196032, 1114112, 1101824]  min=1101824 max=1208320
sndbuf 1 MiB    [1224704, 1212416, 1118208, 1224704, 1196032]  min=1118208 max=1224704
sndbuf 4 MiB    [1568768, 1130496, 1212416, 1171456, 1191936]  min=1130496 max=1568768
default client socket opts: [sndbuf: 2626560, recbuf: 131072, buffer: 9216]
```

Observed: 1,064,960–1,568,768, spread with the client's socket buffers, never 1,769,325. Expected:
a number a reader can reproduce. What the *server* reads is `min(content_length, 1_048_576)` —
exactly the cap (`do_read_content_length_data!`, `socket.ex:248`) — plus whatever header-parse
read left buffered. The excess a client observes is kernel socket buffering on both ends and is
machine-specific. The claim's shape ("a floor, not a ceiling") is correct and worth keeping;
the digits should become a range, or "somewhat more than the cap, depending on socket buffers".

### MEDIUM-2 — not one of the ten new numeric claims is pinned.

`test/beam_mcp/readme_claims_test.exs` is **untouched** by the delta
(`git diff --stat a5cfb67..HEAD -- test/beam_mcp/readme_claims_test.exs` is empty), and:

```
$ grep -rn "408\|read_timeout\|1_769_325\|1769325\|1_638_400\|1638400\|1\.05 MiB\|8000 concurrent\|16,500\|16500" test/
(no matches)
```

The delta's 26 new tests in `http_test.exs` cover the header-validation and rescue behaviour well
— five duplicate-header tests, three `Mcp-Param` tests, three base64 tests, the 404/200 split, the
non-string body values, and the raise/throw/exit rescue. None of them touch a number in the
README. That file's own moduledoc already flags the gap ("Nothing enumerates the README's claims
and proves each has a test"); the delta added ten more claims to the unpinned side and, in three
cases, the unpinned number is now wrong. The three that are wrong are precisely the ones a test
would have caught: `408` is a two-line socket test, and `initialize` is a one-line one.

### LOW-3 — the resource section omits the bound that is actually doing the work on headers.

`README.md:164-177` enumerates what the Plug does and does not bound: body size, aggregate memory,
bytes read, time. It does not mention headers at all, and headers are the one attacker-controlled
input `check_param_headers/3` iterates. The real bounds are Bandit's `max_header_count: 50` and
`max_header_length: 10_000` (`deps/bandit/lib/bandit/http1/socket.ex:150-151`), demonstrated above
by `431` responses. Given that the section's whole argument is "here is what is yours and what is
your server's", a fourth bullet naming the header bounds as the server's belongs in it.

### LOW-4 — "16,500 such connections held 243 MiB" describes a transient, not a hold.

`README.md:176`. Such connections cannot be *held*: each dies at the 15 s deadline the same
sentence describes. Measured at 2,000 / 6,000 / 12,000 opened (`probes/p14_hold.exs`), with
attrition already under way inside the measurement window:

```
held=2000   d_total=43.4MiB   d_rss=69.8MiB  legit_request=200 in 0.01s
held=6000   d_total=52.3MiB   d_rss=80.4MiB  legit_request=200 in 0.0s
held=12000  d_total=50.8MiB   d_rss=79.5MiB  legit_request=200 in 0.0s
```

The point the sentence is making — the timeout bounds the slow-client cost, and service is
unaffected — is **correct and confirmed** (a legitimate request was served in ≤0.01 s throughout).
Only the framing of 16,500 as a sustained population is wrong, and it is the framing that makes
the 243 MiB figure unreproducible: the denominator is a moving target.

---

## Corrections to my own measurements

Stated explicitly, per the brief.

* My first run of `probes/p4_floor.exs` reported `status=` (none) for all three 32 MiB trials.
  That was a bug in **my** probe — the polling loop consumed the response into a discarded binding
  — not a missing response from the server. Corrected in `p4b.exs`, which shows `413` with
  `connection: close` on all five trials. **This correction makes the package look better**, and
  I am flagging it as such.
* My first cap-boundary run reported a `1_048_577`-byte body returning `200`. That was also my
  bug: my padding arithmetic produced a 1,048,536-byte body, under the cap. Corrected in `p4b.exs`
  with exact sizes: `1_048_576` → `200`, `1_048_577` → `413`. **Also makes the package look better.**
* `probes/p14_hold.exs` rebinds a counter inside a comprehension, which does not accumulate in
  Elixir; the three rows are 2,000 / 6,000 / 12,000 cumulative opens, not 2,000 / 4,000 / 6,000.
  I have labelled them with what actually happened rather than what I intended. This gave me
  *more* coverage than planned, so it does not weaken the conclusion, but the per-connection KiB
  figures from that probe are unusable (dead connections in the denominator) and I have not
  quoted them.
* Claim 7 (8,000 concurrent) is extrapolated from five measured points capped at 4,000, not
  measured. I have not marked it "holds".
* Claim 1 (119 bytes) I could not reproduce exactly — my minimal valid message for this catalog
  is 151 bytes. I verified the kind (a small body succeeds) rather than the digit.

---

## Summary of findings

| id | sev | file:line | headline |
|---|---|---|---|
| HIGH-1 | HIGH | `lib/beam_mcp/transport/http.ex:160-170` | The widened rescue swallows `Bandit.HTTPError`; read timeout `408`→`500`, bad transfer-encoding `400`→`500`, malformed chunked `400`→`500`. Regression vs `a5cfb67`, and an unauthenticated 5xx + error-stacktrace amplifier. |
| HIGH-2 | HIGH | `README.md:216-217` | Claims `initialize` is not implemented; it returns `200` with `protocolVersion: "2025-11-25"`. Contradicted by `README.md:247` in the same file. |
| DOC-1 | HIGH | `README.md:156`, `CHANGELOG.md:95` | Both claim `408`; both measure `500`. Fix the code (HIGH-1), not the sentence. |
| MEDIUM-1 | MEDIUM | `README.md:172` | `1,769,325 bytes` is unreproducible (20 trials: 1,064,960–1,568,768) and is a client-socket-buffer artifact stated as a package property. |
| MEDIUM-2 | MEDIUM | `test/beam_mcp/readme_claims_test.exs` | Untouched by the delta; none of the ten new numeric claims is pinned. The three wrong ones are exactly the two-line tests. |
| LOW-1 | LOW | `http.ex:325-348`, `:466-492` | Base64 decoding applied to `Mcp-Method` (outside the quoted MUST, and undocumented) and half-applied to `MCP-Protocol-Version` (`:473` decodes, `:477` does not). |
| LOW-2 | LOW | `http.ex:411`, `:418-421` | Attacker-controlled header *name* reflected verbatim into the refusal body (10,047 B out for 9,910 B in); bounded only by Bandit's `max_header_length`. |
| LOW-3 | LOW | `README.md:164-177` | The resource section omits header bounds, which are Bandit's (`max_header_count: 50`, `max_header_length: 10_000`) and are what actually bounds `check_param_headers/3`. |
| LOW-4 | LOW | `README.md:176` | "16,500 such connections held 243 MiB" is a transient, not a hold — those connections die at the 15 s deadline the same sentence describes. |
