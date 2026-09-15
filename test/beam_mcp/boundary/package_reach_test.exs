# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.PackageReachTest do
  # boundary: the package's reach, read from what it compiled to
  # Every census over the text sees an act by its written name. This one reads the artefact:
  # `:xref` over the beams compiled from lib/, BIFs included, lists every module and function
  # the package calls. The lists below are the package's reach, pinned exactly. A new library, an
  # evaluator, a socket, a shell, a spawn to another node, a key store, an environment read --
  # whatever it is spelled -- is a call to a module or function not on the list, and fails here
  # until it is named. That is the boundary the other censuses can only approximate.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  # The modules called from lib/ that are not themselves compiled from lib/. `:"$M_EXPR"` is a
  # module known only at runtime -- the host's catalog, held to one callee elsewhere.
  @modules [
    :"$M_EXPR",
    Access,
    Application,
    ArgumentError,
    Base,
    Code,
    Enum,
    Exception,
    GenServer,
    IO,
    Integer,
    Jason,
    Kernel,
    Kernel.Utils,
    Keyword,
    List,
    Logger,
    Map,
    MapSet,
    Plug.Conn,
    Plug.Exception,
    Process,
    Range,
    Regex,
    RuntimeError,
    Stream,
    String,
    String.Chars,
    Supervisor,
    System,
    :application,
    :atomics,
    :code,
    :crypto,
    :digraph,
    :elixir_erl_pass,
    :erlang,
    :ets,
    :io_lib,
    :lists,
    :logger,
    :maps,
    :persistent_term,
    :telemetry,
    :unicode,
    :xref
  ]

  # The functions called on the modules through which code, names, secrets, the operating
  # system or another node could be reached. Operators on :erlang are not listed; nothing is
  # evaluated, loaded, applied, spawned to a node or read from the environment through them.
  @functions %{
    :erlang => [
      atom_to_binary: 1,
      binary_to_atom: 1,
      binary_to_integer: 1,
      demonitor: 2,
      element: 2,
      error: 1,
      error: 3,
      float_to_binary: 2,
      function_exported: 3,
      get_module_info: 2,
      hd: 1,
      integer_to_binary: 1,
      integer_to_binary: 2,
      iolist_to_binary: 1,
      is_map_key: 2,
      length: 1,
      make_ref: 0,
      map_get: 2,
      map_size: 1,
      max: 2,
      monitor: 2,
      monotonic_time: 0,
      not: 1,
      phash2: 2,
      process_flag: 2,
      process_info: 2,
      raise: 3,
      rem: 2,
      self: 0,
      send: 2,
      spawn: 1,
      system_time: 0,
      trace: 3,
      trace_info: 2,
      trace_pattern: 3,
      tuple_size: 1
    ],
    :code => [get_object_code: 1],
    Code => [ensure_compiled: 1, ensure_loaded?: 1],
    System => [convert_time_unit: 3],
    :persistent_term => [erase: 1, get: 2, put: 2],
    Application => [load: 1, spec: 2],
    :application => [get_application: 1],
    :crypto => [hash: 2]
  }

  # The one atom the package makes from a binary: the argument keys a tool declared in its
  # schema, in the one function that reads them.
  @atom_from_binary {{BeamMCP.Server, :declared_atoms, 1}, {:erlang, :binary_to_atom, 1}}

  setup_all do
    lib = Boundary.lib_modules()
    {edges, _unresolved} = Boundary.xref()
    %{lib: lib, edges: edges}
  end

  test "the modules the package calls are exactly the listed ones", %{lib: lib, edges: edges} do
    called = for {_, {m, _, _}} <- edges, m not in lib, uniq: true, do: m

    assert Enum.sort(called) == Enum.sort(@modules),
           "not on the list: #{inspect(Enum.sort(called -- @modules))}; on the list, not called: #{inspect(Enum.sort(@modules -- called))}"
  end

  test "on the modules that could reach code, names, secrets, the OS or another node, the functions called are exactly the listed ones",
       %{edges: edges} do
    for {module, listed} <- @functions do
      called = for {_, {^module, f, a}} <- edges, operator?(f) == false, uniq: true, do: {f, a}

      assert Enum.sort(called) == Enum.sort(listed),
             "#{inspect(module)}: not on the list: #{inspect(Enum.sort(called -- listed))}; listed, not called: #{inspect(Enum.sort(listed -- called))}"
    end
  end

  test "the one atom made from a binary is made in Server.declared_atoms/1", %{edges: edges} do
    makers =
      for {_, {:erlang, f, _}} = e <- edges,
          f in [:binary_to_atom, :list_to_atom, :binary_to_existing_atom, :list_to_existing_atom],
          do: e

    assert makers == [@atom_from_binary],
           "atoms made from binaries:\n  " <> Enum.map_join(makers, "\n  ", &inspect/1)
  end

  defp operator?(f), do: not Regex.match?(~r/^[a-z_]/, Atom.to_string(f))
end
