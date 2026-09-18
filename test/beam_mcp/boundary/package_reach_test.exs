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
    :beam_lib,
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
    :telemetry,
    :trace,
    :unicode,
    :xref
  ]

  # The eight atoms that name a loadable module and occur in the compiled forms other than as
  # a call target: `-file`/`-compile` attributes and the compiler's own (`:file`, `:compile`,
  # `:elixir`), export lists (`:init`), a handler's message
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
    Jason.OrderedObject
  ]

  # The same collision, one OTP later: `:graph` -- a key in this package's maps (`%{graph: g}`,
  # Surface.call/2) -- is the name of a stdlib module from OTP 29 (`lib/stdlib/src/graph.erl`,
  # beside `digraph`; measured on the CI head leg, OTP 29 / Elixir 1.20). On OTP 27 and 28 it
  # names nothing and the census does not see it. So: named as data where the OTP makes it a
  # module's name, and not required where it does not. Nothing else is tolerated this way;
  # the next OTP's collision is added here by name, with its module cited.
  @named_on_newer_otp [:graph]

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
      tuple_size: 1,
      # A tuple error reason to a JSON array (Server.to_json_value/1); reads nothing.
      tuple_to_list: 1
    ],
    :code => [get_object_code: 1],
    # The declared builder reads a beam's `Dbgi` chunk by path (`Declared.add_module/2`) to
    # classify a stripped beam itself, before xref: the same file `get_object_code/1` named.
    :beam_lib => [chunks: 2],
    Code => [ensure_compiled: 1, ensure_loaded?: 1],
    # `monotonic_time/1` is the HTTP transport's whole-body deadline clock; a clock, not the environment.
    System => [convert_time_unit: 3, monotonic_time: 1],
    # The tracer's one trace session: created with itself as the tracer, its call patterns
    # and process flags set inside it, destroyed in one call. `:trace.info/3` is not called:
    # the tracer never asks what it set, it only sets and destroys.
    :trace => [function: 4, process: 4, session_create: 3, session_destroy: 1],
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
  # (measured on the CI head and floor legs). The same code, the same reach -- `Regex` is `:re`
  # -- so `:re` is REQUIRED on the compiler that inlines it and REFUSED on the ones that do not:
  # a hand-written `:re` call in lib is caught on 1.17 and 1.18, and a compiler that stops
  # inlining is caught on the head. Nothing else is tolerated: a second module here needs its
  # own measured reason.
  @inlined_by_newer_compilers [re: {Regex, ">= 1.20.0"}]

  test "the modules the package calls are exactly the listed ones", %{lib: lib, edges: edges} do
    called = for {_, {m, _, _}} <- edges, m not in lib, uniq: true, do: m

    for {inlined, {wrapper, from}} <- @inlined_by_newer_compilers do
      assert wrapper in called, "#{inspect(wrapper)} is not called at all"

      if Version.match?(System.version(), from),
        do:
          assert(
            inlined in called,
            "Elixir #{System.version()} should reach #{inspect(inlined)} for #{inspect(wrapper)}"
          ),
        else:
          refute(
            inlined in called,
            "#{inspect(inlined)} reached directly on Elixir #{System.version()}, which does not inline #{inspect(wrapper)}"
          )
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
    strays = named -- (called ++ @named_not_called ++ @named_on_newer_otp)
    unused = @named_not_called -- named

    # Each newer-OTP entry is named exactly where this VM loads it as a module: on OTP 29 the
    # census must see `:graph`, on 27 and 28 it must not -- so an entry that leaves the
    # package's maps, or one added without a module behind it, fails on the leg that can tell.
    not_a_module_here =
      Enum.reject(@named_on_newer_otp, &match?({:module, _}, Code.ensure_loaded(&1)))

    assert @named_on_newer_otp -- named == not_a_module_here,
           "newer-OTP names: not seen #{inspect(@named_on_newer_otp -- named)}, not a module on this OTP #{inspect(not_a_module_here)}"

    # And "newer" means newer than the floor: on the floor release (the CI matrix's lowest
    # leg) none of these may be a module, or the atom belongs on `@named_not_called` with
    # its own reason -- a one-VM check cannot tell a newer-OTP collision from an atom that
    # names a module everywhere; the floor leg can.
    if List.to_integer(:erlang.system_info(:otp_release)) == BeamMCP.MixProject.otp_floor() do
      assert not_a_module_here == @named_on_newer_otp,
             "on the floor OTP these are modules already, so they are not newer-OTP names: #{inspect(@named_on_newer_otp -- not_a_module_here)}"
    end

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
