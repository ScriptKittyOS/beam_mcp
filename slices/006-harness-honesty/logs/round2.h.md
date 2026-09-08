<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 2, lane h — the record and the instrument

**INDEPENDENCE, STATED FIRST.** Two written passes by **one reader**, not two readers. Round 1's
lanes were separate agents; these are not. "Two lanes" here is not a claim of independence.

Tree read: `2f03bec5521bc0b45853b69667b54b2953c27eb9` (commit `716526e8aa8184a6c98abf13de931281ee1bea11`).

## The finding of this round, and it is about an archive rather than the code

**The provenance notes destroyed the evidence they cite.** Each of the four `*-round2` archives
carries a hand-added note arguing it is the clean re-run because the four births form "an unbroken
serial chain". Measured:

    birth 13:36:56  mtime 13:36:56    all four, identical to the millisecond

Birth equal to mtime, and all four equal to each other, is the signature of a wholesale rewrite.
**Prepending each note rewrote its file and reset the very timestamp the note offers as proof.**
The archive cited as evidence was consumed by the act of citing it.

This is the slice's own subject one level up, and it is the third time in this repository the
failure has moved outward from the code: defect, then test, then record, then — here — the
*mechanism by which a record is corrected*.

**It is corrected by appending, not by deletion**, in all four files and in FINDINGS. What
survives is the driver's own `date:` lines, which establish one serial run and cannot rule out
interference in its opening minutes; there is no later quiet-machine scoring table to cite, since
`mutation-harness-anchors-round2.txt` is *earlier* at 12:06:42Z. Recorded as unresolved.

## What else I checked

**B1 is not repeated in the Round 2 tables.** Every count there is paired to its label by

    awk '/^H[0-9] applied/{lab=$1} /^164 tests/{if(lab!=""){print lab" -> "$0; lab=""}}'

rather than read off adjacent lines, which is how the round-1 table came to print a suite total
beside a single-file archive. Round 1's table is left standing with its defect, as the finding.

**The CI correction is appended, not substituted.** Round 1's "the CI transcript did not print the
argument" is false — `ci-evidence.txt` carries `# 1` and `""` in both red runs — and the
sentence is corrected beneath itself rather than edited away.

**The repeat is now visible in a scored archive.** `exchanges repeated:` appears 3 times in
`green-mutation-under-load-round2.txt`, so a defect the harness absorbs can no longer be silent
in a table — the gap that let a 30-run check count retries as successes.

**`mutate.sh` refuses a dirty target**, proven red-then-green in `probe-mutate-dirty-target.txt`,
which closes the path where a SIGKILL-orphaned mutant becomes the next run's pristine.

## Verdict

**approve**, with the provenance uncertainty recorded rather than closed. The record now states
what it cannot show, which is the property this slice exists to produce.

Bounded by the independence limit at the head of this file.
