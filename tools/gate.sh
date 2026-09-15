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

# THE FORMAT POPULATION IS THE TRACKED SET, NOT `.formatter.exs`'s GLOB. The glob once read
# `{lib,test}/**/*.{ex,exs}`; five tracked Elixir scripts under tools/ sat outside it, a
# syntax error appended to one of them passed the whole gate green (measured, 2026-09-08),
# and slice 008 broke four of them without a red line anywhere. A glob is a hand list of
# directories: bench/ had to be added to it by name, and the next directory would be
# forgotten the same way. Here every tracked `.ex` and `.exs` is handed to the formatter
# explicitly, from the same `git ls-files` the REUSE and publication steps read, and the
# count is printed beside the verdict. The glob stays in `.formatter.exs` for a developer's
# bare `mix format`, and lists the same directories today; disagreeing with it is this
# step's job, not a defect in it.
# Read with -z / -0 so a name with whitespace is one name, as the REUSE and publication
# steps read theirs.
fmt_n=$(git ls-files -- '*.ex' '*.exs' | grep -c .)
fmt_out=$(git ls-files -z -- '*.ex' '*.exs' | xargs -0 mix format --check-formatted 2>&1); fmt_rc=$?
if [ "$fmt_rc" -eq 0 ] && [ "$fmt_n" -gt 0 ]; then
  note "format" "pass ($fmt_n tracked .ex/.exs)"
else
  note "format" "FAIL (exit $fmt_rc, $fmt_n tracked .ex/.exs)"
  printf '%s\n' "$fmt_out" | sed 's/^/      /'; fail=1
fi
step "compile"  mix compile --warnings-as-errors --force

# The other instruments: every tracked shell script and every tracked Python file (the
# mutants, the scoring harness's probes) must at least parse. `bash -n` and `ast.parse`
# are not compilation -- a shell script that calls a command that no longer exists, or a
# mutant whose anchor no longer matches, is not seen here; the mutation harness reports
# the latter as NOT-APPLIED when it runs. The limit, stated: an Elixir script under
# tools/ is parsed by the format step and run by nobody, so a call into a module the
# package renamed is caught only when the script is next run by hand. Populations from
# `git ls-files`, counts printed, an absent interpreter is a failure and not a pass.
inst_fail=""; n_sh=0; n_py=0
while read -r f; do
  [ -n "$f" ] || continue
  n_sh=$((n_sh + 1))
  bash -n "$f" 2>/dev/null || inst_fail="${inst_fail}${f}  (bash -n)"$'\n'
done <<< "$(git ls-files -- '*.sh')"
py_files=$(git ls-files -- '*.py')
if [ -n "$py_files" ]; then
  if command -v python3 >/dev/null 2>&1; then
    while read -r f; do
      [ -n "$f" ] || continue
      n_py=$((n_py + 1))
      python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>/dev/null \
        || inst_fail="${inst_fail}${f}  (python3 ast.parse)"$'\n'
    done <<< "$py_files"
  else
    inst_fail="${inst_fail}python3 not found: $(printf '%s\n' "$py_files" | grep -c .) tracked .py files unparsed"$'\n'
  fi
fi
if [ -z "$inst_fail" ]; then
  note "instruments" "pass ($n_sh tracked .sh parse, $n_py tracked .py parse)"
else
  note "instruments" "FAIL ($n_sh tracked .sh, $n_py tracked .py)"
  printf '%s' "$inst_fail" | sed 's/^/      /'; fail=1
fi
step "test"     mix test
step "credo"    mix credo --strict

# The property gate. The suite above runs every property at StreamData's default of 100
# generations, which is what a developer's run should cost; this step runs the properties
# alone at ten times that, so the release tree is searched harder than a working one. The
# count reaches the generators through PROPERTY_RUNS, which test/test_helper.exs reads
# (shown red before it did: a probe property counting its own generations passed under
# PROPERTY_RUNS=1000 on the tree before the helper read it). The number of properties is
# read from ExUnit's summary and printed, and a summary with none is a failure: a pass over
# an empty population is the defect this gate's REUSE step was rewritten to remove.
prop_runs=1000
prop_out=$(PROPERTY_RUNS=$prop_runs mix test --only property 2>&1); prop_rc=$?
prop_n=$(printf '%s\n' "$prop_out" | grep -oE '^[0-9]+ propert(y|ies)' | tail -1 | cut -d' ' -f1)
if [ "$prop_rc" -eq 0 ] && [ -n "$prop_n" ] && [ "$prop_n" -gt 0 ]; then
  note "properties" "pass ($prop_n properties at $prop_runs generations each)"
