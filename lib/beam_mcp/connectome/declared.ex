# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Declared do
  @moduledoc """
  The declared connectome: what a composed system says can talk to what, built from what is
  declared and nothing that ran. The vocabulary is in `docs/connectome.md`.

  Three sources, each optional but the scope:

  * **the catalog** -- `capabilities/0` of the module given as `catalog:`; one node per tool,
    resource and prompt, a `:invoke` edge from the server to each tool, and a `:invoke` edge
    from a tool to the module the host names for it in `tool_modules:`;
  * **the compiled code** -- call edges read from the beams of the modules in scope with OTP's
    `:xref`. A module whose only use is at a macro's expansion site produces no edge, because
    no call to it survives into the caller's beam; the calls a macro's own body makes at
    expansion time are attributed by xref to its `MACRO-` function and are filed in the bound
    as expansion calls, never as edges. The scope is `modules:`, or every module an `.app` file
    names for each of `apps:` -- never a directory listing. Under `apps:` the `.app` is the
    authority and a stale beam beside the real ones is not a module; under `modules:` the host
    has named the module, and its beam is found on the code path by that name, whatever put it
    there. Naming an application no `.app` describes is refused by name; the application is
    loaded first, a side effect on this node's application controller;
  * **a grouping of modules**, at the `:boundary` level: the host's `boundaries:` map, or, by
    default, each module's OTP application as the application controller knows it at build
    time -- a module whose application is not loaded is enumerated as ungrouped, with its
    calls, and never guessed into a group.

  ## The completeness bound

  What the build could not see is returned beside the graph as `BeamMCP.Connectome.Declared.Bound`,
  every field an enumerated, sorted list and never a count: dynamic-dispatch sites (the calls
  `:xref` cannot resolve, by caller), sites the host vouched for in `dynamic_allowlist:`, callees
  outside the scope, modules with no beam on the code path, modules whose beam carries no debug
  information, catalog entries no reader can name, tools with no implementing module, modules
  that could not be grouped at the `:boundary` level and the calls into or out of them. Nothing
  the compiled code shows is dropped silently; what it cannot show is stated below.

  ## What the compiled code cannot show, stated

  A module handed as *data* to a dispatcher outside the scope -- a behaviour callback module
  given to `GenServer.start_link/2`, a module in `Task.async/3`, a struct module in
  `struct/2` -- is called from inside that library, not from the scope, so the call is neither
  an edge nor an entry in the bound: the bound enumerates dynamic dispatch *from* the scope,
  not dispatch *into* it from library code. Calls to what `:erlang.is_builtin/3` calls a
  built-in -- C-implemented functions in `erlang`, and also in `lists`, `ets`, `maps`, `re`,
  `math`, `os`, `binary` among others -- are not reported either (xref's default, which this
  builder never changes): every module makes them, and the dependency is on the runtime itself,
  not on a part of the system. The filter is per function, not per module: `lists` appears
  among the external callees when `:lists.reverse/1` is called and not when `:lists.member/2`
  is; `ets` when `:ets.tab2list/1` is called and not when `:ets.lookup/2` is (measured: 25 of
  `ets`'s exports are Erlang-implemented). Two more, at the edges of the `MACRO-` rule: a
  compile-time hook written as a plain function (`__before_compile__/1`, `__after_compile__/2`)
  is attributed to that function and so reads as a runtime call; and a private macro leaves no
  `MACRO-` function and no call, so a helper used only from its body produces neither an edge
  nor an expansion call.

  ## What this module does not do

  It observes nothing (that is the observed connectome), reads no resource, and writes no sign:
  every edge is `provenance: :declared`, `sign: :unknown`, `weight: nil`. Boundary declarations
  read by reflection (`boundaries: :reflect`) are refused by name until the mechanism has been
  measured.
  """

  alias BeamMCP.Connectome.{Edge, Graph, Node}

  defmodule Bound do
    @moduledoc "What a declared build could not see, enumerated. Every field is a sorted list."
    defstruct unresolved_calls: [],
              allowlisted_calls: [],
              macro_expansion_calls: [],
              external_callees: [],
              modules_without_beam: [],
              modules_without_debug_info: [],
              unreadable_catalog_entries: [],
              tools_without_module: [],
              ungrouped_modules: [],
              ungrouped_calls: [],
              sources_used: []

    @type mfa_t :: {module(), atom(), arity()}
    @type t :: %__MODULE__{
            unresolved_calls: [{mfa_t(), {atom(), atom(), arity()}}],
            allowlisted_calls: [{mfa_t(), {atom(), atom(), arity()}}],
            macro_expansion_calls: [{mfa_t(), mfa_t()}],
            external_callees: [module()],
            modules_without_beam: [module()],
            modules_without_debug_info: [module()],
            unreadable_catalog_entries: [{:resources | :prompts, term()}],
            tools_without_module: [atom()],
            ungrouped_modules: [module()],
            ungrouped_calls: [{mfa_t(), mfa_t()}],
            sources_used: [:catalog | :xref | :boundary_map | :application]
          }
  end

  defmodule Result do
    @moduledoc "A declared graph and the bound on what its build could not see."
    @enforce_keys [:graph, :bound]
    defstruct [:graph, :bound]
    @type t :: %__MODULE__{graph: Graph.t(), bound: Bound.t()}
  end

  @keys [
    :server,
    :catalog,
    :modules,
    :apps,
    :level,
    :boundaries,
    :tool_modules,
    :dynamic_allowlist
  ]
  @levels [:module, :mfa, :boundary]

  @doc """
  Builds the declared connectome. Options: `server:` (the host's server identity, a string,
  required); `modules:` or `apps:` (the scope, one required); `catalog:` (a module, optional);
  `level:` (`:module` by default, `:mfa`, or `:boundary`); `boundaries:` (a map from module to
  `{:application, app}` or `{:boundary_module, root}`; absent means group by OTP application);
  `tool_modules:` (a map from tool name to its implementing module); `dynamic_allowlist:` (a
  list of caller `{module, function, arity}` the host vouches for).

  Returns `{:ok, %Result{}}`, or `{:error, reason}` by name.

  Two side effects, stated: each application in `apps:` is loaded (never started) before its
  `.app` is read, and the loads preceding a refusal persist; and `capabilities/0` is called
  twice on the catalog -- once by the package's contract check, once to read it.
  """
  @spec build(keyword()) :: {:ok, Result.t()} | {:error, term()}
  def build(opts) do
    with :ok <- keyword(opts),
         :ok <- reject_unknown(opts),
         {:ok, server} <- server(opts),
         {:ok, level} <- level(opts),
         {:ok, boundaries} <- boundaries(opts),
         {:ok, modules} <- scope(opts),
         {:ok, catalog} <- catalog(opts, server),
         {:ok, code} <- code(modules, server, level, boundaries, opts) do
      tool_modules = Keyword.get(opts, :tool_modules, %{})

      {tool_edges, tools_without_module} = tool_edges(catalog, tool_modules, code, server)

      nodes = [
        Node.new!(kind: :server, level: :server, identity: {:server, server})
        | catalog.nodes ++ code.nodes
      ]

      edges = catalog.edges ++ tool_edges ++ code.edges

      bound = %Bound{
        unresolved_calls: code.unresolved,
        allowlisted_calls: code.allowlisted,
        macro_expansion_calls: code.macro,
        external_callees: code.external,
        modules_without_beam: code.no_beam,
        modules_without_debug_info: code.no_debug_info,
        unreadable_catalog_entries: catalog.unreadable,
        tools_without_module: tools_without_module,
        ungrouped_modules: code.ungrouped,
        ungrouped_calls: code.ungrouped_calls,
        sources_used: Enum.sort(catalog.sources ++ code.sources)
      }

      case Graph.new(nodes: nodes, edges: edges, schema_version: Graph.schema_version()) do
        {:ok, graph} -> {:ok, %Result{graph: graph, bound: bound}}
        {:error, reason} -> {:error, {:graph, reason}}
      end
    end
  end

  # ---------------------------------------------------------------------------------------
  # options

  defp keyword(opts),
    do: if(Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid, :opts, opts}})

  defp reject_unknown(opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @keys)) do
      nil -> :ok
      key -> {:error, {:unknown_key, key}}
    end
  end

  defp server(opts) do
    case Keyword.fetch(opts, :server) do
      {:ok, s} when is_binary(s) -> {:ok, s}
      {:ok, other} -> {:error, {:invalid, :server, other}}
      :error -> {:error, {:missing, :server}}
    end
  end

  defp level(opts) do
    case Keyword.get(opts, :level, :module) do
      l when l in @levels -> {:ok, l}
      other -> {:error, {:invalid, :level, other}}
    end
  end

  defp boundaries(opts) do
    case Keyword.get(opts, :boundaries) do
      nil -> {:ok, :application}
      :reflect -> {:error, {:unsupported, :boundaries, :reflect}}
      map when is_map(map) -> {:ok, map}
      other -> {:error, {:invalid, :boundaries, other}}
    end
  end

  # The scope is a list of modules, or every module an .app file names. Never a directory
  # listing: a beam on disk that no .app names is not a module of the system.
  defp scope(opts) do
    case {Keyword.get(opts, :modules), Keyword.get(opts, :apps)} do
      {mods, nil} when is_list(mods) ->
        atoms(mods, :modules, fn m -> {:ok, Enum.sort(Enum.uniq(m))} end)

      {nil, apps} when is_list(apps) ->
        atoms(apps, :apps, &app_modules/1)

      {nil, nil} ->
        {:error, {:missing, :modules}}

      {mods, nil} ->
        {:error, {:invalid, :modules, mods}}

      {nil, apps} ->
        {:error, {:invalid, :apps, apps}}

      {_, _} ->
        {:error, {:invalid, :modules, :both_modules_and_apps}}
    end
  end

  defp atoms(list, key, then) do
    if Enum.all?(list, &is_atom/1), do: then.(list), else: {:error, {:invalid, key, list}}
  end

  # An application is loaded so its .app can be read -- a side effect on this node's
  # application controller, stated. One no .app file describes is refused by name: the .app is
  # the population rule's authority, and an app without one has no population to derive.
  defp app_modules(apps) do
    Enum.reduce_while(apps, {:ok, []}, fn app, {:ok, acc} ->
      case Application.load(app) do
        r when r == :ok or r == {:error, {:already_loaded, app}} ->
          {:cont, {:ok, acc ++ (Application.spec(app, :modules) || [])}}

        {:error, _} ->
          {:halt, {:error, {:unknown_app, app}}}
      end
    end)
    |> case do
      {:ok, mods} -> {:ok, mods |> Enum.uniq() |> Enum.sort()}
      error -> error
    end
  end

  # ---------------------------------------------------------------------------------------
  # the catalog

  defp catalog(opts, server) do
    case Keyword.get(opts, :catalog) do
      nil ->
        {:ok, %{nodes: [], edges: [], unreadable: [], tools: [], sources: []}}

      module when is_atom(module) ->
        # The package's one contract check runs first, so a catalog it refuses is refused
        # here by the same reason and is never read: a `tools` entry that is not a ToolSpec
        # was once skipped silently by the comprehension in read_catalog/2.
        case BeamMCP.Catalog.validate(module) do
          :ok -> read_catalog(module, server)
          {:error, reason} -> {:error, {:invalid, :catalog, reason}}
        end

      other ->
        {:error, {:invalid, :catalog, other}}
    end
  end

  defp read_catalog(module, server) do
    caps = module.capabilities()
    tools = Map.get(caps, :tools, [])
    server_id = Node.id({:server, server})

    tool_nodes =
      for %BeamMCP.ToolSpec{} = t <- tools do
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, server, t.name},
          labels: %{command_class: t.command_class, mode: t.mode}
        )
      end

    tool_edges =
      for n <- tool_nodes,
          do: Edge.new!(from: server_id, to: n.id, kind: :invoke, provenance: :declared)

    {resource_nodes, bad_resources} =
      named(Map.get(caps, :resources, []), :resources, [:uri, "uri"], server, :resource)

    {prompt_nodes, bad_prompts} =
      named(Map.get(caps, :prompts, []), :prompts, [:name, "name"], server, :prompt)

    {:ok,
     %{
       nodes: tool_nodes ++ resource_nodes ++ prompt_nodes,
       edges: tool_edges,
       unreadable: Enum.sort(bad_resources ++ bad_prompts),
       tools: Enum.map(tools, & &1.name),
       sources: [:catalog]
     }}
  end

  # A resource or prompt entry is readable when it carries a name under one of the keys a
  # reader can look for. Anything else is enumerated as unreadable, never dropped.
  defp named(entries, field, keys, server, kind) do
    Enum.reduce(entries, {[], []}, fn entry, {nodes, bad} ->
      # The map test comes first and on its own: `is_map(e) and find(...)` short-circuits to
      # `false`, and `false` is an atom -- the first version named a node "false" for an
      # entry that was not a map at all. Measured on the fixture's `:opaque` entry.
      name = if is_map(entry), do: Enum.find_value(keys, &Map.get(entry, &1)), else: nil

      if is_binary(name) or (is_atom(name) and name not in [nil, true, false]) do
        {[Node.new!(kind: kind, level: :server, identity: {kind, server, name}) | nodes], bad}
      else
        {nodes, [{field, entry} | bad]}
      end
    end)
  end

  # A tool's implementing module is the host's to name; the catalog does not say. Named and in
  # scope, it is an edge; unnamed or out of scope, the tool is enumerated in the bound.
  defp tool_edges(catalog, tool_modules, code, server) do
    {edges, without} =
      Enum.reduce(catalog.tools, {[], []}, fn tool, {edges, without} ->
        with module when not is_nil(module) <- Map.get(tool_modules, tool),
             to when not is_nil(to) <- code.module_ids[module] do
          edge =
            Edge.new!(
              from: Node.id({:tool, server, tool}),
              to: to,
              kind: :invoke,
              provenance: :declared
            )

          {[edge | edges], without}
        else
          _ -> {edges, [tool | without]}
        end
      end)

    {edges, Enum.sort(without)}
  end

  # ---------------------------------------------------------------------------------------
  # the compiled code, through OTP's xref

  defp code(modules, server, level, boundaries, opts) do
    if Code.ensure_loaded?(:xref),
      do: xref_code(modules, server, level, boundaries, opts),
      else: {:error, {:unavailable, :xref}}
  end

  defp xref_code(modules, server, level, boundaries, opts) do
    allowlist = Keyword.get(opts, :dynamic_allowlist, [])
    {:ok, ref} = :xref.start([])
    :xref.set_default(ref, warnings: false, verbose: false)

    try do
      {added, no_beam, no_debug_info} = add_modules(ref, modules)
      {:ok, calls} = :xref.q(ref, ~c"E")
      {:ok, unresolved} = :xref.q(ref, ~c"UC")

      in_scope = MapSet.new(added)
      {resolved, external, macro} = split_calls(calls, in_scope)

      {allowlisted, unresolved} =
        Enum.split_with(unresolved, fn {caller, _} ->
          caller in allowlist
        end)

      {nodes, edges, module_ids, ungrouped, ungrouped_calls, sources} =
        at_level(level, added, resolved, server, boundaries)

      {:ok,
       %{
         nodes: nodes,
         edges: edges,
         module_ids: module_ids,
         unresolved: Enum.sort(unresolved),
         allowlisted: Enum.sort(allowlisted),
         external: external,
         macro: macro,
         no_beam: Enum.sort(no_beam),
         no_debug_info: Enum.sort(no_debug_info),
         ungrouped: Enum.sort(ungrouped),
         ungrouped_calls: ungrouped_calls,
         sources: [:xref | sources]
       }}
    after
      :xref.stop(ref)
    end
  end

  # Each module's beam is found on the code path by name -- `:code.get_object_code/1` -- so a
  # cover-compiled or unloaded module is read the same way, and a stray beam nobody named is
  # never read at all.
  defp add_modules(ref, modules) do
    Enum.reduce(modules, {[], [], []}, fn m, {added, no_beam, no_dbg} ->
      case add_module(ref, m) do
        :added -> {[m | added], no_beam, no_dbg}
        :no_beam -> {added, [m | no_beam], no_dbg}
        :no_debug_info -> {added, no_beam, [m | no_dbg]}
      end
    end)
    |> then(fn {a, b, c} -> {Enum.sort(a), b, c} end)
  end

  defp add_module(ref, m) do
    with {^m, _binary, file} <- :code.get_object_code(m),
         {:ok, _} <- :xref.add_module(ref, file) do
      :added
    else
      :error -> :no_beam
      {:error, _, _} -> :no_debug_info
    end
  end

  # An edge is kept when both endpoints are in scope. A callee outside the scope is neither a
  # node nor an edge; it is enumerated by module. Every dynamic dispatch -- a fun call, an
  # `apply/3` inlined by the compiler, an `apply/3` with a variable argument list -- arrives
  # from xref as a `$M_EXPR` call and is reported by `UC`; measured on the fixture's three
  # shapes, none arrives as a resolved call to `:erlang.apply/3`, so none is looked for here.
  defp split_calls(calls, in_scope) do
    calls
    |> Enum.reduce({[], MapSet.new(), []}, fn {{fm, ff, _} = from, {tm, _, _} = to},
                                              {kept, ext, macro} ->
      cond do
        tm == :"$M_EXPR" ->
          {kept, ext, macro}

        macro_function?(ff) ->
          # A call a macro body makes runs at expansion time, in the compiler, not in the
          # system. xref attributes it to the `MACRO-name` function. It is neither an edge nor
          # a callee outside the scope; it is enumerated by its macro.
          {kept, ext, [{from, to} | macro]}

        MapSet.member?(in_scope, fm) and MapSet.member?(in_scope, tm) ->
          {[{from, to} | kept], ext, macro}

        true ->
          # Every call xref reports comes from a module that was added, so the caller is in
          # scope by construction; only the callee can be outside it.
          _ = fm
          {kept, MapSet.put(ext, tm), macro}
      end
    end)
    |> then(fn {kept, ext, macro} -> {kept, Enum.sort(MapSet.to_list(ext)), Enum.sort(macro)} end)
  end

  defp macro_function?(f), do: String.starts_with?(Atom.to_string(f), "MACRO-")

  defp at_level(:module, modules, calls, server, _boundaries) do
    ids = Map.new(modules, &{&1, Node.id({:module, server, &1})})

    nodes =
      for m <- modules,
          do: Node.new!(kind: :module, level: :module, identity: {:module, server, m})

    edges =
      calls
      |> Enum.map(fn {{fm, _, _}, {tm, _, _}} -> {ids[fm], ids[tm]} end)
      |> Enum.reject(fn {a, b} -> a == b end)
      |> Enum.uniq()
      |> Enum.map(fn {a, b} ->
        Edge.new!(from: a, to: b, kind: :invoke, provenance: :declared)
      end)

    {nodes, edges, ids, [], [], []}
  end

  defp at_level(:mfa, modules, calls, server, _boundaries) do
    mfas =
      calls
      |> Enum.flat_map(fn {from, to} -> [from, to] end)
      |> Enum.uniq()
      |> Enum.sort()

    nodes =
      for mfa <- mfas, do: Node.new!(kind: :module, level: :mfa, identity: {:module, server, mfa})

    edges =
      calls
      |> Enum.uniq()
      |> Enum.map(fn {from, to} ->
        Edge.new!(
          from: Node.id({:module, server, from}),
          to: Node.id({:module, server, to}),
          kind: :invoke,
          provenance: :declared
        )
      end)

    # At this level a tool's implementing module is not a node; module ids are empty so a
    # tool_modules entry is enumerated as a tool without a module rather than dangling.
    _ = modules
    {nodes, edges, %{}, [], [], []}
  end

  defp at_level(:boundary, modules, calls, server, boundaries) do
    {groups, ungrouped} =
      Enum.reduce(modules, {%{}, []}, fn m, {groups, ungrouped} ->
        case group_of(m, boundaries) do
          nil -> {groups, [m | ungrouped]}
          group -> {Map.put(groups, m, group), ungrouped}
        end
      end)

    source = if is_map(boundaries), do: :boundary_map, else: :application
    ids = Map.new(groups, fn {m, {src, name}} -> {m, Node.id({:boundary, server, src, name})} end)

    nodes =
      groups
      |> Map.values()
      |> Enum.uniq()
      |> Enum.map(fn {src, name} ->
        Node.new!(kind: :module, level: :boundary, identity: {:boundary, server, src, name})
      end)

    # A call with an ungrouped end cannot be an edge at this level -- one end has no node --
    # and the compiled code showed it, so it is enumerated, not dropped.
    {grouped_calls, ungrouped_calls} =
      Enum.split_with(calls, fn {{fm, _, _}, {tm, _, _}} ->
        Map.has_key?(ids, fm) and Map.has_key?(ids, tm)
      end)

    edges =
      grouped_calls
      |> Enum.map(fn {{fm, _, _}, {tm, _, _}} -> {ids[fm], ids[tm]} end)
      |> Enum.reject(fn {a, b} -> a == b end)
      |> Enum.uniq()
      |> Enum.map(fn {a, b} ->
        Edge.new!(from: a, to: b, kind: :invoke, provenance: :declared)
      end)

    {nodes, edges, ids, ungrouped, Enum.sort(ungrouped_calls), [source]}
  end

  defp group_of(m, boundaries) when is_map(boundaries) do
    case Map.get(boundaries, m) do
      {:application, app} when is_atom(app) -> {:application, app}
      {:boundary_module, root} when is_atom(root) -> {:boundary_module, root}
      _ -> nil
    end
  end

  # The grouping the BEAM itself asserts: the OTP application a module belongs to, as the
  # application controller knows it at build time -- which is to say among LOADED applications.
  # Under `apps:` every named application is loaded first; under `modules:` a module whose
  # application is not loaded is indistinguishable from one that belongs to none, and both are
  # enumerated as ungrouped rather than guessed from a beam's path.
  defp group_of(m, :application) do
    case :application.get_application(m) do
      {:ok, app} -> {:application, app}
      :undefined -> nil
    end
  end
end
