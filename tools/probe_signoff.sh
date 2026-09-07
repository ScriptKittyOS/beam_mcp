#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probes for tools/signoff.sh.
#
# THE POPULATION IS DERIVED THE WAY signoff.sh DERIVES IT (CONVENTIONS.md, instance #1 of which
# is this repository's own REUSE check):
#
#   - Records are created by CALLING `signoff.sh record`. None is hand-written, so a probe
#     cannot pass by planting a record shape the tool would never produce.
#   - The tree is moved by a REAL COMMIT. No probe edits a hash to manufacture a mismatch,
#     because a hand-edited hash proves the string comparison works and nothing about whether
#     the tool is watching the right tree.
#
# Everything runs inside a throwaway git repository this script builds with `git init`, so the
# repository it lives in is never touched. The tool under test is the REAL tools/signoff.sh,
# invoked by absolute path -- not a copy, which could drift from the file that ships.
#
#     ./tools/probe_signoff.sh > slices/004-gate-honesty/logs/probe-signoff.txt 2>&1
set -uo pipefail

SIGNOFF="$(cd "$(dirname "$0")" && pwd)/signoff.sh"
[ -x "$SIGNOFF" ] || { echo "no executable $SIGNOFF"; exit 2; }
SLICE="slices/test-slice"
PASSES=0; FAILS=0

newrepo() { # newrepo -> prints the path of a fresh repo with one commit
  local d; d=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-signoff.XXXXXXXX")
  (
    cd "$d" || exit 1
    git init -q -b main .
    git config user.email probe@example.invalid
    git config user.name  Probe
    git config commit.gpgsign false
    mkdir -p "$SLICE/logs"
    echo "the reviewed content, v1" > source.txt
    echo "a log" > "$SLICE/logs/note.txt"
    git add -A && git commit -q -m "initial"
  ) || return 1
  printf '%s' "$d"
}

check() { # check <id> <expected: 0|nonzero> <actual-rc> <what>
  local id="$1" want="$2" rc="$3" what="$4"
  local ok
  if [ "$want" = "0" ]; then [ "$rc" -eq 0 ] && ok=1 || ok=0
  else [ "$rc" -ne 0 ] && ok=1 || ok=0; fi
  if [ "$ok" -eq 1 ]; then PASSES=$((PASSES+1)); printf '  %-4s AS EXPECTED  (want %s, got exit %s)  %s\n' "$id" "$want" "$rc" "$what"
  else FAILS=$((FAILS+1));  printf '  %-4s DISAGREES    (want %s, got exit %s)  %s\n' "$id" "$want" "$rc" "$what"; fi
}

echo "=== tools/signoff.sh probes ==="
echo "  tool under test: $SIGNOFF"
echo