else
  note "properties" "FAIL (exit $prop_rc, ${prop_n:-0} properties found)"
  printf '%s\n' "$prop_out" | sed 's/^/      /'; fail=1
fi

# `optional: true` is a resolution flag, not a compilation one: the HTTP transport compiles here,
# where plug is present, and broke every stdio-only consumer until round 1. Asserted on the
# artefact in a throwaway consumer project, because a compile that "succeeded" is not evidence.
step "optional deps" bash tools/probe_optional_deps.sh

# The benchmark gate. `bench/overhead.exs` measures the observed collector's per-call
# overhead and exits 1 over its threshold -- a ceiling the owner set, with its reasoning in
# the script; `bench/diff.exs` records the diff engine's cost on a 10 000-edge fixture and
# judges nothing, because no threshold has been set for it. All three scripts are run here, so a
# file under bench/ that does not compile fails this step rather than sitting outside every
# population the gate reads (the defect tools/ once had). Their one-line figures are kept in
# the note, because a pass that hides its number is a number nobody can compare later.
# `bench/reach.exs` records the reachability queries' cost on the same fixture, warm-up and
# medians, and judges nothing either: it is the measurement graph cost is decided against.
bench_out=$(mix run bench/overhead.exs 2>&1); bench_rc=$?
diff_out=$(mix run bench/diff.exs 2>&1); diff_rc=$?
reach_out=$(mix run bench/reach.exs 2>&1); reach_rc=$?
if [ "$bench_rc" -eq 0 ] && [ "$diff_rc" -eq 0 ] && [ "$reach_rc" -eq 0 ]; then
  note "bench" "pass ($(printf '%s\n' "$bench_out" | tail -1); $(printf '%s\n' "$diff_out" | tail -1); $(printf '%s\n' "$reach_out" | tail -1))"
else
  note "bench" "FAIL (overhead exit $bench_rc, diff exit $diff_rc, reach exit $reach_rc)"
  printf '%s\n%s\n%s\n' "$bench_out" "$diff_out" "$reach_out" | sed 's/^/      /'; fail=1
fi

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
# THE TRACKED-SET LOOKUP USES NO ASSOCIATIVE ARRAY, AND THAT IS A CORRECTNESS REQUIREMENT
# RATHER THAN A STYLE ONE. It was `declare -A tracked` with `tracked["$f"]=1`. Bash 3.2 -- the
# bash every stock macOS ships -- has no `-A`, so `tracked["$f"]` becomes an INDEXED array whose
# subscript is evaluated as ARITHMETIC. `.formatter.exs` is not an arithmetic expression, the
# expansion is a fatal error for the enclosing command, and both loops abort at their first
# offending path. Measured by simulation (round 1, logs/round1.r1.md):
#
#     reuse                      pass (10 tracked; 10 in scope, 9 headered + 0 sidecar; excluded 0 archive + 0 licence text)
#     Gate OK.
#     EXIT=0
#
# `pass` over ten files out of 145, and the gate exits 0 -- which is the exact defect this step
# was rewritten to remove, reintroduced by the rewrite, on every developer machine running the
# system bash. Two lines on stderr were the only sign.
#
# The replacement is a newline-delimited string tested with a `case` glob: a shell builtin, no
# subprocess, no arithmetic context, and correct on bash 3.2. It is filled from the SAME
# `git ls-files` invocation that drives the loop below, so the population and the coverage
# lookup cannot disagree about what "tracked" means -- which is the whole content of this step.
# tools/probe_gate_honesty.sh P9 fails if an associative array reappears here.
tracked_paths=$'\n'$(git ls-files)$'\n'
is_tracked() { case "$tracked_paths" in *$'\n'"$1"$'\n'*) return 0 ;; esac; return 1; }
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
  if is_tracked "$f.license" && head -5 "$f.license" | grep -q 'SPDX-License-Identifier'; then
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

