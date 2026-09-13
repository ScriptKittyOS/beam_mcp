# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.DeclaredAppTest do
  # Not async: the second test takes OTP's tools application off the code path for a moment,
  # and every other test that reads a beam through xref must not be running while it does.
  use ExUnit.Case, async: false

  alias BeamMCP.Connectome.Declared

  test "OTP's tools application is optional in the .app file, so a release without it still boots" do
    # Read from the .app the build wrote, not from mix.exs: the first spelling of this
    # (`optional_applications: [:tools]` as its own key) was accepted by Mix, ignored, and left
    # tools REQUIRED in the .app -- measured by review, while the changelog said otherwise.
    assert :tools in Application.spec(:beam_mcp, :applications)
    assert :tools in Application.spec(:beam_mcp, :optional_applications)
  end

  test "without :xref on the code path the builder refuses by name instead of crashing" do
    ebin = :code.lib_dir(:tools) |> Path.join("ebin") |> to_string()
    true = Code.delete_path(ebin)
    # Delete, then purge: the other order leaves old code lingering after the reload, and a
    # second run in one VM would refuse the delete. This test crashes rather than skips on an
    # OTP without tools; the rest of the suite needs xref anyway.
    :code.delete(:xref)
    :code.purge(:xref)

    try do
      refute Code.ensure_loaded?(:xref)
      assert {:error, {:unavailable, :xref}} = Declared.build(server: "s", modules: [Enum])
    after
      true = Code.append_path(ebin)
      true = Code.ensure_loaded?(:xref)
    end
  end
end
