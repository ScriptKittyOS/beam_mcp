<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 002 — stateless Streamable HTTP, and the conformance gap that ships with it

**Written before any code.** Release **0.3.0**. Base `origin/main` at `bee3d26` (published
`0.2.0`). Worktree `/home/aylac/Projects/beam_mcp-wt/002-http`, its own `_build` and `deps`.

Every specification claim below is quoted from an **archived** page, not recalled:
`logs/spec-streamable-http.md` (fetched by `curl -sSL --fail`, 31525 bytes),
`logs/spec-changelog.md` and `logs/spec-basic-versioning.md` (carried forward from the earlier
slice that fetched them).

## 1. What an HTTP request with no era established gets — answered before any code

**This is SCR-255's question, and the transport specification answers half of it for us.**

    Every POST request to the MCP endpoint **MUST** include an
    `MCP-Protocol-Version` header.
    The header value **MUST** match the `io.modelcontextprotocol/protocolVersion`
    field carried in the request body's `_meta`. If the values do not match, the
    server **MUST** reject the request with `400 Bad Request` and a `HeaderMismatch`
    JSON-RPC error.
                                              -- logs/spec-streamable-http.md:252-261

So **the bare-request path that exists on stdio cannot exist over conformant HTTP.** On stdio a
client may send `tools/call` with no `initialize` and no `_meta`, and the package serves it —
SCR-255's measurement. Over HTTP the same request is malformed: the header is mandatory, and it
must agree with the body. A Plug that enforces the header refuses the no-era request as a
protocol matter, not as a policy choice.

**That closes the era half and closes none of the authorization half.** A request can carry a
perfect `MCP-Protocol-Version` header and still be from anyone who can reach the port.
`tools/call` executes through the host's dispatch. That is the confused-deputy shape, and the
header requirement does nothing about it.

### The answer, in the required form

**The package makes refusal inescapable; it does not decide who may call.**

`BeamMCP.Transport.HTTP` takes a **required option with no default**: an authorization function
supplied by the host. A host that wires the Plug without it **fails at start, not at request
time**.

Why this and not the alternatives:

- **The package cannot decide who may call.** It has no view of the host's identity model. A
  package that authorized on the host's behalf would be claiming something it cannot keep — the
  same over-claim this repository has spent five slices removing from prose.
- **"The host should authenticate" is not a control.** SCR-255 already records that a requirement
  nobody is told about is not a control; a requirement everybody is *told* about is not one
  either. A README paragraph is documentation. **A required argument with no default is a
  contract**, because the host cannot start without answering it.
- **Serving `tools/call` to any caller that reaches the port is the hazard**, and shipping it with
  a footnote would be the package putting a confused-deputy surface on a port and calling the
  consequence someone else's.

**Origin validation is a second required decision, and the spec makes it a MUST:**

    Servers **MUST** validate the `Origin` header on all incoming connections to
    prevent DNS rebinding attacks. If the `Origin` header is present and invalid,
    servers **MUST** respond with HTTP 403 Forbidden.
                                              -- logs/spec-streamable-http.md:57-61

"Valid" is host knowledge. So the allowed origins are a **second required option with no
default**, for the same reason and by the same mechanism.

**Recorded as reversible**: this is the coordinator's call, flagged to the owner. If a materially
better mechanism appears while building, it is raised before being built, not substituted.

## 2. Scope — three things, one release

1. **SCR-253 / 002 — stateless Streamable HTTP.** A Plug on Bandit at `/mcp`, the `2026-07-28`
   stateless model: **no sessions, no `Mcp-Session-Id`, no SSE resumability** (changelog items 1
   and 9). `handle_message/2` **does not change** — this is a second caller of the existing core.
   **Bandit and Plug only**; nothing else added.
2. **SCR-261 — `ttlMs` and `cacheScope` on `tools/list`.** Verified against the archived spec
   rather than the issue: *"Require `ttlMs` and `cacheScope` fields on results returned by
   `tools/list` … via a new `CacheableResult` interface."* Ships **with** HTTP rather than after,
   because serving a non-conformant modern era over a public port is worse than over a pipe.
   Both values are host knowledge (a freshness hint about the host's catalog; a disclosure
   decision about shared caches), so they are supplied, not invented — `cacheScope` defaulting to
   the **non-permissive** value if the host says nothing.
