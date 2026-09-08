<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 007 — `:authorize_body/2`, so body-signature auth is possible at all

**Issue:** SCR-292. Written before the code.

**Number verified free in both places before claiming it**, because SCR-279 records a prior
collision where a directory and an issue disagreed: `slices/` on `main` held `001`, `001b`,
`002`, `003`, `004`, `006`; `005` exists only on PR #15's branch; no `slice/007-*` branch.

## The defect

`authorize/1` cannot see the request body. Not awkwardly — structurally: there is no argument
through which the bytes arrive.

    lib/beam_mcp/transport/http.ex:33-34   the contract, (Plug.Conn.t() -> :ok | {:error, term()})
    lib/beam_mcp/transport/http.ex:277     the single call site
    lib/beam_mcp/transport/http.ex:275-278 authorize is the third `with` clause;
                                           read_body_bounded is the `do` block
    lib/beam_mcp/transport/http.ex:124-126 the init-time arity check it sits beside

So HMAC or asymmetric verification over the payload cannot be written by any host.

## The four options, and why option 1

1. **Leave `authorize/1`; add an optional post-read hook.** ← chosen
2. Change the arity to `(conn, body)` — **breaking**: every `&Auth.check/1` stops satisfying
   `is_function(authorize, 1)` at `:124` and the Plug refuses to start.
3. Keep the arity, pass a conn whose body is read — **breaking invisibly**: unchanged signature,
   moved behaviour, and all seven pre-read refusal sites lose `connection: close`.
4. Accept either arity — forces a host to choose one check when the useful configuration is both.

**Option 1** keeps the property that pays for `authorize/1`'s position: an unauthenticated caller
is refused **before** up to 8 MB is buffered on their behalf. A host that wants both gets both.

## Constraints

- Name exactly `:authorize_body`. Not `:verify_signature` — this package performs no
  cryptography and naming it so would claim a guarantee it does not provide.
- Optional; validated at `init/1` with `is_function(f, 2)`. Wrong arity is a **startup** failure.
- The second argument is the **raw binary** from `read_body_bounded`, before `Jason.decode`.
- Refusal is opaque: the reason reaches the log, never the caller.

## Three decisions this forces, to be answered in FINDINGS

- **(a)** Ordering relative to `check_headers` — it must precede `Jason.decode`.
- **(b)** The refusal status code.
- **(c)** Whether a post-read refusal carries `connection: close`.

## Acceptance criterion, as a measurement

1. The raw-bytes guarantee, **demonstrated red first** by handing the hook
   `Jason.encode!(Jason.decode!(body))` and quoting the failure.
2. `init/1` refuses a wrong-arity function.
3. A passing check allows execution; a failing check refuses **and the tool does not run**.
4. The refusal leaks nothing — not in the body, not in the headers.
5. Two mutants in `tools/mutants/`, scored by `tools/mutate.sh`, both of which must **KILL**:
   one removing the call entirely, one passing a re-encoding. A survivor means the hook is
   deletable without a red suite, and that is reported rather than fixed by adjusting the mutant.

## Out of scope

All cryptography. Any opinion about what a host should verify. `authorize/1` itself.
