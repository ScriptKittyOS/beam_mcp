#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Binds a review verdict to the tree the reviewer actually read.
#
#     tools/signoff.sh record <slice-dir> <round> <lane> <approve|changes-required> [note]
#     tools/signoff.sh verify <slice-dir>
#
# `verify` decides on the HIGHEST round present and keeps earlier rounds as history. See the
# comment above the `top` loop for why, and for the plan text it departs from.
#
# WHAT THIS IS FOR, MEASURED IN THIS REPOSITORY'S OWN SHIPPED SLICES:
#
#     $ git ls-files -- 'slices/001b-ping-guard/logs/round*' | grep -vc '\.tree$'   ->  16
#     $ git ls-files -- 'slices/001b-ping-guard/logs/*.tree'  | wc -l               ->   0
#
#     $ git ls-files -- 'slices/002-streamable-http/logs/round4.*'
#       slices/002-streamable-http/logs/round4.r1.tree     <- a tree nobody gave a verdict on
#       slices/002-streamable-http/logs/round4.r2.tree     <- a tree nobody gave a verdict on
#       slices/002-streamable-http/logs/round4.s1.md
#       slices/002-streamable-http/logs/round4.s1.tree
#
# Sixteen verdicts bound to nothing, and three pins of which two certify nothing. Those two
# shapes are the same defect from both ends, and the fix is that a record is ONE FILE carrying
# BOTH facts: a verdict without a tree does not parse, and a tree without a verdict is not a
# record. There is no pairing step to get wrong because there is no pair.
#
# Those archives are NOT repaired. They are the evidence this tool exists, and rewriting them
# would delete the reason.
#
# WHAT IT DOES NOT DO. It cannot know whether a reviewer read anything. The hash is written by
# the party it certifies. It records WHICH tree a verdict is about, and it REFUSES when that
# tree is no longer the tree in front of you -- which is slice 001b's failure, mechanised: a
# version bump moved the tree after both lanes had approved it and an extra round was needed to
# find that out.
#
# WHAT IT DELIBERATELY DOES NOT CARRY. The reference implementation this was read against
# (a sibling tree's tools/signoff.sh) hard-codes a known-empty-diff hash, pins the number of
# reviewers per round at a count taken from that project's own protocol file, and calls back
# into its gate for a staged-diff recipe. None of that is here. CONVENTIONS.md's first rule --
# "not carrying another tree's tolerances is most of the reason the package exists" -- applies
# to a signoff tool as much as to a linter baseline. The mechanism was taken; the numbers were
# left.
#
# NOT WIRED INTO gate.sh OR CI, and the reason is stated rather than left to be discovered:
# `verify` in the gate would demand signoff records on every push -- including the push that
# introduces this script, and including any concurrent branch that has not been reviewed yet.
# That is a policy decision for the owner, not a side effect of adding a file.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

