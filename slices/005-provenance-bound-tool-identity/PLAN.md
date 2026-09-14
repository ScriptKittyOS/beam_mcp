<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 005 — provenance-bound tool identity: a tool is (origin, name)

**Issue:** SCR-254. **Written before any code**, per the practice this repository carries.

**The number is 005, not 003.** SCR-254 was titled *"003 — provenance-bound tool identity"* until
the numbering rule of 2026-09-07, which says slice directories own one number sequence assigned
**when a slice starts**. `slices/003-release-0-3-1/` is slice 003 and has shipped. This slice
starts now, and 005 is the next free number. The issue keeps its name and its rank; it never had
a number to keep.

---

## 0. The prior art, read before the design rather than after

`SEP-2640, Skills Extension` is the strongest prior art for this slice's central idea, and it is
**archived in full** at `logs/spec-sep-2640-skills.md`, fetched by the command that wrote the
file. Re-measured at the time of writing:

    state=open  merged=False  mergeable_state=clean  Status: Accepted  Sponsor: @pja-ant

Its `mergeable_state` moved from `blocked` to `clean` while the survey that found it was still
running. **This slice treats 2640 as landing**, not as a speculative draft.

### What 2640 already says, quoted rather than paraphrased

> The identity of an MCP-served skill is therefore the pair of the host's identity for the
> originating server and the skill's `uri`. Hosts MUST preserve both halves wherever a skill is
> recorded or addressed — the registry, persisted approvals, the cache, and any tool or path
> through which the model reaches the skill — and MUST NOT key any of these on the `uri` alone.

and, from its Security Implications:

> Hosts MUST resolve skill names within a per-origin namespace, identifying servers by a
> **host-assigned label, not the server's self-reported `serverInfo.name`**; MUST NOT let an
> MCP-served skill silently shadow, replace, or intercept invocations of a same-named skill from
> any other origin

That is compound identity, stated normatively, with an explicit prohibition on collapsing it to
one key. **This slice does not get to claim the idea.**

### What this slice does that 2640 does not — the three differences, and they are the whole slice

**1. Tools, not skills.** 2640 governs skills: resources under `skill://`, delivered over the
Resources primitive. It never touches `Tool`, `tools/list` or `tools/call`. Its own Backward
Compatibility section confines it — *"A server that does not implement this extension simply
exposes no `skill://` resources"*. Nothing in it changes what a tool is.

**2. On the wire, not a host-assigned label.** 2640's origin half is *"the host's identity for the
originating server"*, and it says twice that this must be a host-assigned label rather than the
server's self-reported `serverInfo.name`. **That value never appears in any MCP message.** 2640 is
a specification document imposing host-side discipline; two hosts talking to the same two servers
may assign different labels, and neither label is transmitted. This slice puts origin in the
protocol's own data, so the identity is the same on both ends of the connection and does not
depend on a host doing the right thing privately.

**3. It closes a gap the project itself records as open.** `docs/community/interest-groups/
security.mdx:121` carries the row `| — | Tool identity across servers | Open | — |` — no SEP, no
champion, in a charter dated 2026-06-13. 2640 did not close it; 2640 is why the row can still be
open while a compound identity exists for a *different* primitive.

### What happens to the claim if 2640 is later extended to tools

Stated now, before the code, so nobody has to decide it under pressure later.

**The claim narrows and the slice does not change.** The clause carrying it today is *"for tools,
on the wire"* — see the claim of record on SCR-254. If 2640's identity rule is extended to cover
`Tool`:

- **If the extension keeps the origin half as a host-assigned label**, difference (2) survives
  intact and difference (1) is gone. The claim becomes *"on the wire, not a host-assigned label"*
  alone. That is a narrower claim and still true, and it is the one difference that has always
  been load-bearing.
- **If the extension puts origin on the wire for tools**, the claim is **dead** and this slice is
  a conforming implementation rather than a novel one. That is a good outcome for the package and
  a bad one for the sentence, and the correct response is to **adopt the standard's shape** —
  matching an accepted SEP beats keeping a private one — and to record the claim as retired
  rather than quietly restating it.
- Either way the **defect** this slice fixes is unaffected: today a newcomer named after an
  incumbent is indistinguishable from it, and that is true whatever any SEP says.

