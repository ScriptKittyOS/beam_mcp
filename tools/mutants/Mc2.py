# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Mc2 -- HALF THE MOVE. The spec read and the schema walk go inside host_call/1, but
# check_annotations/2 stays outside it. Tests whether the record's claim that the validity
# check is host territory too is pinned by anything, or is only argued in a comment.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """           {:ok, entries} <- host_call(fn -> tool_annotations(catalog, name) end) do
        entries"""
new = """           {:ok, entries} <- host_call(fn -> tool_annotations(catalog, name) end),
           :ok <- check_annotations(name, entries) do
        entries"""
assert s.count(old) == 1
s = s.replace(old, new)
old2 = """      with {:ok, spec} <- ToolCatalog.fetch(catalog, name),
           entries = annotations(spec.input_schema),
           :ok <- check_annotations(name, entries) do
        {:ok, entries}
      end"""
new2 = """      with {:ok, spec} <- ToolCatalog.fetch(catalog, name) do
        {:ok, annotations(spec.input_schema)}
      end"""
assert s.count(old2) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old2, new2))
print("Mc2 applied")
