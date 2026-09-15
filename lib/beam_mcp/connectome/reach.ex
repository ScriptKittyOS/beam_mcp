# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Reach do
  @moduledoc """
  Control-reachability queries over a connectome graph: can an entry reach an effect, can it
  do so without crossing a gate, and which nodes does every path have to cross.

  The graph is any `BeamMCP.Connectome.Graph` -- the declared one is the point, since it says
  what *can* happen -- and the questions are the ones a gate is placed in a graph to answer:

    * `reachable?/4` -- is there a path from `from` to `to`?
    * `reachable_without/5` -- is there a path from `from` to `to` that crosses none of the
      `gates`? When there is, the answer carries a **witness**: a `BeamMCP.Connectome.Reach.Path`
      whose edges are edges
      of the input graph, in order, so a reader can check it against the graph rather than
      trust this module.
    * `dominates?/4` -- does every path from the entry set to `target` pass `gate`?
    * `mandatory_pass/3` -- the set of nodes every path from the entry set to `target` must
      cross: the dominators of `target`, the target itself excluded.

  The **entry set** is the graph's server nodes unless `entries:` says otherwise; a virtual
  root above the entries makes "from the entry set" one source. A node that is an entry on its
  own is on every path only when it is the sole entry, which is what the definition says.

  ## How, and what it costs

  Every query builds a private `:digraph` from the graph -- O(V + E), deleted when the query
  returns, whatever happens -- with the edges filtered to `kinds:` and the gate nodes left out.
  `reachable?/4` and `reachable_without/5` are one `:digraph.get_short_path/3` -- breadth-first,
  O(V + E) -- so the witness is a *shortest* path among those that cross no gate.
  `dominates?/4` is the definition itself: `target` is reachable from the entries with `gate`
  present and unreachable with it removed -- two searches, O(V + E), the single-query form.
  `mandatory_pass/3` is Lengauer–Tarjan (1979), the simple variant with path compression,
  O(E log V) -- OTP's `:digraph_utils` has no dominator function (measured), so it is written
  here and held to the removal definition by a property that asks `dominates?/4` about every
  node. Every function is polynomial; none enumerates paths.

  ## Caps and refusals, by name

  `max_edges:` (default #{1_000_000}) bounds the graph a query will build a `:digraph` over; a
  larger graph is refused with `{:error, {:cap, :max_edges, n}}` before a table is created.
  `max_hops:` (default `:infinity`) bounds a witness's length: a shortest path longer than it is
  not a witness. `all_paths/4` is **refused by name** -- `{:error, {:refused, :all_paths}}` --
  because the number of paths is exponential in the graph and no cap makes enumerating them a
  question this package should answer; motif isomorphism is not offered for the same reason.
  That is the boundary: what is cheap on the BEAM (searches, dominators) is here; what is not
  is refused rather than attempted with a cap that would be raised until it meant nothing.

  An unknown option, an option of the wrong shape, an edge kind outside the vocabulary and a
  node id the graph does not hold are each refused by name. Signs are not consulted:
  sign-aware reachability beyond "avoid these nodes" waits for a consumer that populates them.
  """

  alias BeamMCP.Connectome.{Edge, Graph}

  defmodule Path do
    @moduledoc """
    A witness path: `nodes` in order from the entry to the target, and `edges` -- one edge of
    the input graph per step, the first in the graph's canonical order among those the query's
    `kinds:` admitted. `length(edges) == length(nodes) - 1`.
    """
    defstruct nodes: [], edges: []
    @type t :: %__MODULE__{nodes: [String.t()], edges: [Edge.t()]}
  end

  @root :"$reach_root"
  @default_max_edges 1_000_000
  @options [:entries, :kinds, :max_hops, :max_edges]

  @typedoc "Why a query was refused; every reason names what was wrong (an `:invalid` names the option)."
  @type refusal ::
          {:unknown_option, atom()}
          | {:invalid, atom(), term()}
          | {:unknown_node, String.t()}
          | {:cap, :max_edges, pos_integer()}
          | {:unreachable, String.t()}
          | {:refused, :all_paths}

  @doc "Is there a path from `from` to `to`, on the admitted edge kinds, within `max_hops:`?"
  @spec reachable?(Graph.t(), String.t(), String.t(), keyword()) ::
          {:ok, boolean()} | {:error, refusal()}
  def reachable?(%Graph{} = graph, from, to, opts \\ []) do
    with {:ok, opts} <- options(graph, opts),
         :ok <- known(graph, [from, to]),
         :ok <- cap(graph, opts) do
      with_digraph(graph, opts, [], fn dg ->
        {:ok, path(dg, from, to, opts) != false}
      end)
    end
  end

  @doc """
  Is there a path from `from` to `to` that crosses none of `gates`? `{:ok, false}` when there
  is none -- or when `from` or `to` is itself a gate; `{:ok, %Path{}}` with the witness when
  there is.
  """
  @spec reachable_without(Graph.t(), String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, false | Path.t()} | {:error, refusal()}
  def reachable_without(%Graph{} = graph, from, to, gates, opts \\ []) when is_list(gates) do
    with {:ok, opts} <- options(graph, opts),
         :ok <- known(graph, [from, to | gates]),
         :ok <- cap(graph, opts) do
      without(graph, from, to, gates, opts)
    end
  end

  defp without(graph, from, to, gates, opts) do
    if from in gates or to in gates,
      do: {:ok, false},
      else: without_gates(graph, from, to, gates, opts)
  end

  defp without_gates(graph, from, to, gates, opts) do
    with_digraph(graph, opts, gates, fn dg ->
      case path(dg, from, to, opts) do
        false -> {:ok, false}
        vertices -> {:ok, witness(graph, vertices, opts)}
      end
    end)
  end

  @doc """
  Does every path from the entry set to `target` pass `gate`? `{:error, {:unreachable, target}}`
  when no path reaches `target` at all -- dominance is undefined there, and saying `true` would
  make an unreachable effect look guarded.
  """
  @spec dominates?(Graph.t(), String.t(), String.t(), keyword()) ::
          {:ok, boolean()} | {:error, refusal()}
  def dominates?(%Graph{} = graph, gate, target, opts \\ []) do
    with {:ok, opts} <- options(graph, opts),
         :ok <- known(graph, [gate, target]),
         :ok <- cap(graph, opts),
         :ok <- reachable_from_entries(graph, target, opts) do
      dominates(graph, gate, target, opts)
    end
  end

  defp dominates(_graph, target, target, _opts), do: {:ok, true}

  defp dominates(graph, gate, target, opts) do
    with_digraph(graph, opts, [gate], fn dg -> {:ok, path(dg, @root, target, opts) == false} end)
  end

  @doc """
  The nodes every path from the entry set to `target` must cross -- the dominators of
  `target`, `target` itself excluded. `{:error, {:unreachable, target}}` when nothing reaches it.
  """
  @spec mandatory_pass(Graph.t(), String.t(), keyword()) ::
          {:ok, MapSet.t(String.t())} | {:error, refusal()}
  def mandatory_pass(%Graph{} = graph, target, opts \\ []) do
    with {:ok, opts} <- options(graph, opts),
         :ok <- known(graph, [target]),
         :ok <- cap(graph, opts),
         :ok <- reachable_from_entries(graph, target, opts) do
      with_digraph(graph, opts, [], fn dg ->
        idom = lengauer_tarjan(dg, @root)
        {:ok, dominators(idom, target)}
      end)
    end
  end

  @doc "Refused by name: enumerating every path is exponential and is not a question this package answers."
  @spec all_paths(Graph.t(), String.t(), String.t(), keyword()) ::
          {:error, {:refused, :all_paths}}
  def all_paths(%Graph{}, _from, _to, _opts \\ []), do: {:error, {:refused, :all_paths}}

  # --- options and refusals ------------------------------------------------------------------

  defp options(graph, opts) do
    with :ok <- keyword(opts),
         :ok <- unknown(opts),
         {:ok, entries} <- entries(graph, opts),
         {:ok, kinds} <- kinds(opts),
         {:ok, max_hops} <- max_hops(opts),
         {:ok, max_edges} <- max_edges(opts) do
      {:ok, %{entries: entries, kinds: kinds, max_hops: max_hops, max_edges: max_edges}}
    end
  end

  defp keyword(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid, :options, opts}}
  end

  defp unknown(opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
      nil -> :ok
      key -> {:error, {:unknown_option, key}}
    end
  end

  defp entries(graph, opts) do
    case Keyword.fetch(opts, :entries) do
      :error ->
        {:ok, for(%{kind: :server, id: id} <- graph.nodes, do: id)}

      {:ok, ids} when is_list(ids) and ids != [] ->
        with :ok <- known(graph, ids), do: {:ok, ids}

      {:ok, other} ->
        {:error, {:invalid, :entries, other}}
    end
  end

  defp kinds(opts) do
    case Keyword.get(opts, :kinds, Edge.kinds()) do
      kinds when is_list(kinds) and kinds != [] ->
        if Enum.all?(kinds, &(&1 in Edge.kinds())),
          do: {:ok, kinds},
          else: {:error, {:invalid, :kinds, kinds}}

      other ->
        {:error, {:invalid, :kinds, other}}
    end
  end

  defp max_hops(opts) do
    case Keyword.get(opts, :max_hops, :infinity) do
      :infinity -> {:ok, :infinity}
      n when is_integer(n) and n > 0 -> {:ok, n}
      other -> {:error, {:invalid, :max_hops, other}}
    end
  end

  defp max_edges(opts) do
    case Keyword.get(opts, :max_edges, @default_max_edges) do
      n when is_integer(n) and n > 0 -> {:ok, n}
      other -> {:error, {:invalid, :max_edges, other}}
    end
  end

  defp known(graph, ids) do
    held = MapSet.new(graph.nodes, & &1.id)

    case Enum.find(ids, &(not (is_binary(&1) and MapSet.member?(held, &1)))) do
      nil -> :ok
      id -> {:error, {:unknown_node, id}}
    end
  end

  defp cap(graph, %{max_edges: max}) do
    if length(graph.edges) > max, do: {:error, {:cap, :max_edges, max}}, else: :ok
  end

  defp reachable_from_entries(graph, target, opts) do
    with_digraph(graph, opts, [], fn dg ->
      if path(dg, @root, target, opts) == false,
        do: {:error, {:unreachable, target}},
        else: :ok
    end)
  end

  # --- the digraph ---------------------------------------------------------------------------

  # A private table per query, deleted on every exit. The virtual root is always present with
  # an edge to each entry; the removed set (gates, or the gate under test) is left out with
  # every edge touching it, which is what "crossing" means.
  defp with_digraph(graph, opts, removed, fun) do
    dg = :digraph.new([:private])

    try do
      removed = MapSet.new(removed)
      kinds = MapSet.new(opts.kinds)

      for %{id: id} <- graph.nodes, not MapSet.member?(removed, id) do
        :digraph.add_vertex(dg, id)
      end

      :digraph.add_vertex(dg, @root)

      for e <- graph.edges,
          MapSet.member?(kinds, e.kind),
          not MapSet.member?(removed, e.from),
          not MapSet.member?(removed, e.to) do
        :digraph.add_edge(dg, e.from, e.to)
      end

      for entry <- opts.entries, not MapSet.member?(removed, entry) do
        :digraph.add_edge(dg, @root, entry)
      end

      fun.(dg)
    after
      :digraph.delete(dg)
    end
  end

  # The vertices of a shortest path from `from` to `to`, or false. A path from a vertex to
  # itself is the empty walk, zero hops -- not a cycle through it.
  defp path(_dg, from, from, _opts), do: [from]

  defp path(dg, from, to, %{max_hops: max_hops}) do
    case :digraph.get_short_path(dg, from, to) do
      false -> false
      vertices when max_hops == :infinity -> vertices
      vertices -> if length(vertices) - 1 <= max_hops, do: vertices, else: false
    end
  end

  # The witness carries input edges: for each step, the first edge in the graph's canonical
  # order between the two vertices whose kind the query admitted. One exists by construction.
  defp witness(graph, vertices, %{kinds: kinds}) do
    edges =
      vertices
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] ->
        Enum.find(graph.edges, &(&1.from == a and &1.to == b and &1.kind in kinds))
      end)

    %Path{nodes: vertices, edges: edges}
  end

  # --- dominators: Lengauer–Tarjan, the simple variant --------------------------------------
  #
  # Lengauer, T. and Tarjan, R. E., "A fast algorithm for finding dominators in a flowgraph",
  # ACM TOPLAS 1(1), 1979. Vertices are numbered by depth-first preorder from the root;
  # semidominators are computed in reverse preorder through the forest `ancestor`/`label`
  # with path compression (the "simple" eval/link, O(E log V)); immediate dominators follow
  # in preorder. Only vertices the DFS reached have numbers; an in-neighbour without one is
  # not on any path from the root and is skipped. The result is held to the removal
  # definition by a property in the tests, over every node of generated graphs.
  defp lengauer_tarjan(dg, root) do
    {order, parent} = dfs(dg, root)
    n = length(order)
    vertex = order |> Enum.with_index() |> Map.new(fn {v, i} -> {i, v} end)
    dfnum = order |> Enum.with_index() |> Map.new()

    state = %{
      dfnum: dfnum,
      parent: parent,
      semi: dfnum,
      ancestor: %{},
      label: Map.new(order, &{&1, &1}),
      bucket: %{},
      idom: %{}
    }

    state =
      Enum.reduce((n - 1)..1//-1, state, fn i, st -> steps_2_and_3(dg, st, vertex, vertex[i]) end)

    # Step 4: explicit immediate dominators, in preorder.
    Enum.reduce(1..(n - 1)//1, state.idom, fn i, idom ->
      w = vertex[i]
      if idom[w] != vertex[state.semi[w]], do: Map.put(idom, w, idom[idom[w]]), else: idom
    end)
  end

  # For one vertex w, in reverse preorder. Step 2: its semidominator, the smallest preorder
  # number among the semidominators reachable through its in-neighbours' forest paths. Step 3:
  # the implicit immediate dominators of every vertex parent(w) semidominates.
  defp steps_2_and_3(dg, st, vertex, w) do
    st = Enum.reduce(:digraph.in_neighbours(dg, w), st, &semi_via(&1, w, &2))
    sd = vertex[st.semi[w]]
    st = update_in(st.bucket, &Map.update(&1, sd, [w], fn l -> [w | l] end))
    p = st.parent[w]
    st = put_in(st.ancestor[w], p)
    {members, st} = {Map.get(st.bucket, p, []), update_in(st.bucket, &Map.delete(&1, p))}

    Enum.reduce(members, st, fn v, st ->
      {u, st} = eval(st, v)
      put_in(st.idom[v], if(st.semi[u] < st.semi[v], do: u, else: p))
    end)
  end

  # An in-neighbour the DFS never reached is on no path from the root and contributes nothing.
  defp semi_via(v, w, st) do
    case Map.fetch(st.dfnum, v) do
      :error ->
        st

      {:ok, _} ->
        {u, st} = eval(st, v)
        if st.semi[u] < st.semi[w], do: put_in(st.semi[w], st.semi[u]), else: st
    end
  end

  # Depth-first preorder from the root: the vertices in the order first seen, and each one's
  # DFS parent. Iterative, so a long chain costs no stack.
  defp dfs(dg, root) do
    walk(dg, [{root, nil}], MapSet.new(), [], %{})
  end

  defp walk(_dg, [], _seen, order, parent), do: {Enum.reverse(order), parent}

  defp walk(dg, [{v, p} | rest], seen, order, parent) do
    if MapSet.member?(seen, v) do
      walk(dg, rest, seen, order, parent)
    else
      parent = if p, do: Map.put(parent, v, p), else: parent
      next = for u <- :digraph.out_neighbours(dg, v), not MapSet.member?(seen, u), do: {u, v}
      walk(dg, next ++ rest, MapSet.put(seen, v), [v | order], parent)
    end
  end

  # eval(v): the vertex with the smallest semidominator on the forest path above v, with the
  # path compressed as it is read.
  defp eval(st, v) do
    case Map.fetch(st.ancestor, v) do
      :error -> {v, st}
      {:ok, _} -> compress(st, v) |> then(fn st -> {st.label[v], st} end)
    end
  end

  defp compress(st, v) do
    a = st.ancestor[v]

    if Map.has_key?(st.ancestor, a) do
      st = compress(st, a)

      st =
        if st.semi[st.label[a]] < st.semi[st.label[v]],
          do: put_in(st.label[v], st.label[a]),
          else: st

      put_in(st.ancestor[v], st.ancestor[a])
    else
      st
    end
  end

  # The dominators of the target: the idom chain up to the root, root and target excluded.
  defp dominators(idom, target) do
    Stream.unfold(idom[target], fn
      nil -> nil
      @root -> nil
      v -> {v, idom[v]}
    end)
    |> MapSet.new()
  end
end
