#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The edited-summary read, out of the workflow and into a script a probe can run with a fake
# `gh`. On a pull-request body edit the legs do not run (the tree did not move) but the
# summary job carries the REQUIRED context, so it reads the legs' latest check runs for the
# head SHA and requires all three to be success. G-079 measured the hole: a body edit while the
# same SHA's legs were still running read their conclusions as null and failed "by design",
# and the ruleset then blocked the pull request on that red although the legs finished green a
# minute later -- a failed run of the required name blocks even beside a later green one. So
# this waits: it polls until every leg check-run for the SHA is `completed`, bounded, and only
# then judges. A tree whose legs never finish is a FAIL at the bound, named as such.
#
#     GH_TOKEN=... tools/ci_legs_verdict.sh <owner/repo> <head sha>
# env: LEGS_MIN (default 3), POLL_SECONDS (default 30), POLL_LIMIT (default 40 -- 20 minutes).
# exit 0: every leg completed and success; 1: a leg not success, too few legs, or the bound hit.
set -uo pipefail
[ $# -eq 2 ] || { echo "usage: tools/ci_legs_verdict.sh <owner/repo> <head-sha>" >&2; exit 2; }
repo=$1 sha=$2
min=${LEGS_MIN:-3} every=${POLL_SECONDS:-30} limit=${POLL_LIMIT:-40}
# The expanded leg names only: the skipped matrix job of the edited run registers one
# unexpanded name ("Gate - leg (OTP ${{ matrix.otp }} ...", skipped), which is not a verdict.
read_legs() {
  gh api "repos/${repo}/commits/${sha}/check-runs?filter=latest&per_page=100" \
    --jq '.check_runs[] | select(.name | test("^Gate - leg \\(OTP [0-9]+, Elixir [0-9.]+, [a-z]+\\)$")) | "\(.name): \(.status)/\(.conclusion)"'
}
i=0
while :; do
  legs=$(read_legs) || { echo "FAIL: the checks API could not be read for ${sha}"; exit 1; }
  n=$(printf '%s\n' "$legs" | grep -c . || true)
  pending=$(printf '%s\n' "$legs" | grep -vc ': completed/' || true)
  if [ "$n" -ge "$min" ] && [ "$pending" -eq 0 ]; then break; fi
  i=$((i + 1))
  if [ "$i" -gt "$limit" ]; then
    printf '%s\n' "$legs"
    echo "FAIL: after $((limit * every)) s, $n leg verdict(s) exist for ${sha} and $pending are not completed; the tree is unmeasured"
    exit 1
  fi
  echo "waiting: $n leg check-run(s), $pending not completed (poll $i of $limit, every ${every}s)"
  sleep "$every"
done
printf '%s\n' "$legs"
bad=$(printf '%s\n' "$legs" | grep -vc ': completed/success$' || true)
[ "$bad" -eq 0 ] || { echo "FAIL: a leg's latest verdict for ${sha} is not success"; exit 1; }
echo "pass: $n leg(s) completed, all success, for ${sha}"