# Publication boundary: the repository is public and its history is publishable at every commit.
#
# Working records -- plans, findings, review notes, decision records -- live outside the tree
# from here on, under an ignored directory, and this step is what makes "ignored" a verdict
# rather than a hope. Since 2026-09-13 the records live in a separate repository outside this
# worktree altogether, so the ignore rule and this census are a backstop for a file written to
# the old path out of habit, not the primary control. THE POPULATION IS `git ls-files`, THE SAME SOURCE THE REUSE STEP READS, so
# a file that is on disk but not added is not in it -- which is correct, because that file is
# not in any commit. What IS checked, in four parts, each with its own line of output:
#
#   1. The ignore rule exists IN THE TRACKED .gitignore. `git check-ignore -v` names the source
#      of the rule that matched, and only `.gitignore` counts: a rule in .git/info/exclude or in
#      a global excludes file would satisfy `-q` on the author's machine and not exist in CI or
#      in a clone, which is the same shape as the untracked sidecar the REUSE step once accepted.
#   2. No tracked path is under the internal directory. `git add -f` bypasses the ignore rule,
#      and that is exactly the act this line exists to catch.
#   3. No tracked path is under slices/ beyond the set frozen in tools/publication-allowlist.txt.
#      The existing slice records stay tracked, deliberately and by name -- untracking them would
#      not remove them from history, and rewriting history is not this script's to do. New
#      records do not join them. The allowlist is pinned by sha256 so that widening it is an
#      edit to this file, visible in a diff, and not a quiet append.
#   4. Under either directory, every tracked entry is a regular file (mode 100644 or 100755);
#      and no tracked name anywhere has a newline in it. A symlink (120000) at a grandfathered path would publish
#      its target string -- an internal path name -- under a name the allowlist admits; a
#      gitlink (160000) at the same path passed the WHOLE GATE green when measured, because
#      the census read names and not modes. A name containing a newline can spell two adjacent
#      allowlist lines and match them both; measured, it was counted as grandfathered.
#
# THE POPULATION IS READ WITH `-s -z` AND `IFS= read -r -d ''`, AND THAT IS A CORRECTNESS
# REQUIREMENT. The first version read `git ls-files` line by line with `read -r` and default
# IFS, and it passed three probes it should have refused, measured on the tree that shipped it:
#
#   - a file named `slices/001-revision-negotiation/PLAN.md ` -- a trailing space -- was read
#     with the space stripped, matched the allowlisted path, and was counted as GRANDFATHERED.
#     The whole gate was green over it.
#   - a force-added `.internal/é` arrived C-quoted as `".internal/\303\251"`, matched neither
#     `case` pattern, and was counted as an ordinary tracked file. `-z` disables the quoting.
#   - a symlink replacing a grandfathered path was listed by its name alone, and its name was
#     allowed. `-s` carries the mode, and 120000 is refused under either directory.
#
# The limit, stated: this is a census over PATHS. A board identifier or a consumer's name inside
# a tracked file is not seen here, because the pattern that would find it would itself be the
# thing this step exists to keep out of a public script. Both the ignore rule and the patterns
# below are root-anchored: a nested `lib/.internal/` is neither ignored nor detected.
internal_dir=".internal"
allowlist="tools/publication-allowlist.txt"
allowlist_sha="ee5dc25859a7ccc153b25a1216ba65abfa3d576117d5b7c327e9b37296dde5c3"
pub_fail=0
# TWO QUESTIONS, TWO COMMANDS. `-q` answers "is the path ignored?" with its exit status alone.
# `-v` answers "which rule matched?" -- and under -v the exit status means something else:
# a NEGATED pattern that matches the probe directly (`!/.internal/*`) is printed and exits 0,
# although nothing is ignored. Measured on git 2.43: with that mis-edit in place, `-v` printed
# `.gitignore:20:!/.internal/*`, exited 0, and the whole gate was green; `-q` exited 1. So the
# fact comes from -q and only the source name comes from -v.
if git check-ignore -q "$internal_dir/probe" 2>/dev/null; then
  case "$(git check-ignore -v "$internal_dir/probe" 2>/dev/null)" in
    .gitignore:*) pub_ignore="rule in .gitignore" ;;
    *)            pub_ignore="IGNORE RULE for $internal_dir/ IS NOT IN THE TRACKED .gitignore"; pub_fail=1 ;;
  esac
else
  pub_ignore="NO IGNORE RULE for $internal_dir/"; pub_fail=1
