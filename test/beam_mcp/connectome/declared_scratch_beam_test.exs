# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.DeclaredScratchBeamTest do
  @moduledoc """
  The two declared-builder tests that compile modules at run time, in their own module so
  the rest of `declared_test.exs` stays `async: true`: the compiles below turn a process-
  global compiler option (`debug_info`) on and back off, which no async neighbour may see
  (a review lane's note, kept as a gap until this island).
  """
  use ExUnit.Case, async: false

  alias BeamMCP.Connectome.{Declared, Node}
  alias BeamMCP.Fixture.Declared, as: Fx

  @server "fx"

  defp ids(nodes), do: nodes |> Enum.map(& &1.id) |> Enum.sort()

  describe "beams the code path holds that no application claims, or that carry no debug information" do
    # Written to a scratch directory and put on the code path, so they are found by name the
    # way any module's beam is -- and belong to no OTP application, because nothing loaded
    # them from one.
    setup do
      dir =
        Path.join(System.tmp_dir!(), "beam_mcp_declared_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)

      # `mix test` runs with the compiler option `debug_info: false`, measured: a module
      # compiled at test time carries `:none`, and xref refuses it as if it were stripped. The
      # option is turned on for these two compiles, so the orphan is a readable beam and the
      # stripped one is stripped by `:beam_lib.strip/1` and by nothing else.
      was = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, true)

      [{Orphan, plain}] = Code.compile_string("defmodule Orphan do\n  def go, do: :ok\nend")
      File.write!(Path.join(dir, "Elixir.Orphan.beam"), plain)

      [{Stripped, full}] = Code.compile_string("defmodule Stripped do\n  def go, do: :ok\nend")
      {:ok, {Stripped, stripped}} = :beam_lib.strip(full)
      File.write!(Path.join(dir, "Elixir.Stripped.beam"), stripped)

      Code.put_compiler_option(:debug_info, was)

      {:ok, {Orphan, [debug_info: {:debug_info_v1, :elixir_erl, {:elixir_v1, _, _}}]}} =
        :beam_lib.chunks(plain, [:debug_info])

      true = Code.append_path(dir)

      on_exit(fn ->
        Code.delete_path(dir)
        File.rm_rf!(dir)
      end)

      :ok
    end

    test "a module with no application is enumerated at the :boundary level, never guessed into a group" do
      {:ok, %{graph: g, bound: bound}} =
        Declared.build(server: @server, modules: [Fx.Beta, Orphan], level: :boundary)

      assert bound.ungrouped_modules == [Orphan]
      assert bound.sources_used == [:application, :xref]

      assert ids(g.nodes) ==
               Enum.sort([
                 Node.id({:server, @server}),
                 Node.id({:boundary, @server, :application, :beam_mcp})
               ])
    end

    test "a beam without debug information is enumerated, and is not a node" do
      {:ok, %{graph: g, bound: bound}} =
        Declared.build(server: @server, modules: [Fx.Beta, Stripped])

      assert bound.modules_without_debug_info == [Stripped]
      refute Enum.any?(g.nodes, &(&1.id == Node.id({:module, @server, Stripped})))
    end
  end
end
