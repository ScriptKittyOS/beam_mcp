# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs10 -- stdio answers a nesting refusal as a generic parse error
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      {:error, {:nesting, _depth, max}} ->
        write_message(%{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{
            "code" => -32_600,
            "message" => "Request body nests deeper than #{max} levels"
          }
        })

        loop(state)

"""
new = """"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