fi
if [ -f "$allowlist" ] && [ "$(sha256sum "$allowlist" | cut -d' ' -f1)" = "$allowlist_sha" ]; then
  allowed=$'\n'$(grep -v '^#' "$allowlist")$'\n'
  pub_allow="allowlist pinned"
else
  allowed=$'\n'
  pub_allow="ALLOWLIST MISSING OR CHANGED (sha256 mismatch)"; pub_fail=1
fi
n_pub=0; n_grand=0; pub_violations=""
# Each -s -z entry is `<mode> <object> <stage>\t<path>`, NUL-terminated. The path is everything
# after the tab, byte for byte: no quoting, no trimming, a trailing space is part of the name.
while IFS= read -r -d '' entry; do
  n_pub=$((n_pub + 1))
  mode="${entry%% *}"
  f="${entry#*	}"
  # A newline in a tracked name is refused anywhere in the tree: no legitimate path has one,
  # and the allowlist lookup below is newline-delimited, so such a name could match two lines.
  case "$f" in *$'\n'*) pub_violations="${pub_violations}${f}  (newline in name)"$'\n'; continue ;; esac
  case "$f" in
    "$internal_dir"/*|slices/*)
      case "$mode" in
        100644|100755) ;;
        120000) pub_violations="${pub_violations}${f}  (symbolic link)"$'\n'; continue ;;
        *)      pub_violations="${pub_violations}${f}  (mode $mode, not a regular file)"$'\n'; continue ;;
      esac ;;
  esac
  case "$f" in
    "$internal_dir"/*) pub_violations="${pub_violations}${f}  (internal directory)"$'\n' ;;
    slices/*)
      case "$allowed" in
        *$'\n'"$f"$'\n'*) n_grand=$((n_grand + 1)) ;;
        *) pub_violations="${pub_violations}${f}  (new under slices/)"$'\n' ;;
      esac ;;
  esac
done < <(git ls-files -s -z)
if [ "$pub_fail" -eq 0 ] && [ -z "$pub_violations" ]; then
  note "publication" "pass ($n_pub tracked; $n_grand grandfathered under slices/; 0 internal; $pub_ignore; $pub_allow)"
else
  note "publication" "FAIL ($n_pub tracked; $n_grand grandfathered under slices/; $pub_ignore; $pub_allow)"
  [ -n "$pub_violations" ] && { printf '      tracked paths that must not be:\n'; printf '%s' "$pub_violations" | sed 's/^/        /'; }
  fail=1
fi

# Commit messages: the branch's own commits carry no attribution trailer, no session link, no
# board identifier and no consumer name.
#
# THE POPULATION IS THE BRANCH'S OWN COMMITS -- those reachable from HEAD and not from
# origin/main -- and the step says so on its line. On main itself, or where origin/main does
# not resolve, the population is empty and the line says that too rather than printing `pass`
# over nothing it looked at. The patterns are the ones a public test in this tree already
# carries (test/beam_mcp/publication_content_test.exs), plus the two trailer names and the
# session-URL host; nothing here names anything the tree does not name already.
#
# The limit, stated: a pull request's body is not a commit message and is not read here. A
# body is policed by a person reading it before merge.
msg_fail=0
if base=$(git merge-base origin/main HEAD 2>/dev/null); then
  n_msgs=$(git rev-list --count "$base"..HEAD)
  msg_hits=$(for h in $(git rev-list "$base"..HEAD); do
    git log -1 --format=%B "$h" | sed "s/^/$(git rev-parse --short "$h")	/"
  done | grep -i -E 'Co-Authored-By:|Claude-Session:|claude\.ai|SCR-[0-9]+|Ultraviolet|Trinity' || true)
  if [ -z "$msg_hits" ]; then
    note "messages" "pass ($n_msgs commit(s) since origin/main; none names a trailer, a session, a board id or a consumer)"
  else
    note "messages" "FAIL ($n_msgs commit(s) since origin/main)"
    printf '      lines naming a trailer, a session, a board id or a consumer (hash<TAB>text):\n'
    printf '%s\n' "$msg_hits" | sed 's/^/        /'
    msg_fail=1; fail=1
  fi
else
  note "messages" "pass (origin/main does not resolve here; 0 commits examined -- this line is not evidence)"
fi

if [ "$fail" -eq 0 ]; then echo "Gate OK."; else echo "GATE FAILED."; fi
exit "$fail"
