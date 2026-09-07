#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The quality gate. Every step reports its own verdict and its own exit code; a step that
# cannot measure something says so rather than passing. There are no ratchet baselines here:
# this tree starts clean and stays at zero, so a non-zero count is a failure, not a baseline.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

fail=0
note() { printf '  %-26s %s\n' "$1" "$2"; }
step() { # step <name> <command...>
  local name="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then note "$name" "pass"
  else note "$name" "FAIL (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; fail=1; fi
}

echo "== beam_mcp gate =="

step "format"   mix format --check-formatted
step "compile"  mix compile --warnings-as-errors --force
step "test"     mix test
step "credo"    mix credo --strict

# `optional: true` is a resolution flag, not a compilation one: the HTTP transport compiles here,
# where plug is present, and broke every stdio-only consumer until round 1. Asserted on the
# artefact in a throwaway consumer project, because a compile that "succeeded" is not evidence.
step "optional deps" bash tools/probe_optional_deps.sh

# `mix docs` EXITS 0 ON A WARNING, so its status is not a verdict and this step reads its output.
#
# A hidden module referenced by the docs shipped in 0.1.0 as `BeamMCP.Server`, and the CHANGELOG
# entry recording that also recorded why nothing caught it: "a hidden module is not a compile
# warning and the gate does not run `mix docs`". The gate then did not run mix docs for two more
# releases, and 0.3.0's first cut reproduced the defect on `BeamMCP.Transport.Stdio` -- the
# transport the README documents as the entry point. Fixing the instance twice and the mechanism
# never is what this step is for.
docs_out=$(mix docs 2>&1); docs_rc=$?
docs_warnings=$(printf '%s\n' "$docs_out" | grep -c 'warning:')
if [ "$docs_rc" -eq 0 ] && [ "$docs_warnings" -eq 0 ]; then
  note "docs" "pass"
else
  note "docs" "FAIL (exit $docs_rc, $docs_warnings warnings)"
  printf '%s\n' "$docs_out" | sed 's/^/      /'; fail=1
fi

# REUSE: every tracked file carries an SPDX identifier.
#
# THE POPULATION IS `git ls-files`, WITH NO GLOB. It used to be
#
#     git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml'
#
# under a comment that said "derived from the tracked set, never from a hand list". It was a
# hand list, and it covered 24 of 122 tracked files. A `.md`, a `.yaml`, a `.toml` or an
# extensionless file did not fail this step -- it was never in it, and the step printed `pass`
# over everything it had not looked at. That is CONVENTIONS.md's "proves nothing, and proves
# nothing quietly", in the check the convention was written about.
#
# A file is covered if the identifier is in its own head, OR in a `<path>.license` sidecar --
# REUSE's own mechanism for a file whose bytes must not change. One rule, applied to any path;
# no extension is privileged and no new file type can escape by not matching a glob.
#
# THE SIDECAR IS LOOKED UP IN THE TRACKED SET, NOT ON DISK. It was `[ -f "$f.license" ]` -- a
# filesystem test, sitting beside a population that comes from `git ls-files` -- so an UNTRACKED
# sidecar covered a tracked file on the author's disk and did not exist in a fresh clone or in
# CI. That is CONVENTIONS.md's instance #1 ("an unadded file is invisible to git ls-files"),
# repeated on the COVERAGE side of the very check the convention was written about, and it was
# measured red before it was fixed -- slices/004-gate-honesty/logs/red-sidecar-untracked.txt
# records `reuse pass (... 3 sidecar)` and `GATE_EXIT=0` over a sidecar that was never added.
# Both halves now read one source of truth, which is the whole content of this step.
#
# TWO EXCLUSIONS SURVIVE. Both are structural rather than convenient, both cite the rule they
# come from, and both are COUNTED AND PRINTED on every run so neither can grow quietly:
#
#   1. slices/*/logs/*  -- the verbatim archives. CONVENTIONS.md: "A verbatim archive is
#      written by a command that fetches it, or it does not exist." Editing their bytes is the
#      thing that destroys them, and three of them are upstream specification pages whose
#      licence is not this project's to declare.
#   2. The licence texts. REUSE's own spec exempts them: a licence text carries no licensing
#      information of its own. Derived rather than named -- `LICENSES/*`, plus any tracked file
#      byte-identical to one of them, which is how the root `LICENSE` (sha256-identical to
#      LICENSES/Apache-2.0.txt) is recognised without appearing in this script as a name.
#
# The limit, stated rather than hidden: source code placed under slices/*/logs/ would escape
# this step. The count printed beside the verdict is what makes that visible.
lic_hashes=$(git ls-files -- 'LICENSES/*' | xargs -r sha256sum 2>/dev/null | cut -d' ' -f1 | sort -u)
declare -A tracked=()
while read -r f; do tracked["$f"]=1; done < <(git ls-files)
n_tracked=0; n_archive=0; n_lictext=0; n_head=0; n_sidecar=0
missing=""
while read -r f; do
  n_tracked=$((n_tracked + 1))
  case "$f" in
    slices/*/logs/*) n_archive=$((n_archive + 1)); continue ;;
    LICENSES/*)      n_lictext=$((n_lictext + 1)); continue ;;
  esac
  if head -5 "$f" | grep -q 'SPDX-License-Identifier'; then
    n_head=$((n_head + 1)); continue
  fi
  if [ -n "${tracked[$f.license]-}" ] && head -5 "$f.license" | grep -q 'SPDX-License-Identifier'; then
    n_sidecar=$((n_sidecar + 1)); continue
  fi
  # Only files that got this far are hashed: the exclusion is consulted where it decides
  # something, not swept over the whole tree.
  if [ -n "$lic_hashes" ] && printf '%s\n' "$lic_hashes" \
       | grep -qx "$(sha256sum "$f" | cut -d' ' -f1)"; then
    n_lictext=$((n_lictext + 1)); continue
  fi
  missing="${missing}${f}"$'\n'
done < <(git ls-files)
n_scope=$((n_tracked - n_archive - n_lictext))
if [ -z "$missing" ]; then
  note "reuse" "pass ($n_tracked tracked; $n_scope in scope, $n_head headered + $n_sidecar sidecar; excluded $n_archive archive + $n_lictext licence text)"
else
  note "reuse" "FAIL ($n_tracked tracked; $n_scope in scope, $n_head headered + $n_sidecar sidecar; excluded $n_archive archive + $n_lictext licence text)"
  printf '      no SPDX-License-Identifier in the file or in a <path>.license sidecar:\n'
  printf '%s' "$missing" | sed 's/^/        /'
  fail=1
fi

# The licence claim is only a claim until the files it names exist.
#
# THIS STEP'S VERDICT IS ITS OWN. It used to read `[ "$fail" -eq 0 ] && note "licence files"
# "pass"` -- the SHARED accumulator -- so a red format, test, credo, docs or reuse step deleted
# this line from the output entirely. The header of this file, thirty lines further up, promises
# that every step reports its own verdict; this was the step that did not, and it failed in the
# worst available mode: the line was not wrong, it was ABSENT, and a reader scanning for FAIL
# found nothing to scan.
lic_fail=0
for f in LICENSE NOTICE LICENSES/Apache-2.0.txt; do
  [ -f "$f" ] || { note "licence files" "FAIL -- $f missing"; lic_fail=1; fail=1; }
done
[ "$lic_fail" -eq 0 ] && note "licence files" "pass"

if [ "$fail" -eq 0 ]; then echo "Gate OK."; else echo "GATE FAILED."; fi
exit "$fail"