die() { echo "SIGNOFF REFUSED -- $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# The reviewed tree.
#
# It is HEAD's tree with every slices/<slice>/signoff/ path removed, computed in a SCRATCH
# index with git's own plumbing so anyone with the same commit derives the same value.
#
# The exclusion is what stops the mechanism eating itself: without it, lane r1 recording its
# verdict would change the tree and invalidate its own record before lane r2 recorded one.
# Probe S3 proves the exclusion is load-bearing rather than asserting it, and the mutation on
# this tool removes the exclusion and requires S1 and S3 to break.
#
# The paths are enumerated from HEAD with an anchored expression rather than handed to a git
# pathspec glob, because a git pathspec `*` matches `/` and `slices/*/signoff` would therefore
# also match `slices/a/b/signoff`. This slice is about populations being derived the way the
# mechanism derives them; a wildcard whose reach is wider than the sentence describing it is
# the same defect in miniature.
review_tree() {
  local idx list rc
  git rev-parse --verify -q HEAD >/dev/null || die "HEAD does not resolve; there is no tree to bind"
  idx=$(mktemp "${TMPDIR:-/tmp}/beam_mcp-signoff-idx.XXXXXXXX") || die "cannot create a scratch index"
  list=$(mktemp "${TMPDIR:-/tmp}/beam_mcp-signoff-list.XXXXXXXX") || die "cannot create a temp file"
  GIT_INDEX_FILE="$idx" git read-tree HEAD || { rm -f "$idx" "$list"; die "git read-tree HEAD failed"; }
  git ls-tree -r -z --name-only HEAD | grep -z -E '^slices/[^/]+/signoff/' > "$list"
  if [ -s "$list" ]; then
    GIT_INDEX_FILE="$idx" git update-index -z --force-remove --stdin < "$list" \
      || { rm -f "$idx" "$list"; die "could not remove the signoff paths from the scratch index"; }
  fi
  GIT_INDEX_FILE="$idx" git write-tree; rc=$?
  rm -f "$idx" "$list"
  [ "$rc" -eq 0 ] || die "git write-tree failed; refusing to bind an unmeasured tree"
}

# ---------------------------------------------------------------------------
# Both commands refuse on a tree that is not the tree the hash describes.
#
# Untracked files UNDER slices/<slice>/signoff/ are tolerated, and only those: they are
# excluded from the reviewed tree by construction, so their presence cannot change the value
# being bound. Anything else -- a modified tracked file, a deletion, a staged change, an
# untracked file anywhere else -- means the hash would not describe what is in front of you.
require_clean_tree() {
  local dirty=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      '?? '*)
        case "${line#?? }" in
          slices/*/signoff/*) continue ;;
        esac
        ;;
    esac
    dirty="${dirty}${line}"$'\n'
  done < <(git status --porcelain --untracked-files=all)
  if [ -n "$dirty" ]; then
    printf '%s' "$dirty" | sed 's/^/  /' >&2
    die "the working tree is not the tree a hash would describe. Commit or revert first."
  fi
}

valid_round() { case "$1" in 0*|''|*[!0-9]*) return 1 ;; esac; [ "${#1}" -le 4 ]; }
valid_lane()  { printf '%s' "$1" | grep -qE '^[a-z][a-z0-9]{0,7}$'; }
valid_hash()  { printf '%s' "$1" | grep -qE '^[0-9a-f]{40}$|^[0-9a-f]{64}$'; }

field() { # field <file> <name>   -- prints the value, empty if absent
  sed -n "s/^$2: //p" "$1" | head -1
}

# ---------------------------------------------------------------------------
cmd="${1:-}"
case "$cmd" in
  record|verify) shift ;;
  *) die "usage: tools/signoff.sh record <slice-dir> <round> <lane> <approve|changes-required> [note]
                  tools/signoff.sh verify <slice-dir>" ;;
esac

slice_dir="${1:-}"; shift || true
[ -n "$slice_dir" ] || die "no slice directory given"
slice_dir="${slice_dir%/}"
[ -d "$slice_dir" ] || die "$slice_dir/ does not exist"
sdir="$slice_dir/signoff"

if [ "$cmd" = "record" ]; then
  round="${1:-}"; lane="${2:-}"; verdict="${3:-}"; note="${4:-}"
  [ -n "$round" ] && [ -n "$lane" ] && [ -n "$verdict" ] \
    || die "usage: tools/signoff.sh record <slice-dir> <round> <lane> <approve|changes-required> [note]"
  valid_round "$round" || die "round must be 1-4 digits with no leading zero (got '$round')"
  valid_lane  "$lane"  || die "lane must be 1-8 lowercase alphanumerics starting with a letter (got '$lane')"
  case "$verdict" in
    approve|changes-required) ;;
    *) die "verdict must be exactly 'approve' or 'changes-required' (got '$verdict')" ;;
  esac
  case "$note" in *$'\n'*) die "the note must be a single line" ;; esac

  require_clean_tree
  tree=$(review_tree) || exit 1
  head=$(git rev-parse HEAD) || die "cannot read HEAD"

  mkdir -p "$sdir" || die "cannot create $sdir/"
  out="$sdir/round$round.$lane.signoff"
  if [ -e "$out" ]; then
    die "$out already exists. A verdict is appended, never rewritten (CONVENTIONS.md).
    If this lane is revising, record the revision as the next round."
  fi
  {
    echo "# A review verdict and the tree it is about, in one file, because this repository has"
    echo "# shipped 16 verdicts bound to no tree and 2 trees carrying no verdict. Written by"
    echo "# tools/signoff.sh; the tree is HEAD's tree with slices/*/signoff/ removed."
    echo "#"
    echo "# This records WHICH tree the verdict is about. It cannot show that anyone read it."
    echo ""
    echo "slice: $slice_dir"
    echo "round: $round"
    echo "lane: $lane"
    echo "verdict: $verdict"
    echo "tree: $tree"
    echo "commit: $head"
    echo "recorded: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "note: $note"
  } > "$out" || die "could not write $out"
  echo "recorded: $out"
  echo "  verdict: $verdict"
  echo "  tree:    $tree"
  echo "  commit:  $head"
  exit 0
