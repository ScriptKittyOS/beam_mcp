#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The one place the publication terms live: the words a commit message or a pull-request
# body must not carry -- an attribution trailer, a session link, a board identifier, a
# consumer's name. Reads stdin; prints every offending line; exits 1 if there is one, 0 if none.
#
#     git log -1 --format=%B <hash> | tools/text_terms.sh
#     printf '%s' "$PR_BODY" | tools/text_terms.sh
#
# WHY ONE SCRIPT. The gate's `messages` step carried this pattern inline and read the branch's
# commits; a pull-request body was read by nobody automated (G-015): 008's body carried a
# trailer and a session URL until a hand removed them. A body is not a commit message and
# cannot be read offline -- it exists only on GitHub -- so the CI workflow reads it from the
# pull_request event and hands it here, the same terms the gate applies to messages. Two seats,
# one pattern; the pattern names nothing the tree does not name already
# (test/beam_mcp/publication_content_test.exs carries the consumer names and the board prefix).
set -uo pipefail
grep -i -E 'Co-Authored-By:|Claude-Session:|claude\.ai|SCR-[0-9]+|Ultraviolet|Trinity' && exit 1
exit 0
