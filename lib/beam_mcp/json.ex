# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.JSON do
  @moduledoc """
  The one place the wire's JSON is read, on every transport, with the nesting bound in front
  of the decoder.

  The size cap a transport puts on a body (1 MiB on both) bounds how deep a body can nest --
  half its bytes, one level per bracket -- but not what decoding it costs: a 1 MiB body nested
  524 288 levels deep was measured decoding in full, 79-96 ms and a 38 MiB heap for one request,
  about 36x the body, and refused only afterwards by its shape. The bound the README's
  per-request figure rests on (about 1.05 MiB in flight per body at the cap) was the size
  cap's, and the nest broke it thirty-six times over.

  So `decode/1` walks the bytes once before `Jason.decode/1` runs -- a state machine over the
  binary counting `[` and `{` outside strings, with `\\\\` escapes honoured so a bracket inside a
  string is text -- and refuses a body whose nesting passes `max_depth/0` with
  `{:error, {:nesting, depth, max}}`, building nothing. The walk is O(bytes) and allocates
  nothing but its counters; what it costs a well-formed request is measured in
  `docs/threat-model.md`. A body it admits is handed to Jason unchanged, so every other
  answer -- a parse error, a non-object -- is the decoder's, as before.

  ## The number

  `#{64}` levels. A JSON-RPC request is three levels deep before the host's data begins
  (message > params > arguments), and the deepest body the conformance suite or this
  package's own tests send is far under the bound; a host whose tool arguments nest deeper
  than sixty-one levels below that has a real case to bring, with the measurement, and the
  answer is a Question to the owner rather than a raise -- the same standing the body cap has.
  The number is a constant, not an option, for the reason the body cap is one: a limit a host
  can raise by keyword is a limit that gets raised until it means nothing.
  """

  @max_depth 64

  @doc "The deepest nesting a body may carry: `#{@max_depth}` levels."
  @spec max_depth() :: pos_integer()
  def max_depth, do: @max_depth

  @doc """
  Decodes a JSON body after bounding its nesting and refusing a repeated key.
  `{:error, {:nesting, depth, max}}` names the first depth past the bound, before a byte is
  decoded; `{:error, {:duplicate_key, key}}` names the first key an object repeats, at any
  depth; every other error is Jason's.

  Repeated keys are refused rather than resolved because two parsers resolve them two ways:
  Jason keeps the first, most others the last. A hop in front of this server that routes on
  the last `"name"` while this server executes the first is two sources of truth inside one
  body: the disagreement the header–body match exists to close. Jason is asked for ordered
  objects, which keep every pair, so the repeat is visible; the objects are then read once
  into maps, which is what every caller expects. The repeat is found in the decoded objects
  and not in the bytes on purpose: a key is compared after unescaping, as every decoder
  compares it (`"a"` and `"\\u0061"` are one key), and a byte walk that compared raw keys
  would miss exactly the pair a hop in front would merge. What that costs, per shape, is
  measured on `docs/threat-model.md`: a request-sized body twice a 2 µs decode; a 1 MiB body
  2.0–2.6× the decoder's own time, the key-dense shapes at the top of that band.
  """
  @spec decode(binary()) ::
          {:ok, term()}
          | {:error,
             {:nesting, pos_integer(), pos_integer()} | {:duplicate_key, String.t()} | struct()}
  def decode(body) when is_binary(body) do
    with :ok <- bound(nesting(body, 0, @max_depth)),
         {:ok, ordered} <- Jason.decode(body, objects: :ordered_objects) do
      maps(ordered)
    end
  end

  @doc "The type of a decoded value that is not an object, for a refusal that names it."
  @spec type_of(term()) :: String.t()
  def type_of(v) when is_list(v), do: "an array"
  def type_of(v) when is_binary(v), do: "a string"
  def type_of(v) when is_number(v), do: "a number"
  def type_of(nil), do: "null"
  def type_of(_), do: "a scalar"

  defp bound(:ok), do: :ok
  defp bound({:too_deep, depth}), do: {:error, {:nesting, depth, @max_depth}}

  # Ordered objects to maps, refusing the first repeated key met. The key set per object is
  # the map being built: equal keys in different objects are two keys.
  defp maps(%Jason.OrderedObject{values: pairs}) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      if Map.has_key?(acc, key),
        do: {:halt, {:error, {:duplicate_key, key}}},
        else: put(acc, key, value)
    end)
  end

  defp maps(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case maps(value) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp maps(scalar), do: {:ok, scalar}

  defp put(acc, key, value) do
    case maps(value) do
      {:ok, v} -> {:cont, {:ok, Map.put(acc, key, v)}}
      error -> {:halt, error}
    end
  end

  # Depth outside strings. An opening bracket that would pass the bound ends the walk: the
  # refusal names the depth it reached, and nothing past it is read.
  defp nesting(<<>>, _depth, _max), do: :ok

  defp nesting(<<?[, _::binary>>, depth, max) when depth >= max, do: {:too_deep, depth + 1}
  defp nesting(<<?{, _::binary>>, depth, max) when depth >= max, do: {:too_deep, depth + 1}
  defp nesting(<<?[, rest::binary>>, depth, max), do: nesting(rest, depth + 1, max)
  defp nesting(<<?{, rest::binary>>, depth, max), do: nesting(rest, depth + 1, max)
  defp nesting(<<?], rest::binary>>, depth, max), do: nesting(rest, depth - 1, max)
  defp nesting(<<?}, rest::binary>>, depth, max), do: nesting(rest, depth - 1, max)
  defp nesting(<<?", rest::binary>>, depth, max), do: in_string(rest, depth, max)
  defp nesting(<<_, rest::binary>>, depth, max), do: nesting(rest, depth, max)

  # Inside a string a bracket is text; a backslash skips the byte it escapes, so an escaped
  # quote does not end the string. An unterminated string reaches the end of the body, which
  # is Jason's parse error to give, not a nesting refusal.
  defp in_string(<<>>, _depth, _max), do: :ok
  defp in_string(<<?\\, _, rest::binary>>, depth, max), do: in_string(rest, depth, max)
  defp in_string(<<?", rest::binary>>, depth, max), do: nesting(rest, depth, max)
  defp in_string(<<_, rest::binary>>, depth, max), do: in_string(rest, depth, max)
end
