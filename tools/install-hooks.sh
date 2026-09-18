#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Opt in to the tracked git hooks: points this clone's core.hooksPath at tools/hooks, so
# `git commit` runs the gate (pre-commit) and reads the message through the publication
# terms (commit-msg). Nothing is copied into .git/, so the hooks are the tracked files and
# change with the tree. `tools/install-hooks.sh --uninstall` unsets the path again.
#
# WHY OPT-IN. A gate that only CI runs is a gate a hand forgets (G-014: every "landed" that
# was not); a hook nobody asked for is one they delete. So the installer is a choice, made
# once per clone, and said in CONTRIBUTING.md. The bypass is git's own: `--no-verify`.
#
#     ./tools/install-hooks.sh              # install
#     ./tools/install-hooks.sh --uninstall  # remove
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

case "${1:-}" in
  "")
    [ -x tools/hooks/pre-commit ] && [ -x tools/hooks/commit-msg ] \
      || { echo "install-hooks: tools/hooks/pre-commit and commit-msg must exist and be executable"; exit 1; }
    git config core.hooksPath tools/hooks || exit 1
    echo "hooks installed: core.hooksPath = $(git config core.hooksPath) (pre-commit runs tools/gate.sh; commit-msg runs tools/text_terms.sh; git commit --no-verify skips both)"
    ;;
  --uninstall)
    if [ "$(git config core.hooksPath || true)" = "tools/hooks" ]; then
      git config --unset core.hooksPath || exit 1
      echo "hooks uninstalled: core.hooksPath unset"
    else
      echo "hooks not installed here (core.hooksPath is '$(git config core.hooksPath || true)'); nothing changed"
    fi
    ;;
  *)
    echo "usage: tools/install-hooks.sh [--uninstall]"; exit 2 ;;
esac
