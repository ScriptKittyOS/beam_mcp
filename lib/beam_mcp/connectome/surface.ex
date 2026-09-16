# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Surface do
  @moduledoc """
  The connectome on the wire: three read-only resources and one `:observe` tool a host may put
  in its catalog, each answering the canonical bytes of a graph and nothing else.

  Nothing here is served unless the host lists it: `resources/0` are three `BeamMCP.ResourceSpec`
  for the host's `resources:` list, and the host's `c:BeamMCP.Catalog.read_resource/1`
  delegates to `read/2`. A host that exposes tools only writes the one tool itself -- the
  package holds no tool, by the will-not-implement page's entry 11, so the spec below is the
  host's to copy -- and its dispatch delegates to `call/2`. The package claims no capability
  for any of it: there is no topology or reachability primitive in either revision it serves,
  and it invents none; a graph is a resource like any other resource.

      %BeamMCP.ToolSpec{
        name: :connectome,
        command_class: :observe,
        mode: :read_only,
        description: "Read a connectome graph as canonical JSON.",
        input_schema: %{
          "type" => "object",
          "properties" => %{"graph" => %{"type" => "string", "enum" => ["declared", "observed", "diff"]}},
          "required" => ["graph"],
          "additionalProperties" => false
        }
      }

  ## The bytes are the file export's

  `connectome://declared` and `connectome://observed` answer exactly what
  `BeamMCP.Connectome.Canonical.encode/1` writes for the graph (`docs/connectome-canonical.md`);
  `connectome://diff` answers exactly `BeamMCP.Connectome.Diff.encode/1` of the record
  (`docs/connectome-diff.md`). A consumer who has the file has the resource, byte for byte, and
  the hash rule the canonical page defines verifies either. The tool answers the same bytes as the value of
  `bytes` in its structured content, with their SHA-256 beside them, so a client verifies
  without re-encoding; the tool result's text content is the server's rendering of that map,
  as for every tool, and is not the bytes.

  ## What the host supplies

      def read_resource("connectome://" <> _ = uri) do
        BeamMCP.Connectome.Surface.read(uri,
          declared: [server: "my-app", apps: [:my_app], catalog: __MODULE__],
          observed: MyApp.Collector,
          window: %{"started_at" => started, "ended_at" => ended}
        )
      end

  `declared:` is `BeamMCP.Connectome.Declared.build/1`'s option list; `observed:` the
  collector's name (`BeamMCP.Connectome.Observed`); `window:` the consumer's map the diff
  record carries verbatim. Each is read only when its graph asks for it, and a missing one is
  refused by name. Every sign the package writes is `:unset` (`docs/connectome.md`).

  ## Read-only, by construction and by test

  `read/2` and `call/2` build a graph, encode it and return; they write nothing -- not to the
  collector's table, not to the tracer's persistent terms, not to the disk. A test compares
  the package's state before and after, term for term, and holds it equal. One consequence
  a host should expect: the *tool's* call is a dispatch like any other, and a running
  collector records every dispatch, so after the first `tools/call` of the tool the observed
  graph carries the tool's own edge (the resource path is not a dispatch and adds nothing);
  a host whose `declared:` names its own catalog has that edge declared too, so it lands as
  a matched edge, not as drift; and since an observed edge's weight is a call count, each call
  of the tool for `observed` or `diff` raises its own edge's weight by one in the sidecar and
  in the diff's weights -- the canonical bytes of the observed graph carry no weight and are
  unchanged after the first call, which is what the `idempotentHint` a `:read_only` tool
  carries promises of them. Pagination of a large graph's bytes and subscriptions on
  `connectome://observed` are out of this module (the server sends no notifications: the
  capability is advertised with `subscribe: false`).
  """

  alias BeamMCP.Connectome.{Canonical, Declared, Diff, Observed}
  alias BeamMCP.ResourceSpec

  @graphs ["declared", "observed", "diff"]

  @doc "The three resources, sorted by uri as the list is served."
  @spec resources() :: [ResourceSpec.t()]
  def resources do
    [
      %ResourceSpec{
        uri: "connectome://declared",
        name: "connectome-declared",
        title: "Declared connectome",
        description:
          "The declared connectome as canonical JSON, byte-identical to the file export " <>
            "(docs/connectome-canonical.md).",
        mime_type: "application/json"
      },
      %ResourceSpec{
        uri: "connectome://diff",
        name: "connectome-diff",
        title: "Connectome diff",
        description:
          "The diff record between the declared and the observed connectome over the " <>
            "consumer's window, as canonical JSON (docs/connectome-diff.md).",
        mime_type: "application/json"
      },
      %ResourceSpec{
        uri: "connectome://observed",
        name: "connectome-observed",
        title: "Observed connectome",
        description:
          "The observed connectome as canonical JSON, byte-identical to the file export " <>
            "(docs/connectome-observed.md).",
        mime_type: "application/json"
      }
    ]
  end

  @doc """
  Reads one resource: the contents list a catalog's `c:BeamMCP.Catalog.read_resource/1`
  answers with, or a refusal by name.
  """
  @spec read(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def read("connectome://" <> graph = uri, opts) when graph in @graphs and is_list(opts) do
    with {:ok, {bytes, _hash}} <- bytes(graph, opts),
         do: {:ok, [%{uri: uri, text: bytes, mime_type: "application/json"}]}
  end

  def read(uri, opts) when is_binary(uri) and is_list(opts), do: {:error, {:unknown_uri, uri}}

  @doc """
  The tool's call, for the host's dispatch: the graph's name, its bytes verbatim and their
  SHA-256 in lower-case hex -- the hash the canonical page defines, computed by the same
  functions -- or a refusal by name. Takes the arguments as the server hands them to a
  dispatch (keyed by the declared name, `:graph`).
  """
  @spec call(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call(%{graph: graph}, opts) when graph in @graphs and is_list(opts) do
    with {:ok, {bytes, hash}} <- bytes(graph, opts) do
      {:ok, %{graph: graph, bytes: bytes, sha256: Base.encode16(hash, case: :lower)}}
    end
  end

  def call(%{graph: other}, _opts), do: {:error, {:unknown_graph, other}}
  def call(_args, _opts), do: {:error, {:missing, :graph}}

  # The bytes and their hash, both from the canonical module: the surface computes neither.
  defp bytes("declared", opts) do
    with {:ok, graph} <- declared(opts), do: graph_bytes(graph)
  end

  defp bytes("observed", opts) do
    with {:ok, graph} <- observed(opts), do: graph_bytes(graph)
  end

  defp bytes("diff", opts) do
    with {:ok, window} <- fetch(opts, :window),
         {:ok, declared} <- declared(opts),
         {:ok, observed} <- observed(opts),
         {:ok, diff} <- Diff.run(declared, observed, window: window),
         {:ok, bytes} <- Diff.encode(diff),
         {:ok, hash} <- Diff.hash(diff),
         do: {:ok, {bytes, hash}}
  end

  defp graph_bytes(graph) do
    with {:ok, bytes} <- Canonical.encode(graph),
         {:ok, hash} <- Canonical.hash(graph),
         do: {:ok, {bytes, hash}}
  end

  defp declared(opts) do
    with {:ok, build} <- fetch(opts, :declared),
         {:ok, %Declared.Result{graph: graph}} <- Declared.build(build),
         do: {:ok, graph}
  end

  defp observed(opts) do
    with {:ok, name} <- fetch(opts, :observed), do: Observed.snapshot(name)
  end

  defp fetch(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing, key}}
    end
  end
end