fi

# ---------------------------------------------------------------------------
# verify
require_clean_tree
[ -d "$sdir" ] || die "$sdir/ does not exist. No signoff is not a signoff."

# Nothing but records may live here. "Excluded from the reviewed tree" must not become a place
# to put code -- an exclusion nobody polices is a hole with a comment over it.
#
# THE ENTRY TYPE IS CHECKED BEFORE THE NAME, and -L is tested before -f because -f FOLLOWS the
# link. The first draft enumerated with `find -mindepth 1 -type f`, which does not match a
# symlink, so a symlink under the excluded directory was seen by neither this loop nor the
# subdirectory check below and `verify` exited 0 over it. Measured in round 1
# (logs/round1.r1.md): a committed `120000 blob ... slices/test/signoff/anything.sh` pointing
# out of the directory left the reviewed tree unchanged -- correctly, it is excluded -- and
# passed the whitelist, while a REGULAR file at the same path was refused. An exclusion a link
# walks through is not an exclusion, and this one is the tool's own promise that "excluded from
# the reviewed tree" is not a place to put things.
while IFS= read -r f; do
  [ -L "$f" ] && die "$f is a symbolic link. $sdir/ is excluded from the reviewed tree, so a link out of it carries content no review sees."
  [ -f "$f" ] || die "$f is not a regular file. $sdir/ holds records and nothing else."
  case "${f##*/}" in
    *.signoff|verify.txt) ;;
    *) die "$f is not a *.signoff record. $sdir/ is excluded from the reviewed tree and may hold nothing else." ;;
  esac
done < <(find "$sdir" -mindepth 1 ! -type d | sort)
if find "$sdir" -mindepth 1 -type d | grep -q .; then
  die "$sdir/ contains a subdirectory. Records are flat, so the whitelist above cannot be walked around."
fi

