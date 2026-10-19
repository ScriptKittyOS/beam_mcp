# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Transport.AdapterBoundaryTest do
  # Every call this package makes into the HTTP adapter goes through `adapter/1`.
  #
  # An exception raised inside a call into the adapter is the adapter's, and goes back to it as
  # itself (`BeamMCP.Transport.HTTP`, the comment above `call/2`). That holds only if every such
  # call is inside the boundary function: one call outside it and that call's exceptions are
  # answered as faults of ours again, which is the defect Bandit 1.13 exposed.
  #
  # READ FROM THE COMPILED CODE, NOT THE SOURCE TEXT. A first version read the source, and two
  # review lanes planted calls it could not see: Plug's default arguments (`read_body(conn)`,
  # a bodiless `send_file/5` head), captures, an alias, an `Elixir.`-prefixed module, `apply/3`,
  # a module calling Plug by name without importing it, a closure built inside `adapter/1` and
  # run outside it. In the abstract code every one of those is the same thing -- a remote call
  # to `Plug.Conn`, a fun reference to it, or `erlang:apply/3` naming it -- so the census reads
  # that, and a new spelling of the same call is not a new case.
  #
  # THE POPULATION IS DERIVED FROM THE AUTHORITY, NOT LISTED: `Plug.Conn.Adapter`'s callbacks,
  # and the functions in Plug.Conn's own compiled forms that call one of them through the
  # conn's adapter module, closed over the functions that call those. Every arity a default
  # argument generates is its own function there, so defaults need no reading.
  #
  # Out of reach of this census, and held elsewhere: a call through a variable module (the
  # adapter module taken out of `conn.adapter`, a module computed at runtime). Every such call
  # under lib/ is pinned by name in `test/beam_mcp/boundary/no_catalog_test.exs`, so a new one
  # fails there.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary
  alias Plug.Conn.Adapter

  @tag_atom :adapter_raised

  defp forms_of(beam) do
    {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
      :beam_lib.chunks(beam, [:abstract_code])

    forms
  end

  # The beam on disk in the build's ebin, not `:code.which/1` (which answers `cover_compiled`
  # under `mix test --cover`).
  defp lib_beam(m),
    do: Mix.Project.compile_path() |> Path.join("#{m}.beam") |> String.to_charlist()

  @doc false
  def adapter_reaching_functions do
    callbacks = Adapter.behaviour_info(:callbacks) |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    defs =
      for {:function, _, name, arity, clauses} <- forms_of(:code.which(Plug.Conn)),
          into: %{},
          do: {{name, arity}, clauses}

    direct =
      for {key, clauses} <- defs, calls_adapter?(clauses, callbacks), into: MapSet.new(), do: key

    reach =
      Stream.iterate(direct, &widen(&1, defs))
      |> Enum.reduce_while(nil, fn r, prev -> if r == prev, do: {:halt, r}, else: {:cont, r} end)

    MapSet.intersection(reach, MapSet.new(Plug.Conn.__info__(:functions)))
  end

  # A remote call through a variable module whose function is an adapter callback: Plug's own
  # `adapter.send_resp(payload, ...)` with `{adapter, payload} = conn.adapter`.
  defp calls_adapter?(clauses, callbacks) do
    any_node?(clauses, fn
      {:call, _, {:remote, _, {:var, _, _}, {:atom, _, cb}}, _} -> MapSet.member?(callbacks, cb)
      _ -> false
    end)
  end

  defp widen(reach, defs) do
    for {key, clauses} <- defs, calls_known?(clauses, reach), into: reach, do: key
  end

  defp calls_known?(clauses, reach) do
    any_node?(clauses, fn
      {:call, _, {:atom, _, name}, args} -> MapSet.member?(reach, {name, length(args)})
      {:fun, _, {:function, name, arity}} -> MapSet.member?(reach, {name, arity})
      _ -> false
    end)
  end

  defp any_node?(term, pred) do
    pred.(term) or
      case term do
        t when is_tuple(t) -> t |> Tuple.to_list() |> any_node?(pred)
        l when is_list(l) -> Enum.any?(l, &any_node?(&1, pred))
        _ -> false
      end
  end

  # Every reach of the population in a module's forms, as `{name, arity, line, inside?}`.
  # Inside means: in the body of the fun passed directly to a local `adapter/1`. A fun nested
  # deeper is a closure that runs wherever it is applied, so its body is outside again.
  @doc false
  def adapter_calls(forms, pop), do: walk(forms, false, pop, [])

  defp walk({:call, _, {:atom, _, :adapter}, [{:fun, _, {:clauses, clauses}}]}, _in, pop, acc),
    do: walk(clauses, true, pop, acc)

  defp walk(
         {:call, loc, {:remote, _, {:atom, _, Plug.Conn}, {:atom, _, f}}, args},
         inside,
         pop,
         acc
       ) do
    acc = if {f, length(args)} in pop, do: [{f, length(args), line(loc), inside} | acc], else: acc
    walk(args, inside, pop, acc)
  end

  defp walk(
         {:call, loc, {:remote, _, {:atom, _, :erlang}, {:atom, _, :apply}},
          [{:atom, _, Plug.Conn}, {:atom, _, f} | _] = args},
         inside,
         pop,
         acc
       ) do
    acc =
      if Enum.any?(pop, &(elem(&1, 0) == f)),
        do: [{f, :apply, line(loc), false} | acc],
        else: acc

    walk(args, inside, pop, acc)
  end

  defp walk(
         {:fun, loc, {:function, {:atom, _, Plug.Conn}, {:atom, _, f}, {:integer, _, a}}},
         _in,
         pop,
         acc
       ),
       do: if({f, a} in pop, do: [{f, a, line(loc), false} | acc], else: acc)

  defp walk({:fun, _, {:clauses, clauses}}, _inside, pop, acc), do: walk(clauses, false, pop, acc)
  defp walk({:named_fun, _, _, clauses}, _inside, pop, acc), do: walk(clauses, false, pop, acc)
  defp walk(t, inside, pop, acc) when is_tuple(t), do: walk(Tuple.to_list(t), inside, pop, acc)

  defp walk(l, inside, pop, acc) when is_list(l),
    do: Enum.reduce(l, acc, &walk(&1, inside, pop, &2))

  defp walk(_leaf, _inside, _pop, acc), do: acc

  defp line({l, _}), do: l
  defp line(l), do: l

  # The boundary function itself: `adapter/1` must catch what it runs and THROW it tagged with
  # its module. A look-alike `defp adapter(f), do: f.()` would satisfy the placement census and
  # hand nothing back, so the definition is held to its shape.
  @doc false
  def boundary_defined?(forms, module) do
    Enum.any?(forms, fn
      {:function, _, :adapter, 1, clauses} ->
        any_node?(clauses, fn
          {:try, _, _body, _else, catches, _after} ->
            Enum.any?(catches, &throws_tag?(&1, module))

          _ ->
            false
        end)

      _ ->
        false
    end)
  end

  defp throws_tag?(clause, module) do
    any_node?(clause, fn
      {:call, _, {:remote, _, {:atom, _, :erlang}, {:atom, _, :throw}},
       [{:tuple, _, [{:tuple, _, [{:atom, _, ^module}, {:atom, _, @tag_atom}]} | _]}]} ->
        true

      _ ->
        false
    end)
  end

  test "the population is derived from Plug's compiled forms and holds the calls this package makes" do
    pop = adapter_reaching_functions()

    # Not the census's list: a check that the derivation reads Plug the way it says it does,
    # defaults and bodiless heads included (both found missing by review lanes in the
    # source-reading version).
    for f <- [
          {:read_body, 1},
          {:read_body, 2},
          {:send_file, 3},
          {:send_file, 4},
          {:send_file, 5},
          {:inform, 2},
          {:push, 2},
          {:send_resp, 1},
          {:send_resp, 3},
          {:get_http_protocol, 1},
          {:send_chunked, 2}
        ],
        do: assert(f in pop, "#{inspect(f)} not derived from Plug.Conn's compiled forms")

    refute {:put_resp_header, 3} in pop, "a pure conn function was taken for an adapter call"
  end

  test "every call into the adapter under lib/ sits inside adapter/1, and adapter/1 is the boundary" do
    pop = adapter_reaching_functions()

    {outside, callers} =
      Enum.reduce(Boundary.lib_modules(), {[], []}, fn m, {out, callers} ->
        calls = m |> lib_beam() |> forms_of() |> adapter_calls(pop)
        bad = for {f, a, line, false} <- calls, do: "#{inspect(m)} line #{line} #{f}/#{a}"
        {out ++ bad, if(calls == [], do: callers, else: [m | callers])}
      end)

    assert outside == [],
           "calls into the adapter outside adapter/1:\n  " <> Enum.join(outside, "\n  ")

    assert callers != [], "no module under lib/ calls into the adapter: the census reads nothing"

    for m <- callers do
      assert boundary_defined?(forms_of(lib_beam(m)), m),
             "#{inspect(m)}: adapter/1 does not catch and throw the tagged exception"
    end
  end

  test "the census sees every shape of a call into the adapter that review lanes planted" do
    pop = adapter_reaching_functions()

    planted =
      Module.concat([BeamMCP, PlantedAdapterCalls, "M#{System.unique_integer([:positive])}"])

    source = """
    defmodule #{inspect(planted)} do
      import Plug.Conn
      alias Plug.Conn, as: C

      def defaults(conn), do: read_body(conn)
      def bodiless_head(conn), do: send_file(conn, 200, "f")
      def aliased(conn), do: C.inform(conn, 103, [])
      def by_name(conn), do: Plug.Conn.send_resp(conn, 200, "")
      def prefixed(conn), do: :"Elixir.Plug.Conn".send_resp(conn, 200, "")
      def captured(conns), do: Enum.map(conns, &get_http_protocol/1)
      def remote_capture, do: &Plug.Conn.send_resp/3
      def applied(conn), do: apply(Plug.Conn, :send_resp, [conn, 200, ""])
      def piped(conn), do: conn |> send_resp(200, "")
      def deferred(conn), do: adapter(fn -> fn -> send_resp(conn, 200, "") end end)
      def wrapped(conn), do: adapter(fn -> send_resp(conn, 200, "") end)
      defp adapter(fun), do: fun.()
    end
    """

    # The planted module needs its abstract code, which `Code.compile_string/1` keeps only with
    # `debug_info` on; the option is restored at once.
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    [{^planted, beam}] = Code.compile_string(source)
    Code.put_compiler_option(:debug_info, previous)

    try do
      calls = beam |> forms_of() |> adapter_calls(pop)
      outside = for {f, a, _l, false} <- calls, do: {f, a}
      inside = for {f, a, _l, true} <- calls, do: {f, a}

      assert Enum.sort(outside) ==
               Enum.sort([
                 {:read_body, 1},
                 {:send_file, 3},
                 {:inform, 3},
                 {:send_resp, 3},
                 {:send_resp, 3},
                 {:get_http_protocol, 1},
                 {:send_resp, 3},
                 {:send_resp, :apply},
                 {:send_resp, 3},
                 {:send_resp, 3}
               ])

      assert inside == [{:send_resp, 3}]
      # The look-alike `adapter/1` above runs its fun and catches nothing: not the boundary.
      refute boundary_defined?(forms_of(beam), planted)
    after
      :code.purge(planted)
      :code.delete(planted)
    end
  end
end
