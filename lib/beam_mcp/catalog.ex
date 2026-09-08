# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Catalog do
  @moduledoc """
  The contract a host implements to tell a `BeamMCP.Server` what it offers.

  The server holds no catalog of its own. It advertises what `capabilities/0` returns and
  accepts a `tools/call` only for a tool `capabilities/0` names, so one implementation governs
  both — a tool advertised by `tools/list` and refused by `tools/call` is the defect this
  behaviour exists to make impossible.

  ## The shape carries keys this package does not yet serve

      %{tools: [BeamMCP.ToolSpec.t()], resources: [], prompts: []}

  `resources` and `prompts` are **required and may be empty**. Nothing reads them today. They
  are here so that serving them later adds a reader rather than changing this contract a second
  time, and every host that has already written `capabilities/0` keeps working when they do.

  A key that is absent is a malformed catalog, not an empty one — the two are different claims
  and only one of them is checkable.

  ## Why `capabilities/0` and not `all/0`

  This behaviour replaces `BeamMCP.ToolCatalog`, whose callback was `all/0` returning a list.
  Keeping the name while changing the return from a list to a map would compile against every
  existing host and fail at the first request with a `BadMapError` — a silent shape change,
  which is the defect class this repository keeps finding. Renaming makes the break arrive at
  compile time as an unimplemented callback, which is the loudest place it can arrive.
  """

  @typedoc """
  What a host offers. Every key is required; `resources` and `prompts` are typed as generic
  lists because nothing in this package reads them yet, and typing them precisely now would be
  a claim about a shape no code enforces.
  """
  @type t :: %{
          required(:tools) => [BeamMCP.ToolSpec.t()],
          required(:resources) => list(),
          required(:prompts) => list()
        }

  @callback capabilities() :: t()

  @required_keys [:tools, :resources, :prompts]

  @doc """
  The tools a catalog offers.

  **This is the single reader, and that is the point rather than a convenience.** Both paths go
  through it: `tools/list` advertises what it returns, and `fetch/2` decides callability from
  the same call. Slice 002 fixed a real defect where advertising honoured an injected catalog
  and calling ignored it — two readers, two answers. One function is how that stays fixed, and
  a mutant that gives the two paths different sources is scored in
  `slices/008-catalog-generalization/`.
  """
  @spec tools(module()) :: [BeamMCP.ToolSpec.t()]
  def tools(catalog), do: catalog.capabilities().tools

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

  Measured on this tree rather than inherited from a prior note
  (`slices/008-catalog-generalization/logs/probe-fetch-spec.txt`):

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
  calls it; the HTTP transport's `Plug` callback `init/1` deliberately does not, because Plug's
  default initialisation is the host's **compile** time and a catalog reading config or ETS
  there would fail for a correct host. That transport checks the export and leaves the shape to
  `new/1`. (`init/1` is not linked here: it is a hidden callback, and a doc reference to it is a
  broken link rather than a useful one.)
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

      true ->
        :ok
    end
  end
end
