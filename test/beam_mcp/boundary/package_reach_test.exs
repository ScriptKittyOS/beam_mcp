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
  # module known only at runtime -- the host's catalog, held to three callees elsewhere.
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

  # The nine atoms that name a loadable module and occur in the compiled forms other than as
  # a call target: `-file`/`-compile` attributes and the compiler's own (`:file`, `:compile`,
  # `:elixir`), export lists (`:init`), the tracer's option names (`:trace`), a handler's message
  # tag (`:error_logger`), a tuple tag in the canonical encoder (`:array`), `:json` -- a local
  # function name that OTP 28 turned into a module's name, the collision this census is loud
  # about -- and `Jason.OrderedObject`, the struct the decoder hands back for ordered objects,
  # matched by `BeamMCP.JSON` to read each object's keys once and never called. Exact for the
  # OTP the gate runs; an older OTP without `json` reads one fewer.
  @named_not_called [
    :array,
    :compile,
    :elixir,
    :error_logger,
    :file,
    :init,
    :json,
    :trace,
    Jason.OrderedObject
  ]

  # The functions called on the modules through which code, names, secrets, the operating
  # system, the file system, another process or another node could be reached. Operators on
  # :erlang are not listed; nothing is evaluated, loaded, applied, spawned to a node, read from
  # the environment or the disk, or decoded into atoms through them.
  @functions %{
    :erlang => [
      atom_to_binary: 1,
      binary_to_atom: 1,
      binary_part: 3,
      binary_to_integer: 1,
      byte_size: 1,
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
      min: 2,
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
      tuple_size: 1,
      # A tuple error reason to a JSON array (Server.to_json_value/1); reads nothing.
      tuple_to_list: 1
    ],
    :code => [get_object_code: 1],
    Code => [ensure_compiled: 1, ensure_loaded?: 1],
    # `monotonic_time/1` is the HTTP transport's whole-body deadline clock; a clock, not the environment.
    System => [convert_time_unit: 3, monotonic_time: 1],
    :persistent_term => [erase: 1, get: 2, put: 2],
    Application => [load: 1, spec: 2],
    :application => [get_application: 1],
    :crypto => [hash: 2],
    :ets => [
      info: 2,
      lookup_element: 3,
      new: 2,
      select_replace: 2,
      tab2list: 1,
      update_counter: 4,
      whereis: 1
    ],
    :xref => [add_module: 2, q: 2, set_default: 2, start: 1, stop: 1],
    :io_lib => [char_list: 1],
    :logger => [error: 2],
    :digraph => [
      add_edge: 3,
      add_vertex: 2,
      delete: 1,
      get_short_path: 3,
      in_neighbours: 2,
      new: 1,
      out_neighbours: 2
    ],
    :atomics => [get: 2, new: 2, put: 3],
    :telemetry => [attach_many: 4, detach: 1, execute: 3],
    Jason => [decode: 1, decode: 2, encode!: 1, encode!: 2],
    Logger => [__do_log__: 4, __should_log__: 2],
    Process => [delete: 1, info: 2, put: 2, whereis: 1],
    GenServer => [format_report: 1, start: 3, start_link: 3, stop: 3],
    Supervisor => [child_spec: 2],
    # `get_http_protocol/1`: the transport's body read asks the adapter for one frame at a time
    # over HTTP/2 and puts `connection: close` on HTTP/1 responses only.
    Plug.Conn => [
      get_http_protocol: 1,
      get_req_header: 2,
      put_resp_content_type: 2,
      put_resp_header: 3,
      read_body: 2,
      send_resp: 3
    ],
    Plug.Exception => [status: 1],
    IO => [binread: 2, binwrite: 2]
  }

  # The one atom the package makes from a binary: the argument keys a tool declared in its
  # schema, in the one function that reads them.
  @atom_from_binary {{BeamMCP.Server, :declared_atoms, 1}, {:erlang, :binary_to_atom, 1}}

  setup_all do
    lib = Boundary.lib_modules()
    {edges, _unresolved} = Boundary.xref()
    %{lib: lib, edges: Enum.map(edges, &same_call/1)}
  end

  # One call, two spellings by compiler: `String.to_atom/1` is inlined to
  # `:erlang.binary_to_atom(b, :utf8)` by Elixir up to 1.17 and to `:erlang.binary_to_atom(b)`
  # by 1.18+ (measured on the CI floor leg, OTP 27 / Elixir 1.17). The census is about what the
  # package can reach, and both spellings reach exactly the same thing, so the /2 form is read
  # as the /1 form here and the lists below carry one entry.
  defp same_call({from, {:erlang, :binary_to_atom, 2}}), do: {from, {:erlang, :binary_to_atom, 1}}
  defp same_call(edge), do: edge

  # A module a newer compiler calls directly where an older one calls its Elixir wrapper: on
  # Elixir 1.20 the package's `Regex` calls (match?/2, scan/2, replace/3, escape/1 -- Catalog and
  # the HTTP transport) reach `:re` as a direct callee, where 1.17 and 1.18 reach only `Regex`
  # (measured on the CI head leg, OTP 29 / Elixir 1.20). The same code, the same reach -- `Regex`
  # is `:re` -- so `:re` is tolerated beside `Regex` and required on neither compiler. Nothing
  # else is tolerated: a second module here needs its own measured reason.
  @inlined_by_newer_compilers [re: Regex]

  test "the modules the package calls are exactly the listed ones", %{lib: lib, edges: edges} do
    called = for {_, {m, _, _}} <- edges, m not in lib, uniq: true, do: m

    for {inlined, wrapper} <- @inlined_by_newer_compilers, inlined in called do
      assert wrapper in called, "#{inspect(inlined)} called without #{inspect(wrapper)}"
    end

    called = called -- Keyword.keys(@inlined_by_newer_compilers)

    assert Enum.sort(called) == Enum.sort(@modules),
           "not on the list: #{inspect(Enum.sort(called -- @modules))}; on the list, not called: #{inspect(Enum.sort(@modules -- called))}"
  end

  test "on the modules that could reach code, names, secrets, the OS or another node, the functions called are exactly the listed ones",
       %{edges: edges} do
    diffs =
      for {module, listed} <- @functions,
          called =
            for({_, {^module, f, a}} <- edges, operator?(f) == false, uniq: true, do: {f, a}),
          Enum.sort(called) != Enum.sort(listed),
          do:
            "#{inspect(module)}: not on the list: #{inspect(Enum.sort(called -- listed))}; listed, not called: #{inspect(Enum.sort(listed -- called))}"

    assert diffs == [], Enum.join(diffs, "\n")
  end

  test "every atom in the compiled forms that names a module is a called module or one of the nine named as data",
       %{lib: lib, edges: edges} do
    called = for {_, {m, _, _}} <- edges, m not in lib, uniq: true, do: m
    named = Boundary.module_atoms()
    strays = named -- (called ++ @named_not_called)
    unused = @named_not_called -- named

    assert strays == [] and unused == [],
           "modules named but neither called nor on the data list: #{inspect(Enum.sort(strays))}; listed as data, not named: #{inspect(unused)}"
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