**A trigger, not a vibe.** Before this slice's PR is opened, re-fetch SEP-2640 and re-run the open
SEP sweep for `Tool`/`tools/call` (the derivation in SCR-254's second correction). If either has
moved, the finding goes in FINDINGS.md and on SCR-254 **before** the claim is repeated anywhere.

---

## 1. The defect, and the red that specifies it

`BeamMCP.ToolCatalog` and `BeamMCP.ToolSpec` key a tool by `name` alone. Two servers offering
`search` are one tool to this package.

**Red first, and the red is the attack rather than a synthetic edge:** register a tool with the
**same name as an incumbent, from a different origin**, and show today's package treats them as
one. Green: the two are distinct, the host can tell which is which, and a test asserts the
newcomer **acquires nothing** — not the incumbent's annotations, not its schema, not its tier.

---

## 2. What the package claims, and what it does not

**It provides identity. It does not assign trust.** Tier and policy stay with the host. The
package makes it possible to tell two same-named tools apart and refuses to conflate them; it does
not decide which one to run. This is the boundary the extraction drew — risk tiers, approvals,
receipts, masking and authority never entered this package — and identity is not a back door for
them.

**2640 independently reaches the same boundary and says it more sharply**, which is worth
borrowing rather than re-deriving: *"A name binds to whatever bytes its origin currently serves —
it carries no authorship or endorsement."* The README sentence for this slice should say that,
because a consumer who reads origin-binding as a trust signal will skip the check that actually
protects them.

---

## 3. Questions the PLAN must answer before any code

1. **What is `origin`?** A host-supplied opaque term, a URI, or a structured value. 2640's warning
   applies with full force: the server's self-reported `serverInfo.name` is **not** an identity
   and must not be used as one.
2. **Does origin travel on the wire, and where?** `_meta` on the tool object, a field on `Tool`, or
   both. Note the constraint the base protocol already imposes: `_meta`
   `io.modelcontextprotocol/serverInfo` is *"self-reported… not verified by the protocol"* and
   clients **SHOULD NOT** use it for security decisions. Anything this slice puts on the wire must
   not be mistakable for that field.
3. **What happens to `tools/call` when two origins offer one name?** Refusal, qualified
   addressing, or host-selected — decided here, with the argument, not discovered in review.
4. **Does the injected-catalog defect recur?** This package's first commit exists because a catalog
   was honoured when advertising and ignored when calling. The same split is available to origin,
   and a test must make it impossible to pass by coincidence.
5. **Backward compatibility.** A single-origin host must not have to change anything. 0.4.0 is a
   minor bump and the README pin documents wire breaks at the minor position.

---

## 4. Acceptance criterion, as a measurement

1. A **red before any fix**, captured whole with its exit code: two origins, one name, treated as
   one tool.
2. The newcomer **acquires nothing** — annotations, schema, and any host-assigned attribute each
   pinned by their own assertion, and each killed by its own mutant.
3. **The population is derived.** Every place this package keys a tool by name is found by a
   recorded command and changed through one path. The test of the fix is that a new keying site
   inherits the behaviour instead of needing a new finding.
4. **`serverInfo.name` is not usable as origin**, pinned by a test, because it is the mistake both
   2640 and the base protocol name explicitly.
5. Gate green, every step line read as a line and not as an exit code.

---

## 5. Process, and one hard dependency

Two lanes, three rounds maximum, closing rule written before round 1 opens. Every round writes both
a verdict and a tree pin for every lane. **`tools/signoff.sh` now exists** (slice 004) and binds a
verdict to the tree it is about; this slice uses it rather than the manual practice that produced
001b's sixteen unbound verdicts.

**Per the supersession rule (PR #14): this brief supersedes the earlier "do not spawn further
subagents" instruction. The lanes may spawn.** If for any reason they cannot, each says so in its
own verdict rather than letting "two lanes" imply independence it does not have.

**BLOCKER — SCR-289 must land first if this slice's record rests on a survivor.** The mutation
harness can add a failure under back-to-back load, which is the direction that turns a **survivor
into a false kill**; `Mc2` already read killed once from that component. This slice's acceptance
criterion 2 is mutation-scored, so if any mutant here is expected to survive, its status is not
recordable until SCR-289 is fixed. Stated now rather than discovered at the round that needs it.

---

## 6. Out of scope, named so it is not folded in

Skills, `skill://`, and any part of SEP-2640's surface. Trust, tiers and approvals. The client
role. Signed provenance (SEP-3140's territory — authenticity, not identity).
