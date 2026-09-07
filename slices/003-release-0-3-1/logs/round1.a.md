# Round 1, lane a — correctness and anchors

Tree read: `1d27f1a0cd3265f45cd7ef0ca64ea10f584f6e2a` (commit `b821818`). Pin: `round1.a.tree`.
Scope: `lib/beam_mcp/transport/http.ex` and `test/beam_mcp/transport/`, read as a pair.
Method: every anchor scored by mutation. No test was read and agreed with.

**Verdict: changes required (one), and they are made. Two survivors recorded as survivors.**

## Blocking

**A1. A comment claimed more than had been measured.** `tool_annotations/2`'s comment said
`check_annotations/2` moved inside `host_call/1` "because ... a schema whose `properties` keys
are not strings raises in `Enum.join/2` there". Scored:

    Mc2   check_annotations/2 left OUTSIDE host_call/1, spec read and walk inside
          SURVIVES   156 tests, 0 failures     logs/mutation-c-Mc2.txt

The mutant survives, and reading why shows the sentence is wrong as written:
`annotation_detail/1` -- the only place a property path is interpolated -- runs **only** on a
type offence or a name collision, so a non-`String.Chars` key alone raises nothing. Reaching the
raise needs such a key AND an offence, which no JSON-derived schema can produce.

This is the class `CONVENTIONS.md` records under *"an archive reported as verbatim but never
fetched"*: a justification written to sound measured that nobody measured. It is the same defect
whether it appears in a record or in a code comment, and it appeared here in code written by
this slice.

**Fixed** by rewriting the comment to say what the measurement says: that half of the move is
defensive rather than defect-driven, the mutant survives, and why. The move itself is kept --
it is right on principle and costs nothing -- but it is no longer described as closing a defect.

## Anchors scored

Each mutant's diff against the pristine file is in its own log, so every one is shown applied
rather than reported applied.

| mutant | what it does | result | log |
|---|---|---|---|
| `M13rev` | the (c) fix removed: spec read and walk back outside `host_call/1` | **KILLED** 147/1 | `mutation-c-M13rev.txt` |
| `M2always` | `fault_response/4` always re-raises (bodyless 500) | **KILLED** 147/1 | `mutation-c-M2always.txt` |
| `M2never` | `fault_response/4` never re-raises | SURVIVES 147/0 | `mutation-c-M2never.txt` |
| `Mc2` | `check_annotations/2` left outside `host_call/1` | SURVIVES 156/0 | `mutation-c-Mc2.txt` |
| `Mc3` | `mirrored_params/2` stops recognising the host-fault sentinel | **KILLED** 156/2 | `mutation-c-Mc3.txt` |
| `Md1` | the (d) fix removed: no pre-read refusal closes | **KILLED** 156/8 | `mutation-d-Md1.txt` |
| `Md2` | closes ALWAYS, every refusal rather than the pre-read set | **KILLED** 156/1 | `mutation-d-Md2.txt` |

Counts are `tests/failures` as the run printed them; the differing totals are the tree growing
across the two commits (147 after (c), 156 after (d)), not a re-labelled run.

`M13rev` and `Md1` had to remove what they orphaned -- `tool_annotations/2` and `close_after/1`
respectively -- or `--warnings-as-errors` would have failed the build before the suite ran and
the table would have recorded a kill no test made. Both mutation scripts assert the orphan is
gone before writing.

`Md2` is the one that matters most for (d): it is killed by the post-read control alone. Without
that control the fix cannot be told from a server that closes on everything, which is a
different bug wearing the fix's clothes.

## Read and accepted

- **`ToolCatalog.fetch/2` not returning `{:ok, spec}` still yields `[]`.** `tool_annotations/2`'s
  `with` has no `else`, so a `{:error, _}` falls out of it, out of `host_call/1`, and into
  `mirrored_params/2`'s `_ -> []`. A tool the catalog does not have mirrors no parameters, which
  is not a fault. Behaviour unchanged from before the move.
- **The invalid-annotation sentinel still reaches its own branch.** It is returned by
  `check_annotations/2`, passes through `host_call/1` untouched, fails to match
  `{:ok, entries}`, and is matched by tag in the `else`. `Mc3` proves the sibling host-fault
  clause is load-bearing; the (a) and (b) tests from earlier in the slice cover this one.
- **`before_body/2`'s `ok -> ok` catch-all.** An unexpected return from a step passes through to
  `handle/2`'s `with`, matches neither the `do` pattern nor the `else` clause, and raises
  `WithClauseError` into `call/2`'s rescue -- a 500 inside the envelope. Identical to the
  behaviour before the split.
- **The 405 keeps its `allow: POST` header through the close.** `check_method/1` builds the
  refusal on a conn that already carries it and `close_after/1` adds to that conn. Asserted.

## Filed, not blocking

**A2. `read_body_bounded/1`'s `{:error, reason}` 400 has no test at all**, and now carries the
new close behaviour untested with it. Derived: `grep -rn "Could not read request body" test/ lib/`
returns one hit and it is the source line. Pre-existing; `Plug.Test`'s `read_body/2` is a
`:binary.part` and cannot return `{:error, _}`, and Bandit raises rather than returning it for
the malformed framings tried here. Recorded so the next reader does not have to rediscover that
the branch is dark.

**A3. A bodyless non-POST now costs a connection.** A `GET /mcp` -- the shape a monitor or a
probe sends -- leaves nothing unread, so closing on it buys nothing and costs a handshake. The
alternative is deciding per request whether the body was consumed, which reintroduces exactly the
per-site reasoning that left five of six sites unfixed. The trade is deliberate: uniformity at
the split, at the cost of one connection per rejected non-POST.