3. **001c's shipped code, carried; its slice record dropped.** `README.md` requirement, the policy
   test, and `CHANGELOG.md` into `files:`. The code is correct and was reviewed; the seven rounds
   of archive discipline around it are not re-run.

**Already found by carrying it, and worth recording:** moving the version to `0.3.0` made the
carried policy test **fail** — the README still said `~> 0.2.0`, which does not admit `0.3.0`.
That test was written in 001c to catch exactly this and this is its first real use. README moved
to `~> 0.3.0`.

## 3. Red first — one per scope item, before any implementation

| # | red | shows |
|---|---|---|
| 1 | an HTTP request against today's package | there is no endpoint: nothing listens, no Plug exists |
| 2 | a `tools/list` result at `2026-07-28` | no `ttlMs`, no `cacheScope` — the required fields absent |
| 3 | wiring the Plug with no authorization option | **must fail at start**, and does not until the option exists |

Each recorded verbatim by redirect before the corresponding code is written.

## 4. Resilience checks — named before the Plug is written, not after

Reported as a table of command and observed result:

| check | question |
|---|---|
| supervision | what supervises the Bandit listener |
| handler crash | a request handler raises — does the listener survive, does the **next** request succeed |
| concurrency | two requests in flight — do they interfere through any shared state |
| malformed input | bad JSON, wrong content-type, empty body, oversized body — **a response, not a stacktrace** |
| resource bounds | is there a body-size limit; what happens without one |
| dispatch crash | a crash in the **host's** dispatch function — what reaches the transport, what reaches the client |

The last is the one that matters most for a package whose whole design is host-injected
behaviour: the host's code runs inside our request path.

## 5. Out of scope, filed not fixed

SCR-263 (sweep population), SCR-265 (signoff binding), SCR-271 (`Transport.Stdio` moduledoc),
SCR-249 (`mix docs` in the gate), SCR-262 (gate REUSE population), 003 (provenance identity).

## 6. Review

**Two lanes, two rounds, scoped to the shipped artefact** — `lib/`, `test/`, `README.md`,
`CHANGELOG.md`, `mix.exs`. Findings about slice records or evidence prose are **filed, not
blocking**. Plus a **third security lane** on the HTTP surface, briefed from §1's answer, which
is on the artefact and in scope.

The bound is deliberate: the last three slices each ran seven or eight rounds with the code
settled by round two, and almost every finding after that was in records rather than in what
ships.

## 7. Acceptance criteria

1. All three reds demonstrated and archived before their fixes.
2. A `tools/list` over HTTP at `2026-07-28` carries `ttlMs` and `cacheScope`.
3. A POST with no `MCP-Protocol-Version` header, or one disagreeing with the body, is rejected —
   `400` with the spec's error, not a stacktrace.
4. An invalid `Origin` gets `403`.
5. Wiring the Plug without the authorization option fails at **start**.
6. `handle_message/2` changes in exactly one clause — `tools/list`, for scope item 2 — and
   nowhere else. **This criterion was written wrong and is corrected here rather than quietly
   failed.** §2 says "`handle_message/2` **does not change**", which is true of scope item 1:
   HTTP is a second caller of the existing core and adds no clause to it. Criterion 6 then
   restated that absolutely, which scope item 2 makes impossible — SCR-261 requires fields on
   the `tools/list` result, and that result is built inside `handle_message/2`. The two
   statements were written at different moments about different scope items and only one of
   them can be an acceptance criterion. Verified by `git diff bee3d26 -- lib/beam_mcp/server.ex`:
   the only changes are `new/1`'s two host-supplied options, the typespec entries for them, and
   the `tools/list` clause.
7. Every resilience check in §4 has a command and an observed result.
8. `./tools/gate.sh` exits 0 with every step line reading `pass`.
