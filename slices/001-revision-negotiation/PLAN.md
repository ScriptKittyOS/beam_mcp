<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 001 — Revision negotiation and `server/discover`

**Written before any code.** Every claim about the specification below was fetched from
`modelcontextprotocol.io` on 2026-09-06, not recalled: the current revision post-dates this
agent's training data, so nothing here is asserted from memory.

## The gap, demonstrated

Run against the server as it stands at `1ac057e`:

    server/discover
      -> {"error":{"code":-32601,"message":"Method not found: server/discover"}}

    tools/list carrying modern _meta, no initialize
      -> {"result":{"tools":[...]}}          <-- ANSWERED, as if legacy

    initialize
      -> {"result":{"protocolVersion":"2024-11-05",...}}

**The second line is the defect, not the first.** A missing method is an honest error a client
can act on. Answering a `2026-07-28` request with a `2024-11-05`-shaped result is the
specification's own worst case — its compatibility matrix says a modern client against a legacy
server "may reject the request, stay silent, **or even process an era-ambiguous method under
legacy semantics**". That result omits `resultType`, omits `_meta` `serverInfo`, and omits the
`ttlMs`/`cacheScope` that `2026-07-28` **requires** on `tools/list`. It looks like success.

## What the specification actually says

**Five revisions, not four.** Derived from the changelog chain, each page naming its
predecessor:

    2024-11-05  ->  2025-03-26  ->  2025-06-18  ->  2025-11-25  ->  2026-07-28 (current)

**The split is by era, not by revision.** The spec defines the terms itself:

> **Modern**: protocol versions that convey version, identity, and capabilities as
> per-request metadata (revision `2026-07-28` and later).
> **Legacy**: protocol versions that establish a session with an `initialize` handshake
> (`2025-11-25` and earlier).
> **Dual-era**: an implementation that supports both.

So negotiation is **two mechanisms**, exactly as the owner said:

| | Legacy client | Modern client |
|---|---|---|
| opens with | `initialize`, then `notifications/initialized` | any request, or `server/discover` |
| carries version in | the `initialize` params | `_meta` `io.modelcontextprotocol/protocolVersion`, per request |
| session | yes, protocol-level | none; every request stands alone |

**How a dual-era server tells them apart from the first message** — quoted:

> A dual-era **server** selects its behavior from how the client opens:
> * A request carrying modern per-request `_meta` is served statelessly according to this revision.
> * An `initialize` request selects legacy semantics.

That is the whole discriminator, and it is cheap: presence of `_meta` protocol version, or the
method being `initialize`.

**`server/discover` is mandatory.** *"Servers **MUST** implement `server/discover`."* Clients
**MAY** call it first; on stdio it is also the backward-compatibility probe — a client sends it
and falls back to `initialize` on any error that is not a recognised modern error.

**Version rejection has a defined shape and code**, `-32022`:

    {"error":{"code":-32022,"message":"Unsupported protocol version",
              "data":{"supported":["2026-07-28","2025-11-25"],"requested":"1900-01-01"}}}

Note `-32022`, not `-32004`: the codes were renumbered in this revision under a new allocation
policy, and the old numbers are the draft's.

**Also removed in 2026-07-28, and we implement two of them:** `initialize`,
`notifications/initialized`, **`ping`**, `logging/setLevel`. All results gain a required
`resultType`. `tools/list` results gain required `ttlMs` and `cacheScope`.

## JSON-RPC batching — answered, and it decides nothing here

    added   2025-03-26   "Added support for JSON-RPC batching"
    removed 2025-06-18   "Remove support for JSON-RPC batching"

**Batching is required in exactly one revision of the five.** Neither candidate compat revision
below is that one, so **the server neither accepts nor emits batches**, and that is a
consequence of the revision choice rather than a separate decision. Recorded because the
question was asked and the answer is a reason to avoid `2025-03-26` as a compat choice.

## Proposed supported set — derived, with one gap named

**`2026-07-28` (modern) + `2025-11-25` (legacy).** Two revisions, not five.

Derivation:

1. The current revision is mandatory for the package to be worth publishing at all; that is
   the whole reason this slice precedes a release.
2. The spec's compatibility model is **era-based**. A dual-era server needs *one* legacy
   revision to serve handshake clients — supporting several buys nothing, because a legacy
   client that cannot use the one offered has no fall-forward either way.
3. Of the four legacy revisions, `2025-11-25` is the newest, so it covers the most clients.
4. It also avoids `2025-03-26`, the only revision that requires batching.

**The gap, stated rather than glossed:** the delta between what this server implements today
(`2024-11-05`) and what `2025-11-25` requires is **not yet measured**. That measurement is the
first task of this slice, before any negotiation code. If it proves large, the alternative is
`2026-07-28` + `2024-11-05` — keeping the legacy side exactly where it is and spending the
budget on the modern side. **The PLAN does not pre-decide that; it names the measurement that
settles it.**

## Order of work

1. **Measure the `2024-11-05` -> `2025-11-25` delta** for a tools-only server. Report before
   writing negotiation code. This decides the legacy revision.
