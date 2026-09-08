# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# M13rev -- the (c) fix removed: `spec.input_schema` and the annotation walk go back OUTSIDE
# `host_call/1`, which is exactly mutant M13 from slices/002-streamable-http/logs/mutation-round7.txt.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """           {:ok, entries} <- host_call(fn -> tool_annotations(catalog, name) end) do
        entries"""
new = """           {:ok, spec} <- host_call(fn -> ToolCatalog.fetch(catalog, name) end),
           entries = annotations(spec.input_schema),
           :ok <- check_annotations(name, entries) do
        entries"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
# tool_annotations/2 is now unused: remove it, or --warnings-as-errors kills the build before
# the suite runs and the table records a kill no test made (CONVENTIONS.md, "the compiler kill").
start = s.index("    defp tool_annotations(catalog, name) do")
end = s.index("\n    end\n", start) + len("\n    end\n")
s = s[:start] + s[end:]
assert "tool_annotations" not in s, "orphan left behind"
io.open(p, "w", encoding="utf-8").write(s)
print("M13rev applied")
