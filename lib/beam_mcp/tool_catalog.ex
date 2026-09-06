# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ToolCatalog do
  @moduledoc """
  The contract a host implements to tell a `BeamMCP.Server` which tools exist.

  The server holds no catalog of its own. It advertises what `all/0` returns and accepts a
  `tools/call` only for a tool `all/0` names, so one implementation governs both — a tool
  advertised by `tools/list` and refused by `tools/call` is the defect this behaviour exists
  to make impossible.
  """

  @callback all() :: [BeamMCP.ToolSpec.t()]
end