# ---------------------------------------------------------------------------
# S1 and S3 are written as FUNCTIONS taking the tool path, because they are run twice: once
# against tools/signoff.sh and once against the mutant. A mutation comparison in which the two
# runs are separately written code is comparing two things at once.
#
# S3 writes its signoff-only file DIRECTLY rather than by calling `verify`. The first draft had
# it commit the verify.txt that S1's verify produces, and under the mutant that verify already
# failed, so there was nothing to commit and S3 never ran -- the mutant killed the setup, not
# the probe, and the run scored it as a survivor. CONVENTIONS.md calls that shape the compiler
# kill: "the build failed; no test did anything. Complete the mutation and re-run, or the table
# records a kill that never happened." Here it recorded a SURVIVAL that never happened, which is
# the same error pointing the other way.
scenario_s1() { # scenario_s1 <tool> ; prints verify's exit code, all output on stderr
  local tool="$1" d rc
  d=$(newrepo) || return 2
  (
    cd "$d" || exit 1
    "$tool" record "$SLICE" 1 r1 approve "lane one"
    "$tool" record "$SLICE" 1 r2 approve "lane two"
    git add -A && git commit -q -m "round 1 signoff records"
    echo "    the two records name the same tree:"
    grep -h '^tree: ' "$SLICE"/signoff/*.signoff | sort -u | sed 's/^/      /'
    "$tool" verify "$SLICE"
  ) >&2; rc=$?
  rm -rf "$d"
  printf '%s' "$rc"
}

scenario_s3() { # scenario_s3 <tool> ; prints verify's exit code, all output on stderr
  local tool="$1" d rc
  d=$(newrepo) || return 2
  (
    cd "$d" || exit 1
    "$tool" record "$SLICE" 1 r1 approve >/dev/null
    "$tool" record "$SLICE" 1 r2 approve >/dev/null
    git add -A && git commit -q -m "round 1 signoff records"
    echo "written by hand so this scenario does not depend on verify succeeding" \
      > "$SLICE/signoff/verify.txt"
    git add -A && git commit -q -m "a commit touching nothing but signoff/"
    echo "    that commit changed only:"
    git show --stat --name-only --format= HEAD | sed 's/^/      /'
    "$tool" verify "$SLICE"
  ) >&2; rc=$?
  rm -rf "$d"
  printf '%s' "$rc"
}

echo "--- S1: two approve records at tree T, both committed. verify must exit 0 ---"
rc=$(scenario_s1 "$SIGNOFF"); check S1 0 "$rc" "committing the records must not invalidate them"
echo

# ---------------------------------------------------------------------------
echo "--- S2: S1, then a real commit changing a tracked file. verify must refuse, both STALE ---"
D=$(newrepo); (
  cd "$D" || exit 1
  "$SIGNOFF" record "$SLICE" 1 r1 approve >/dev/null
  "$SIGNOFF" record "$SLICE" 1 r2 approve >/dev/null
  git add -A && git commit -q -m "round 1 signoff records"
  echo "the reviewed content, v2" > source.txt
  git commit -qam "the tree moves under the approved review"
  "$SIGNOFF" verify "$SLICE" 2>&1 | sed 's/^/    /'
  exit "${PIPESTATUS[0]}"
); check S2 nonzero $? "this is slice 001b's failure, mechanised"
rm -rf "$D"; echo

# ---------------------------------------------------------------------------
echo "--- S3: S1, then a commit changing ONLY slices/*/signoff/. verify must still exit 0 ---"
echo "     The exclusion is load-bearing and this proves it rather than asserting it."
rc=$(scenario_s3 "$SIGNOFF"); check S3 0 "$rc" "a commit inside the excluded directory must not move the reviewed tree"
echo

# ---------------------------------------------------------------------------
echo "--- S4: no records at all. verify must refuse ---"
echo "     If this passes, the tool is the defect it was written against."
D=$(newrepo); (
  cd "$D" || exit 1
  mkdir -p "$SLICE/signoff"
  "$SIGNOFF" verify "$SLICE" 2>&1 | sed 's/^/    /'
  exit "${PIPESTATUS[0]}"
); check S4 nonzero $? "nothing to check is not a pass"
rm -rf "$D"; echo

# ---------------------------------------------------------------------------
echo "--- S5: one approve, one changes-required. verify must refuse ---"
D=$(newrepo); (
  cd "$D" || exit 1
  "$SIGNOFF" record "$SLICE" 1 r1 approve >/dev/null
  "$SIGNOFF" record "$SLICE" 1 r2 changes-required "the finding" >/dev/null
  git add -A && git commit -q -m "round 1 signoff records"
  "$SIGNOFF" verify "$SLICE" 2>&1 | sed 's/^/    /'
  exit "${PIPESTATUS[0]}"
); check S5 nonzero $? "one lane objecting is the round objecting"
rm -rf "$D"; echo

# ---------------------------------------------------------------------------
echo "--- S6: a stray notes.txt under slices/*/signoff/. verify must refuse ---"
echo "     Excluded from the reviewed tree must not become a place to put things."
D=$(newrepo); (
  cd "$D" || exit 1
  "$SIGNOFF" record "$SLICE" 1 r1 approve >/dev/null
  "$SIGNOFF" record "$SLICE" 1 r2 approve >/dev/null
  echo "anything at all" > "$SLICE/signoff/notes.txt"
  git add -A && git commit -q -m "records plus a stray file"
  "$SIGNOFF" verify "$SLICE" 2>&1 | sed 's/^/    /'
  exit "${PIPESTATUS[0]}"
); check S6 nonzero $? "the exclusion is policed, not just documented"
rm -rf "$D"; echo

# ---------------------------------------------------------------------------
echo "--- S7: a record with its 'tree:' line deleted. verify must REFUSE, not skip ---"
D=$(newrepo); (
  cd "$D" || exit 1
  "$SIGNOFF" record "$SLICE" 1 r1 approve >/dev/null
  "$SIGNOFF" record "$SLICE" 1 r2 approve >/dev/null
  grep -v '^tree: ' "$SLICE/signoff/round1.r2.signoff" > "$SLICE/signoff/round1.r2.tmp"
  mv "$SLICE/signoff/round1.r2.tmp" "$SLICE/signoff/round1.r2.signoff"
  git add -A && git commit -q -m "one record loses its tree line"
  "$SIGNOFF" verify "$SLICE" 2>&1 | sed 's/^/    /'
  exit "${PIPESTATUS[0]}"
); check S7 nonzero $? "a skipped record is a member the population lost quietly"
rm -rf "$D"; echo

# ---------------------------------------------------------------------------
echo "--- S8: a SYMLINK under slices/*/signoff/. verify must refuse ---"
echo "     S6 plants a regular file. This plants a link, which is what the first draft's"
echo "     \`find -type f\` did not match: seen by neither the file loop nor the subdirectory"
echo "     check, so verify exited 0 over it. The link points at a file ALREADY tracked, so"
echo "     the reviewed tree does not move and STALE cannot be what refuses -- the whitelist"
echo "     has to be what refuses, or nothing does."
D=$(newrepo); (
  cd "$D" || exit 1
  "$SIGNOFF" record "$SLICE" 1 r1 approve >/dev/null
  "$SIGNOFF" record "$SLICE" 1 r2 approve >/dev/null
  ln -s ../../../source.txt "$SLICE/signoff/anything.sh"
  git add -A && git commit -q -m "records plus a symlink"
  echo "    under the excluded directory HEAD now carries:"
  git ls-tree -r HEAD -- "$SLICE/signoff" | sed 's/^/      /'
  "$SIGNOFF" verify "$SLICE" 2>&1 | sed 's/^/    /'
  exit "${PIPESTATUS[0]}"
); check S8 nonzero $? "an exclusion a link walks through is not an exclusion"
rm -rf "$D"; echo

# S9 is a function for the same reason S1 and S3 are: it is run twice, once against the real
# tool and once against a mutant, and the two runs must differ in exactly one thing.
scenario_s9() { # scenario_s9 <tool> ; prints verify's exit code, all output on stderr
  local tool="$1" d rc
  d=$(newrepo) || return 2
  (
    cd "$d" || exit 1
    # Round 1 finds something. One lane objects; the other approved the tree that is about to
    # be replaced. Both are exactly what a real first round leaves behind.
    "$tool" record "$SLICE" 1 r1 changes-required "a finding" >/dev/null
    "$tool" record "$SLICE" 1 r2 approve "no objection at this tree" >/dev/null
    git add -A && git commit -q -m "round 1 records"
    echo "the reviewed content, v2 -- round 1's finding, fixed" > source.txt
    git commit -qam "fix the round 1 finding"
    # Round 2 reviews the fixed tree and approves it.
    "$tool" record "$SLICE" 2 r1 approve >/dev/null
    "$tool" record "$SLICE" 2 r2 approve >/dev/null
    git add -A && git commit -q -m "round 2 records"
    echo "    records present:"
    ls "$SLICE"/signoff/*.signoff | sed 's/^/      /'
    "$tool" verify "$SLICE"
  ) >&2; rc=$?
  rm -rf "$d"
  printf '%s' "$rc"
}

echo "--- S9: round 1 objects and goes stale, round 2 approves the fixed tree. verify must exit 0 ---"
echo "     PLAN.md 4's table refuses on ANY changes-required and ANY stale record, over every"
echo "     record. Applied to a slice that actually runs rounds, that is a check which cannot"
echo "     pass: needing a change is what rounds are for, and fixing the finding is what makes"
echo "     round 1's approve stale. A check that can only fail is the mirror of one that can"
echo "     only pass, and its one stable outcome is to be switched off."
rc=$(scenario_s9 "$SIGNOFF"); check S9 0 "$rc" "the highest round decides; earlier rounds are history"
echo

# EVERY MUTATION IS ASSERTED TO HAVE APPLIED. This is not defensive tidiness: round 2 moved the
# exclusion from `git ls-tree | grep -z` to a shell glob, the mutant's sed no longer matched
# anything, and the probe cheerfully ran the UNMUTATED script and scored S1 and S3 as SURVIVORS.
# CONVENTIONS.md names that shape -- "a mutation reported as applied but never applied" -- and a
# survivor is the expensive direction to be wrong in, because it reads as a real finding.
mutate() { # mutate <name> <sed-expression> ; prints the mutant's path, or exits
  local name="$1" expr="$2" dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-signoff-$name.XXXXXXXX") || exit 2
  sed "$expr" "$SIGNOFF" > "$dir/signoff.sh"
  if cmp -s "$SIGNOFF" "$dir/signoff.sh"; then
    echo "  MUTATION $name DID NOT APPLY -- the sed matched nothing. Refusing to score it." >&2
    FAILS=$((FAILS+1)); rm -rf "$dir"; return 1
  fi
  chmod +x "$dir/signoff.sh"
  echo "  the one line changed:" >&2
  diff "$SIGNOFF" "$dir/signoff.sh" | sed 's/^/    /' >&2
  printf '%s' "$dir"
}

echo "=== MUTATION: remove the slices/*/signoff/ exclusion from review_tree() ==="
echo "  An exclusion whose removal changes nothing was never load-bearing. S1 and S3 must break."
MUT=$(mutate mut1 's|^  for d in slices/\*/signoff; do$|  for d in /nonexistent-mutant-path; do   # MUTANT: exclude nothing|') || MUT=""
MUT_FAILS=0
for id in S1 S3; do
  [ -n "$MUT" ] || { MUT_FAILS=$((MUT_FAILS+1)); echo "  $id: not scored, mutation did not apply"; continue; }
  rc=$("scenario_${id,,}" "$MUT/signoff.sh" 2>/dev/null)
  if [ "$rc" -ne 0 ] 2>/dev/null && [ -n "$rc" ]; then
    echo "  $id under the mutant: verify exit $rc -- BROKEN, as required"
  else
    echo "  $id under the mutant: verify exit '$rc' -- SURVIVED. The exclusion is not load-bearing."
    MUT_FAILS=$((MUT_FAILS+1))
  fi
done
rm -rf "$MUT"
echo

echo "=== MUTATION 2: make every round decide, not just the highest ==="
echo "  This is PLAN.md 4's table as literally written. S9 must break under it, or the"
echo "  departure from the plan bought nothing and should be reverted."
MUT2=$(mutate mut2 's|^  if \[ "\$r_round" != "\$top" \]; then$|  if false; then   # MUTANT: no round is ever superseded|') || MUT2=""
if [ -z "$MUT2" ]; then
  MUT_FAILS=$((MUT_FAILS+1)); echo "  S9: not scored, mutation did not apply"; rc=0
else
rc=$(scenario_s9 "$MUT2/signoff.sh" 2>/dev/null)
if [ "$rc" -ne 0 ] 2>/dev/null && [ -n "$rc" ]; then
  echo "  S9 under mutant 2: verify exit $rc -- BROKEN, as required"
else
  echo "  S9 under mutant 2: verify exit '$rc' -- SURVIVED. The round logic is not load-bearing."
  MUT_FAILS=$((MUT_FAILS+1))
fi
fi
rm -rf "$MUT2"
echo

echo "=== totals ==="
echo "  probes as expected: $PASSES"
echo "  probes disagreeing: $FAILS"
echo "  mutants surviving:  $MUT_FAILS"
[ "$FAILS" -eq 0 ] && [ "$MUT_FAILS" -eq 0 ] || exit 1
exit 0
