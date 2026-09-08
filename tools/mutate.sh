#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The mutation harness. Applies one mutant to the shipping file, PROVES IT APPLIED, runs the
# suite, and restores the file -- whatever happens.
#
#     tools/mutate.sh score  [<name>...]     one line per mutant: PASSES passes, each scored
#     tools/mutate.sh run    <name>          one mutant, with its diff and the whole suite output
#     tools/mutate.sh list                   the mutants available
#     tools/mutate.sh check                  every mutant applies and restores, no suite run
#
# Environment: PASSES (default 2, for `score`), TARGET (default lib/beam_mcp/transport/http.ex).
#
# WHY THIS FILE EXISTS AND IS TRACKED. Slice 003's record cites its scoring instrument as
# `$S/mut.sh <name>` where `$S` is a scratchpad directory on one machine. Nobody reading that
# record can re-run it, which makes the table a claim rather than a measurement -- the same rule
# CONVENTIONS.md states for archives ("written by a command that fetches it, or it does not
# exist") applied to the instrument instead of the artefact. The scratchpad copy also hard-coded
# a worktree path in every mutant script. Both are removed: the repository root comes from git,
# and each mutant is handed the file to mutate as its argument.
#
# THE PRISTINE COPY IS TAKEN FROM THE TREE IN FRONT OF YOU, NOT FROM A SNAPSHOT. The scratchpad
# version diffed against a `http.ex.pristine` file that had been copied by hand some time
# earlier, and carried a second copy named `.prerebase` because the first had gone stale. A
# stale pristine makes the printed diff describe a tree nobody is running. Here the pristine is
# made at the start of every invocation from the working file, and restored from it by an EXIT
# trap, so an interrupted run cannot leave a mutated file behind.
#
# WHAT IT REFUSES. A mutant whose anchor no longer matches, or one that leaves the file byte
# identical, is reported as NOT-APPLIED and scored as nothing. CONVENTIONS.md: "a mutation
# reported as applied but never applied" is the family of defect this guards. The suite is never
# run over an unmutated file and called a score.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TARGET="${TARGET:-lib/beam_mcp/transport/http.ex}"
PASSES="${PASSES:-2}"
MUTANTS_DIR="tools/mutants"

[ -f "$TARGET" ] || { echo "no such target file: $TARGET" >&2; exit 1; }

all_mutants() {
  local f
  for f in "$MUTANTS_DIR"/*.py; do
    [ -e "$f" ] || continue
    f="${f##*/}"
    printf '%s\n' "${f%.py}"
  done
}

pristine=""
restore() { [ -n "$pristine" ] && [ -f "$pristine" ] && cp "$pristine" "$TARGET"; rm -f "$pristine"; }
trap restore EXIT INT TERM

start() {
  pristine=$(mktemp "${TMPDIR:-/tmp}/beam_mcp-mutate.XXXXXXXX") || exit 1
  cp "$TARGET" "$pristine" || exit 1
}

# apply <name> -- 0 applied, 1 script failed, 2 file unchanged
apply() {
  local name="$1"
  cp "$pristine" "$TARGET" || return 1
  python3 "$MUTANTS_DIR/$name.py" "$TARGET" >/dev/null 2>&1 || return 1
  cmp -s "$pristine" "$TARGET" && return 2
  return 0
}

# The count line the suite prints, quoted rather than retyped, and the NAME of every test that
# failed. The scratchpad version kept only the count, and a count is where a harness flake hides:
# "160 tests, 1 failure" reads the same whether the failure is the mutant's or the instrument's.
# Slice 006 needed the names to tell those apart, so the instrument now keeps them.
suite() {
  local out rc
  out=$(mix test 2>&1); rc=$?
  printf '%s\n' "$out" | grep -E '^[0-9]+ tests?, ' | tail -1
  printf '%s\n' "$out" | grep -E '^ +[0-9]+\) test ' | sed 's/^ *[0-9]*) test /        failed: /'
  return $rc
}

cmd="${1:-}"; shift || true
case "$cmd" in
  list)
    all_mutants
    ;;

  check)
    start
    for name in $(all_mutants); do
      apply "$name"
      case $? in
        0) echo "$name  applied ($(diff -u "$pristine" "$TARGET" | grep -c '^[-+][^-+]') changed line(s))" ;;
        1) echo "$name  SCRIPT-FAILED"; python3 "$MUTANTS_DIR/$name.py" "$TARGET" ;;
        2) echo "$name  NOT-APPLIED (file unchanged)" ;;
      esac
    done
    cp "$pristine" "$TARGET"
    cmp -s "$pristine" "$TARGET" && echo "restored: $TARGET is the file you started with"
    ;;

  run)
    name="${1:-}"
    [ -n "$name" ] || { echo "usage: tools/mutate.sh run <name>" >&2; exit 1; }
    [ -f "$MUTANTS_DIR/$name.py" ] || { echo "no such mutant: $name" >&2; exit 1; }
    start
    apply "$name"
    case $? in
      1) echo "$name: MUTATION SCRIPT FAILED"; python3 "$MUTANTS_DIR/$name.py" "$TARGET"; exit 9 ;;
      2) echo "$name: NOT APPLIED -- $TARGET is unchanged. Nothing was scored."; exit 9 ;;
    esac
    echo "=== $name: diff against the pristine $TARGET, proving the mutation applied ==="
    diff -u "$pristine" "$TARGET"
    echo "(diff exit $? -- 1 means the files differ, i.e. the mutation is on disk)"
    echo "=== $name: suite ==="
    mix test; echo "TEST_EXIT=$?"
    ;;

  score)
    wanted="$*"
    [ -n "$wanted" ] || wanted=$(all_mutants)
    start
    echo "target:  $TARGET"
    echo "passes:  $PASSES"
    echo "tree:    $(git rev-parse HEAD)  dirty=$(git status --porcelain | wc -l)"
    for name in $wanted; do
      [ -f "$MUTANTS_DIR/$name.py" ] || { echo "$name  NO-SUCH-MUTANT"; continue; }
      line="$name"
      failed=""
      for _ in $(seq 1 "$PASSES"); do
        apply "$name"
        case $? in
          1) line="$line | SCRIPT-FAILED"; continue ;;
          2) line="$line | NOT-APPLIED"; continue ;;
        esac
        out=$(suite); rc=$?
        res=$(printf '%s\n' "$out" | head -1)
        failed="${failed}$(printf '%s\n' "$out" | tail -n +2)"$'\n'
        line="$line | $res TEST_EXIT=$rc"
      done
      echo "$line"
      printf '%s' "$failed" | sort -u | grep -v '^$'
    done
    cp "$pristine" "$TARGET"
    ;;

  *)
    sed -n '5,20p' "$0"
    exit 1
    ;;
esac
