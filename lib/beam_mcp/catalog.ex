# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Catalog do
  @moduledoc """
  The contract a host implements to tell a `BeamMCP.Server` what it offers.

  The server holds no catalog of its own. It advertises what `capabilities/0` returns and
  accepts a `tools/call` only for a tool `capabilities/0` names, so one implementation governs
  both — a tool advertised by `tools/list` and refused by `tools/call` is the defect this
  behaviour exists to make impossible.

  ## The shape

      %{
        tools: [BeamMCP.ToolSpec.t()],
        resources: [BeamMCP.ResourceSpec.t() | BeamMCP.ResourceTemplateSpec.t()],
        prompts: []
      }

  Every key is **required and may be empty**. `resources` holds both resources and resource
  templates -- one list, two structs -- so that serving templates added a reader rather than
  a key, and every host that had written `capabilities/0` with an empty list kept working.
  `prompts` is not yet read by the server; the declared-connectome builder reads a `:name`
  from each entry to name a node and enumerates the rest as unreadable.

  A key that is absent is a malformed catalog, not an empty one — the two are different claims
  and only one of them is checkable.

  ## Resources: advertise and read from one reader, as tools do

  `resources/1` and `templates/1` are the single readers. `resources/list` and
  `resources/templates/list` advertise what they return, and `readable?/2` decides from the
  same call whether a `resources/read` uri is served at all: a uri the catalog lists, or one a
  listed template matches, is passed to the catalog's `read_resource/1`; any other is
  refused before host code runs. A catalog that lists a resource must export
  `read_resource/1` -- `validate/1` refuses one that does not, because advertising what
  cannot be read is the defect this behaviour exists to make impossible.

  `read_resource/1` answers `{:ok, contents}` -- a list of `%{uri: String.t(), text:
  String.t()}` or `%{uri: String.t(), blob: binary()}` maps, each with an optional
  `mime_type:`; the server base64-encodes a blob -- or `{:error, reason}`, which reaches
  the client as `-32002` carrying the reason as data.

  ## Why `capabilities/0` and not `BeamMCP.ToolCatalog.all/0`

  This behaviour replaces `BeamMCP.ToolCatalog`, whose callback was `BeamMCP.ToolCatalog.all/0`,
  returning a list.
  Keeping the name while changing the return from a list to a map would compile against every
  existing host and fail at the first request with a `BadMapError` — a silent shape change,
  which is the defect class this repository keeps finding. Renaming makes the break arrive at
  compile time as an unimplemented callback, which is the loudest place it can arrive.
  """

  @typedoc """
  What a host offers. Every key is required. `prompts` is typed as a generic list because the
  server does not read it yet and no code enforces a shape -- the connectome builder reads a
  name from each entry and enumerates the rest, which is a reader, not a contract.
  """
  @type t :: %{
          required(:tools) => [BeamMCP.ToolSpec.t()],
          required(:resources) => [BeamMCP.ResourceSpec.t() | BeamMCP.ResourceTemplateSpec.t()],
          required(:prompts) => list()
        }

  @typedoc """
  One item of a resource's contents, as the catalog's reader returns it: text as a string, or
  a blob as raw bytes (the server encodes it), with the uri it belongs to and an optional
  MIME type.
  """
  @type contents ::
          %{
            required(:uri) => String.t(),
            required(:text) => String.t(),
            optional(:mime_type) => String.t()
          }
          | %{
              required(:uri) => String.t(),
              required(:blob) => binary(),
              optional(:mime_type) => String.t()
            }

  @callback capabilities() :: t()

  @doc """
  Reads a resource the catalog lists, or one a listed template matches. Required when
  `capabilities/0` names any resource; `validate/1` refuses a catalog that lists one without
  it.
  """
  @callback read_resource(uri :: String.t()) :: {:ok, [contents()]} | {:error, term()}

  @optional_callbacks read_resource: 1

  @required_keys [:tools, :resources, :prompts]

  @doc """
  The tools a catalog offers.

  **This is the single reader, and that is the point rather than a convenience.** Both paths go
  through it: `tools/list` advertises what it returns, and `fetch/2` decides callability from
  the same call. Slice 002 fixed a real defect where advertising honoured an injected catalog
  and calling ignored it — two readers, two answers. One function is how that stays fixed, and
  a mutant that gives the two paths different sources is scored in the repository's record
  of the catalog generalisation (a slice archive; not in the package).
  """
  @spec tools(module()) :: [BeamMCP.ToolSpec.t()]
  def tools(catalog), do: catalog.capabilities().tools

  @doc """
  The resources a catalog offers -- the `BeamMCP.ResourceSpec` entries of its `resources`
  list, sorted by `uri`. The single reader for `resources/list` and for readability.
  """
  @spec resources(module()) :: [BeamMCP.ResourceSpec.t()]
  def resources(catalog) do
    entries = for %BeamMCP.ResourceSpec{} = r <- entries(catalog), do: r
    Enum.sort_by(entries, & &1.uri)
  end

  @doc """
  The resource templates a catalog offers -- the `BeamMCP.ResourceTemplateSpec` entries of its
  `resources` list, sorted by `uri_template`. The single reader for
  `resources/templates/list` and for readability.
  """
  @spec templates(module()) :: [BeamMCP.ResourceTemplateSpec.t()]
  def templates(catalog) do
    entries = for %BeamMCP.ResourceTemplateSpec{} = t <- entries(catalog), do: t
    Enum.sort_by(entries, & &1.uri_template)
  end

  # The one call behind both resource readers.
  defp entries(catalog), do: catalog.capabilities().resources

  @doc """
  Whether a `resources/read` uri is served at all: listed by `resources/1`, or matched by a
  template `templates/1` returns. RFC 6570 level 1 plus reserved expansion, and nothing more:
  `{var}` matches one segment (any run of characters without `/`), `{+var}` matches across
  segments; every other character of the template is literal.
  """
  @spec readable?(module(), String.t()) :: boolean()
  def readable?(catalog, uri) when is_binary(uri) do
    Enum.any?(resources(catalog), &(&1.uri == uri)) or
      Enum.any?(templates(catalog), &template_matches?(&1.uri_template, uri))
  end

  @doc false
  def template_matches?(template, uri) do
    pattern =
      template
      |> String.split(~r/\{\+?[^}]+\}/, include_captures: true)
      |> Enum.map_join(fn
        "{+" <> _ -> ".+"
        "{" <> _ -> "[^/]+"
        literal -> Regex.escape(literal)
      end)

    Regex.match?(~r/\A#{pattern}\z/, uri)
  end

  @doc """
  Finds the spec a tool name refers to, or `:error`.

  One lookup, used by every caller that has to answer "which tool does this name mean". The
  core uses it to decide whether a `tools/call` is callable at all; the HTTP transport uses it
  to read the `x-mcp-header` annotations it must validate against. Two implementations of this
  question would be two answers, which is precisely the header-versus-body disagreement the
  transport's validation exists to prevent.

  ## This function raises on a malformed catalog, and the `@spec` does not say so

  Stated rather than caught, and the reason is the guarantee above. A host bug turned into
  `:error` is indistinguishable from "no such tool" — so a catalog that is broken would present
  exactly as a catalog that is working and simply does not have that tool. That is the
  advertise-versus-call disagreement this behaviour exists to prevent, reintroduced by the
  error handling meant to be defensive.

  Measured on this tree rather than inherited from a prior note (the probe's transcript is
  in the repository's record of the catalog generalisation, not in the package):

      host spec.name is a binary, not an atom       ArgumentError
      capabilities/0 returns a non-list map         BadMapError
      capabilities/0 returns nil                    Protocol.UndefinedError
      module is not loaded / does not exist         UndefinedFunctionError

  Use `validate/1` to refuse these at startup instead, which is what `BeamMCP.Server.new/1`
  does.
  """
  @spec fetch(module(), String.t() | atom()) :: {:ok, BeamMCP.ToolSpec.t()} | :error
  def fetch(catalog, name) when is_atom(name), do: fetch(catalog, Atom.to_string(name))

  def fetch(catalog, name) when is_atom(catalog) and is_binary(name) do
    catalog
    |> tools()
    |> Enum.find_value(:error, fn spec ->
      if Atom.to_string(spec.name) == name, do: {:ok, spec}
    end)
  end

  def fetch(_catalog, _name), do: :error

  @doc """
  Checks that a module is a usable catalog, returning `:ok` or `{:error, reason}`.

  Calls `capabilities/0`, so it belongs where host code may safely run. `BeamMCP.Server.new/1`
  calls it; the HTTP transport's `Plug` `init` callback deliberately does not, because Plug's
  default initialisation is the host's **compile** time and a catalog reading config or ETS
  there would fail for a correct host. That transport checks the export and leaves the shape to
  `BeamMCP.Server.new/1`. (The transport's `init` callback is not linked here: it is a hidden
  callback, and a doc reference to it is a broken link rather than a useful one.)
  """
  @spec validate(module()) :: :ok | {:error, String.t()}
  def validate(catalog) when is_atom(catalog) and not is_nil(catalog) do
    with {:module, _} <- Code.ensure_compiled(catalog),
         true <- function_exported?(catalog, :capabilities, 0) do
      validate_shape(catalog)
    else
      _ -> {:error, "#{inspect(catalog)} does not export capabilities/0"}
    end
  end

  def validate(other), do: {:error, "expected a module, got: #{inspect(other)}"}

  defp validate_shape(catalog) do
    case catalog.capabilities() do
      %{} = caps ->
        validate_keys(catalog, caps)

      other ->
        {:error, "#{inspect(catalog)}.capabilities/0 must return a map, got: #{inspect(other)}"}
    end
  rescue
    e -> {:error, "#{inspect(catalog)}.capabilities/0 raised #{inspect(e.__struct__)}"}
  end

  defp validate_keys(catalog, caps) do
    missing = Enum.reject(@required_keys, &Map.has_key?(caps, &1))

    cond do
      missing != [] ->
        {:error,
         "#{inspect(catalog)}.capabilities/0 is missing required key(s): #{inspect(missing)}"}

      not is_list(caps.tools) ->
        {:error, "#{inspect(catalog)}.capabilities/0's :tools must be a list"}

      not Enum.all?(caps.tools, &match?(%BeamMCP.ToolSpec{}, &1)) ->
        {:error, "#{inspect(catalog)}.capabilities/0's :tools must all be %BeamMCP.ToolSpec{}"}

      not is_list(caps.resources) ->
        {:error, "#{inspect(catalog)}.capabilities/0's :resources must be a list"}

      not Enum.all?(caps.resources, &resource_entry?/1) ->
        {:error,
         "#{inspect(catalog)}.capabilities/0's :resources must all be %BeamMCP.ResourceSpec{} " <>
           "or %BeamMCP.ResourceTemplateSpec{}"}

      caps.resources != [] and not function_exported?(catalog, :read_resource, 1) ->
        {:error,
         "#{inspect(catalog)} lists a resource and does not export read_resource/1, " <>
           "so what it advertises could not be read"}

      true ->
        :ok
    end
  end

  defp resource_entry?(%BeamMCP.ResourceSpec{}), do: true
  defp resource_entry?(%BeamMCP.ResourceTemplateSpec{}), do: true
  defp resource_entry?(_), do: false
end
