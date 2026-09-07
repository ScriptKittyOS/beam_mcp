<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 001b — the `_meta` era guard: `ping`, and the result shape that goes with it

**Written before any edit to `lib/`.** Sub-slice of 001, per the letter-suffix convention: a
defect found in slice 001's revision-negotiation work after it merged and after `0.1.0`
published. Issue: SCR-257.

**Every specification claim below was fetched on 2026-09-06 from
`https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning` and
`.../changelog`, not recalled.** The `2026-07-28` revision post-dates this agent's training
data, so nothing here is asserted from memory.

**Every page quoted anywhere in this slice is archived, by a command that fetched it** —
`curl -sSL --fail … -o <file>`, so the bytes are the source's bytes:

    logs/spec-basic-versioning.md    2026-07-28 versioning and compatibility
    logs/spec-changelog.md           2026-07-28 key changes
    logs/spec-legacy-basic.md        2025-11-25 base protocol

Added in round 2: r2 was right that "fetched, not recalled" is an unverifiable process assertion
when the quotes it licenses are the load-bearing evidence for the whole decision, and that citing
the URL was permitted but weaker than archiving at no extra cost. The third page was added in
round 3, on r2's finding 5: round 2's correction about `resultType` leaned on `2025-11-25`'s base
page, and the sentence above claimed *both* pages were archived while a third had quietly become
load-bearing.

## Where the probe runs

`/home/aylac/Projects/beam_mcp-wt/001b-ping-guard` — a `git worktree` off `main` at `5d8d1ae`,
with its own `_build` and `deps`. The canonical clone at `/home/aylac/Projects/beam_mcp` is
not written to by any probe in this slice. The probe script itself lives outside the tree, in
the session scratchpad, so it is never a tracked file and never enters the gate's REUSE
population by accident.

## The defect, measured

`mix run` against the worktree at `5d8d1ae`, `mix.exs` version `0.1.1`, each message the first
and only one handed to a fresh `Server.new/1` state:

    ping + _meta 2026-07-28
      -> {"error":{"code":-32601,"message":"Method not found: ping"},"id":1,"jsonrpc":"2.0"}
    ping + _meta 2025-11-25
      -> {"error":{"code":-32601,"message":"Method not found: ping"},"id":1,"jsonrpc":"2.0"}
    ping + _meta, no version key
      -> {"id":1,"jsonrpc":"2.0","result":{}}
    ping bare
      -> {"id":1,"jsonrpc":"2.0","result":{}}

Line 2 is the defect. Line 3 is the **measured boundary**: a `_meta` that carries no
`io.modelcontextprotocol/protocolVersion` does not match the clause head at all and falls
through to the bare handler, so the defect is specific to a `_meta` that names a revision.

`lib/beam_mcp/server.ex:120-135`:

```elixir
def handle_message(
      state,
      %{"jsonrpc" => "2.0", "id" => id, "_meta" => %{@version_meta_key => version}} = message
    ) do
  cond do
    version not in @supported_versions ->
      {state, unsupported_version(id, version)}

    # ping was removed in 2026-07-28. The legacy handler must not inherit it.
    message["method"] == "ping" ->
      {state, error(id, -32_601, "Method not found: ping")}

    true ->
      {next, response} = handle_message(state, Map.drop(message, ["_meta"]))
      {next, modernise(response, state)}
  end
end
```

The guard tests the method and nothing else. The comment names `2026-07-28`; the code names no
revision. Every supported revision reaching this clause takes the refusal branch.

## The second half of the same defect, found while measuring, not in SCR-257

The same clause modernises **every** result it produces, on the same version-blind basis:

    tools/list + _meta 2025-11-25
      -> {"id":2,"jsonrpc":"2.0","result":{"_meta":{"io.modelcontextprotocol/serverInfo":
         {"name":"beam_mcp","version":"0.1.1"}},"resultType":"complete","tools":[...]}}

A request that declared `2025-11-25` is answered with a result carrying `resultType` and
modern `_meta` `serverInfo` — two fields `2026-07-28` introduced and `2025-11-25` does not
define. This is the mirror image of the defect slice 001 was written to close, which was a
modern request answered in a legacy shape. It is the same root cause as the `ping` guard —
one `cond` that branches on the method but never on `version` — so it is in scope here rather
than filed onward. Fixing only `ping` would leave the clause still version-blind.

## What the specification says

From **Versioning and Compatibility**, `2026-07-28`:

> Every request declares the protocol version it is using in its `_meta` field.

> If the server does not implement the requested version (whether the version is unknown to
> the server, or is a known version the server has chosen not to support), it **MUST** respond
> with an `UnsupportedProtocolVersionError` listing the versions it does support

with the page's own example carrying `"supported": ["2026-07-28", "2025-11-25"]`, and:

> The client **SHOULD** select a mutually supported version from the `supported` list and
> retry the request

> A dual-era **server** selects its behavior from how the client opens:
> * A request carrying modern per-request `_meta` is served statelessly according to this
>   revision.
> * An `initialize` request selects legacy semantics [...]

