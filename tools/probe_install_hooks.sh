#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probes for tools/install-hooks.sh and the two hooks it points at.
#
# Everything runs inside a throwaway git repository this script builds with `git init`, so the
# repository it lives in is never touched (its own core.hooksPath in particular). The installer
# under test is the REAL tools/install-hooks.sh by absolute path; the hooks and the terms
# script are copied from the tree into the scratch repository at probe time, because
# core.hooksPath is relative to the repository the commit is made in. The gate the pre-commit
# hook runs is a PLANT: a tools/gate.sh whose exit code the probe sets, and which writes a
# marker -- the probe is about whether git runs the hook and honours its verdict, not about the
# gate's own verdicts (tools/probe_gate_honesty.sh is about those).
#
#     ./tools/probe_install_hooks.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$HERE/install-hooks.sh"
[ -x "$INSTALL" ] || { echo "no executable $INSTALL"; exit 2; }
PASSES=0; FAILS=0
ok()   { PASSES=$((PASSES + 1)); echo "  pass  $1"; }
bad()  { FAILS=$((FAILS + 1));   echo "  FAIL  $1"; }
check() { # check <description> <expected-exit> <actual-exit>
  if [ "$2" = "$3" ]; then ok "$1 (exit $3)"; else bad "$1 (expected exit $2, got $3)"; fi
}

D=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-hooks.XXXXXXXX")
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1
git init -q -b main .
git config user.email probe@example.invalid
git config user.name  Probe
git config commit.gpgsign false
mkdir -p tools/hooks
cp "$HERE/hooks/pre-commit" "$HERE/hooks/commit-msg" tools/hooks/
cp "$HERE/text_terms.sh" tools/
# The planted gate: exits with the code in tools/gate.rc, and leaves a marker that it ran.
cat > tools/gate.sh <<'GATE'
#!/usr/bin/env bash
echo ran > "$(git rev-parse --show-toplevel)/gate.ran"
exit "$(cat "$(git rev-parse --show-toplevel)/tools/gate.rc")"
GATE
chmod +x tools/gate.sh tools/hooks/pre-commit tools/hooks/commit-msg tools/text_terms.sh
echo 1 > tools/gate.rc
echo "gate.ran" > .gitignore
git add -A && git commit -q -m "initial"
commits() { git rev-list --count HEAD; }
attempt() { # attempt <message> [git commit flags...] -> exit code; stages a new line first
  local msg="$1"; shift
  echo "line $RANDOM" >> source.txt; git add source.txt
  rm -f gate.ran
  git commit -q "$@" -m "$msg" > /dev/null 2>&1
}

echo "== probe_install_hooks: $D"

# P0 -- the hooks have no .sh suffix (git needs the bare names), so the gate's instruments
# step does not parse them; this probe does.
bash -n "$HERE/hooks/pre-commit" "$HERE/hooks/commit-msg" "$INSTALL"; rc=$?
check "P0 the two hooks and the installer parse" 0 "$rc"

# P1 -- no hooks installed: a red gate is not consulted, the commit lands.
attempt "P1 no hooks"; rc=$?
check "P1 before install, a commit lands with the gate red" 0 "$rc"
[ -f gate.ran ] && bad "P1 the planted gate ran with no hook installed" || ok "P1 the gate did not run"

# P2 -- install: core.hooksPath points at the tracked directory.
"$INSTALL" > /dev/null; rc=$?
check "P2 install exits 0" 0 "$rc"
[ "$(git config core.hooksPath)" = "tools/hooks" ] && ok "P2 core.hooksPath = tools/hooks" || bad "P2 core.hooksPath = '$(git config core.hooksPath)'"

# P3 -- red gate: the commit is refused and nothing is committed.
before=$(commits); attempt "P3 red gate"; rc=$?
check "P3 a red gate refuses the commit" 1 "$rc"
[ "$(commits)" = "$before" ] && ok "P3 no commit was made" || bad "P3 a commit landed past a red gate"
[ -f gate.ran ] && ok "P3 the gate ran" || bad "P3 the gate did not run"

# P4 -- green gate: the commit lands, and the gate ran.
echo 0 > tools/gate.rc
before=$(commits); attempt "P4 green gate"; rc=$?
check "P4 a green gate lets the commit through" 0 "$rc"
[ "$(commits)" = "$((before + 1))" ] && ok "P4 one commit landed" || bad "P4 commit count $(commits), expected $((before + 1))"
[ -f gate.ran ] && ok "P4 the gate ran" || bad "P4 the gate did not run"

# P5 -- a publication term in the message: refused by commit-msg even with the gate green.
before=$(commits); attempt "P5 fixes SCR-123"; rc=$?
check "P5 a term in the message is refused" 1 "$rc"
[ "$(commits)" = "$before" ] && ok "P5 no commit was made" || bad "P5 a commit with a term landed"

# P6 -- git's own bypass: --no-verify skips both hooks (documented, not taken away).
echo 1 > tools/gate.rc
before=$(commits); attempt "P6 fixes SCR-123" --no-verify; rc=$?
check "P6 --no-verify skips the red gate and the term check" 0 "$rc"
[ -f gate.ran ] && bad "P6 the gate ran under --no-verify" || ok "P6 the gate did not run"

# P7 -- uninstall: the path is unset and a red gate is no longer consulted.
"$INSTALL" --uninstall > /dev/null; rc=$?
check "P7 uninstall exits 0" 0 "$rc"
[ -z "$(git config core.hooksPath || true)" ] && ok "P7 core.hooksPath unset" || bad "P7 core.hooksPath still '$(git config core.hooksPath)'"
attempt "P7 after uninstall"; rc=$?
check "P7 after uninstall a commit lands with the gate red" 0 "$rc"

# P8 -- the installer refuses a hook that is not executable (git would skip it silently).
chmod -x tools/hooks/pre-commit
"$INSTALL" > /dev/null 2>&1; rc=$?
check "P8 a non-executable hook is refused by the installer" 1 "$rc"
[ -z "$(git config core.hooksPath || true)" ] && ok "P8 nothing was installed" || bad "P8 core.hooksPath was set anyway"
chmod +x tools/hooks/pre-commit

# P9 -- uninstall when another hooksPath is set leaves it alone.
git config core.hooksPath somewhere/else
"$INSTALL" --uninstall > /dev/null; rc=$?
[ "$(git config core.hooksPath)" = "somewhere/else" ] && ok "P9 a foreign core.hooksPath is left alone by --uninstall" || bad "P9 a foreign core.hooksPath was changed"
git config --unset core.hooksPath

echo "== probe_install_hooks: $PASSES pass, $FAILS fail"
[ "$FAILS" -eq 0 ]