records=()
while IFS= read -r f; do records+=("$f"); done < <(find "$sdir" -maxdepth 1 -name '*.signoff' -type f | sort)
n=${#records[@]}

# THE ONE REFUSAL THIS TOOL MUST NOT GET WRONG. A slice with no records is the exact defect the
# slice this tool was written in is about: a check reporting on a population it never looked at.
# Zero records is not a clean review.
[ "$n" -gt 0 ] || die "$sdir/ holds no *.signoff records. Nothing to check is not a pass."

current=$(review_tree) || exit 1
valid_hash "$current" || die "the computed review tree is not a hash: '$current'"

# ---------------------------------------------------------------------------
# ONLY THE HIGHEST ROUND DECIDES. Earlier rounds are printed as history and do not block.
#
# THIS IS A DELIBERATE DEPARTURE FROM PLAN.md 4, AND THE TOOL'S FIRST REAL USE IS WHAT FOUND
# IT. That table says "any record's verdict is changes-required -> refuse" and "a record's tree
# hash != the current review tree -> STALE, refuse", over every record. Applied to a slice that
# actually runs rounds, those two rules make a signoff unreachable:
#
#   - a round-1 changes-required record refuses forever, so a slice that ever needed a change
#     can never be signed off -- and needing a change is what rounds are FOR;
#   - a round-1 approve record goes STALE the instant round 2's fix commit lands, so a slice
#     that runs more than one round can never be signed off either.
#
# A check that cannot pass is the mirror of a check that cannot fail, and CONVENTIONS.md is
# explicit that the second "reads as coverage and is not". The first reads as rigour and is
# not: its only stable outcome is to be switched off. So the highest round decides, and the
# earlier ones are kept because a superseded verdict is the record of what was found -- which
# is the half of this slice that is not about tooling at all.
#
# What is NOT relaxed: every record still has to parse, in every round. An unparseable record
# is refused, never skipped, whatever round it belongs to.
top=""
for f in "${records[@]}"; do
  r=$(field "$f" round)
  valid_round "$r" || die "$f: malformed round '$r'"
  if [ -z "$top" ] || [ "$r" -gt "$top" ]; then top="$r"; fi
done

echo "== signoff verify: $slice_dir =="
echo "   review tree (HEAD's tree, slices/*/signoff/ removed): $current"
echo "   deciding round: $top   (earlier rounds are history and do not block)"

fail=0
stale=0
deciding=0
for f in "${records[@]}"; do
  base="${f##*/}"
  r_slice=$(field "$f" slice); r_round=$(field "$f" round); r_lane=$(field "$f" lane)
  r_verdict=$(field "$f" verdict); r_tree=$(field "$f" tree)

  # A record missing a field is REFUSED, not skipped. Skipping is how a population loses a
  # member quietly, which is the whole subject of this slice.
  for pair in "slice:$r_slice" "round:$r_round" "lane:$r_lane" "verdict:$r_verdict" "tree:$r_tree"; do
    [ -n "${pair#*:}" ] || die "$f has no '${pair%%:*}:' line. An unparseable record is refused, never skipped."
  done
  valid_round "$r_round" || die "$f: malformed round '$r_round'"
  valid_lane  "$r_lane"  || die "$f: malformed lane '$r_lane'"
  valid_hash  "$r_tree"  || die "$f: 'tree:' is not a hash: '$r_tree'"
  [ "$r_slice" = "$slice_dir" ] || die "$f records slice '$r_slice' but lives under $slice_dir/"
  # The filename must agree with the contents, or a record could claim to be a round it is not.
  [ "$base" = "round$r_round.$r_lane.signoff" ] \
    || die "$f contents say round $r_round lane $r_lane, which is not what the filename says"

  case "$r_verdict" in
    approve|changes-required) ;;
    *) die "$f: verdict is '$r_verdict', which is neither approve nor changes-required" ;;
  esac

  if [ "$r_round" != "$top" ]; then
    echo "   round $r_round $r_lane: $r_verdict (superseded by round $top)"
    continue
  fi
  deciding=$((deciding + 1))

  if [ "$r_verdict" = "changes-required" ]; then
    echo "   round $r_round $r_lane: CHANGES-REQUIRED"; fail=1; continue
  fi
  if [ "$r_tree" != "$current" ]; then
    echo "   round $r_round $r_lane: STALE"
    echo "        read: $r_tree"
    echo "        now:  $current"
    stale=1; fail=1; continue
  fi
  echo "   round $r_round $r_lane: approve, on the current review tree"
done

# The deciding round having no records is the S4 refusal one level down, and it is reachable:
# every record could belong to an earlier round only if `top` were wrong, so this is a guard on
# the loop above rather than on the input. It fails closed rather than reading as a clean round.
[ "$deciding" -gt 0 ] || die "round $top produced no records in the loop; refusing rather than reporting a round nobody signed"

if [ "$fail" -eq 0 ]; then
  echo "   round $top: $deciding record(s), all approve, all on the tree in front of you."
  echo "   ($n record(s) in total, including superseded rounds.)"
  {
    echo "# Written by tools/signoff.sh verify. It says which tree the records bind, not that"
    echo "# anyone read it."
    echo "slice: $slice_dir"
    echo "review-tree: $current"
    echo "deciding-round: $top"
    echo "deciding-records: $deciding"
    echo "records-total: $n"
    echo "verified: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$sdir/verify.txt"
  echo "   wrote $sdir/verify.txt"
  exit 0
fi
[ "$stale" -eq 1 ] && echo "   A stale record is slice 001b's failure: the tree moved after the lanes approved it."
die "$slice_dir is not signed off."