From the **changelog**, `2026-07-28`:

> 5. Remove `ping`, `logging/setLevel`, and `notifications/roots/list_changed`.

> 8. All results now carry a required `resultType` field [...] Clients **MUST** treat results
>    from earlier-protocol servers that omit the field as `"complete"`.

## The decision, and why the other two shapes lose

Three shapes are defensible. They are not equally honest.

**(A) — chosen. The `_meta` clause branches on the declared version.** `2026-07-28` refuses
`ping` and modernises; `2025-11-25` answers `ping` and does **not** modernise; anything else is
`-32022`.

**(B) — rejected. Refuse any `_meta` naming a legacy revision with `-32022`.** The spec permits
a server to not support a known version, so this is coherent *only for a server that does not
advertise it*. This server does advertise it: `server/discover` returns
`["2026-07-28","2025-11-25"]`, `initialize` answers `2025-11-25`, and the `-32022` payload
itself lists `2025-11-25` as supported. The spec's prescribed client behaviour on `-32022` is
to pick from `supported` and **retry the request** — i.e. resend the same `_meta`-shaped
request naming `2025-11-25`. (B) turns that into an infinite loop against our own advertisement.
Making (B) honest would mean dropping `2025-11-25` from the supported set, which is a different
and much larger change and contradicts the `initialize` path this package already serves.

**(C) — rejected. Add `and version == @modern_version` to the `ping` guard, change nothing
else.** This is what SCR-257's title implies and it closes the reported symptom. It leaves the
clause answering a request that declared `2025-11-25` with `resultType` and modern `serverInfo`
— it fixes the method table and keeps the wrong envelope. The brief instructs deciding the
shape against the specification rather than against the issue text, and the specification is
explicit that `resultType` is a `2026-07-28` addition which earlier-revision servers omit.

(A) is the only shape under which the clause's own comment becomes true.

## Note on "served according to this revision"

The spec sentence *"a request carrying modern per-request `_meta` is served statelessly
according to this revision"* describes the era discriminator: `_meta` means stateless, not
session. It is read here as fixing the **statelessness**, not as fixing the revision to
`2026-07-28` regardless of what the `_meta` declares — because the same page's negotiation
section says every request declares its version in `_meta` and requires the server to serve or
refuse **that** version, and because the retry loop above only terminates under that reading.
Recorded explicitly because it is the one sentence that could be read to support (B).

## In scope

1. `lib/beam_mcp/server.ex` — the `_meta` clause branches on `version`.
2. `test/beam_mcp/negotiation_test.exs` — the red, added and demonstrated failing first.
3. `README.md` — the era table, which currently states the intended rule and not the shipped one.
4. `CHANGELOG.md` — a `0.1.2` section.
5. `mix.exs` — version `0.1.1` -> `0.1.2`.
6. This slice directory.

## Out of scope, recorded rather than fixed

- **`ttlMs` and `cacheScope` on `tools/list` results.** `2026-07-28` requires both
  (changelog, minor change 5) and `modernise/2` adds neither. Pre-existing since slice 001,
  unrelated to the version branch, filed rather than fixed.
- **A `_meta` with no version key is served bare** (line 3 of the measurement). That is the
  no-era-established path, which is SCR-255, not this slice.
- Anything about HTTP. That is SCR-253 / slice 002.

## Acceptance criteria

1. A `ping` carrying `_meta` `2025-11-25` returns `result` `%{}` — red before the fix, green
   after, output of both recorded verbatim from the command.
2. A `ping` carrying `_meta` `2026-07-28` still returns `-32601`. The existing test at
   `negotiation_test.exs:145` covers this and must not be edited to pass.
3. A `tools/list` carrying `_meta` `2025-11-25` carries **no** `resultType` and **no**
   `_meta` `serverInfo`; the same request at `2026-07-28` carries both.
4. A `_meta` naming an unsupported revision still returns `-32022` with the supported list.
5. `./tools/gate.sh` exits 0, and every step's own line reads `pass`.
6. Two independent reviewer lanes, read-only, on a checkout of the index, report before merge.

## Version

`0.1.2`. **`0.1.1` is on `main` and was never published to Hex**, so bumping to `0.1.2` means
`0.1.1` will not exist as a release and its documentation fix ships inside `0.1.2`. The
`CHANGELOG` `0.1.1` section is left as written and the fact is appended under `0.1.2` rather
than rewritten. Flagged to the owner: if `0.1.1` is wanted as a release on its own, that is a
publish that has to happen before this slice merges, and it is an owner step either way.

## Review binding

**This repository has no `tools/signoff.sh`.** `tools/` contains `gate.sh` only. There is
therefore **no mechanical binding** between a reviewer's verdict and the bytes committed — no
`Reviewed-diff` trailer, no index-hash check, no hook that refuses an unreviewed commit. The
two lane verdicts are recorded in `slices/001b-ping-guard/` as text, and each lane prints the
tree hash it read into `logs/`, so the binding is *checkable by hand* and is *not enforced*.
Stated plainly rather than implied, because a signoff file that no tool consumes looks like a
control and is not one.