2. **`server/discover`**, red first: the demonstration above is the red.
3. **The era discriminator** and per-request `_meta` handling, red first per era.
4. **`UnsupportedProtocolVersionError`** with `-32022` and the `supported`/`requested` shape.
5. **`resultType`**, and `ttlMs`/`cacheScope` on `tools/list`, for modern responses only.
6. **Decide `ping`.** Removed in `2026-07-28`, present here. It stays for legacy and must not
   be advertised as modern.

## Out of scope

Streamable HTTP, `subscriptions/listen`, MRTR, tasks, authorization, elicitation, sampling,
roots. This slice is stdio and version handling. MRTR is named in the project's own later
scope and is not smuggled in here.

## Deliverable alongside

`CHANGELOG.md`, seeded from the seven commits to date and carrying this slice's entry.

---

# Step 1 — the `2024-11-05` -> `2025-11-25` delta, measured

Owner ruling 2026-09-06: the pair is **`2026-07-28` + `2025-11-25`**, gated on this
measurement, with `2026-07-28` + `2024-11-05` as the fallback if the delta measures large.
**It does not. The delta is small, so the ruling stands and the fallback is not taken.**

Derived by walking all three intervening changelogs and filtering to what a **tools-only stdio
server** must do. Auth, Streamable HTTP, elicitation, sampling, roots and tasks are excluded
because this server implements none of them and none is mandatory for a tools-only server.

## Already compliant — measured against the running server, not assumed

| item | revision | evidence |
|---|---|---|
| Tool annotations | 2025-03-26 | emits `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint` |
| Structured tool output | 2025-06-18 | emits `structuredContent` alongside `content` |
| Input-validation errors are **Tool Execution Errors, not Protocol Errors** (SEP-1303) | 2025-11-25 | an invalid call returns a `result` with `isError: true`, **not** a JSON-RPC error |
| No JSON-RPC batching | added 2025-03-26, removed 2025-06-18 | never implemented; correct for a 2025-11-25 target |
| stderr may carry all logging | 2025-11-25 | clarification, permissive |

**Three of the four substantive 2025-era items for this server class are already done.** That
is the finding: the legacy side is much closer to `2025-11-25` than its advertised
`2024-11-05` suggests.

## Real work on the legacy side — one item

**`initialize` ignores the version the client asks for.** Measured:

    request  {"method":"initialize","params":{"protocolVersion":"2025-11-25"}}
    response {"result":{"protocolVersion":"2024-11-05", ...}}

The server answers with a compiled-in constant whatever it is asked. Lifecycle operation went
**SHOULD to MUST** in `2025-06-18`, so this is non-conformant for any legacy revision after
`2024-11-05`. **It is needed for whichever compat revision is chosen**, so it is not a cost of
picking `2025-11-25`.

## Small, and optional

- **JSON Schema 2020-12 as the default dialect** (2025-11-25). This validator is a deliberate
  subset; the work is declaring the dialect and confirming the subset does not contradict it.
- `title`, `icons`, and `description` on `Implementation` are all **optional** and are not
  adopted by this slice.

## Found while measuring, and not a revision item

**The error payload leaks Elixir syntax onto the wire:**

    "structuredContent":{"error":"%{reason: \"invalid arguments: missing required property: a\", tool: :t}"}

That is `inspect/1` output on a map, reaching a client that has no reason to parse Elixir. It
is a defect at every revision, independent of this slice, and it is recorded rather than fixed
here.

## `ping` — the owner's added item

Measured: `{"method":"ping"}` returns `{"result":{}}` today.

`ping` is **removed in `2026-07-28`** (major change 5). So the two eras must disagree, and the
hazard is precisely that a shared handler answers both:

- **Legacy era** — `ping` is answered, as now. Correct for `2025-11-25` and earlier.
- **Modern era** — `ping` **does not exist**. A modern request for it gets method-not-found,
  the same as any unknown method. **The legacy handler must not inherit it**, and a test
  asserts a modern-era `ping` is refused while a legacy-era `ping` succeeds.

## Amendments to this PLAN, per the owner

1. **Batching is asserted, not merely absent.** A test asserts the server neither accepts nor
   emits JSON-RPC batches, at both eras, so its absence is a property rather than an accident.
2. **`-32022`** is the `UnsupportedProtocolVersionError` code, per the revision's error-code
   allocation policy. **Most secondary sources still show `-32004`**, the draft number, which
   was renumbered in this revision along with `HeaderMismatch` (`-32001` to `-32020`) and
   `MissingRequiredClientCapability` (`-32003` to `-32021`). Anyone checking this against a
   blog post or an SDK written before the renumbering will find the old value.
3. **`CHANGELOG.md`** records the red's second line, in those words, as the reason `0.1.0` was
   not published at `c5da02f`: *a `2026-07-28` request answered with a `2024-11-05`-shaped
   result that looks like success.*

## Verdict

**Proceed with `2026-07-28` + `2025-11-25`.** The fallback is not needed. The legacy-side work
is one item — honouring the requested version in `initialize` — which any compat choice
requires anyway.
