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
  Decodes a JSON body after bounding its nesting. `{:error, {:nesting, depth, max}}` names
  the first depth past the bound, before a byte is decoded; every other error is Jason's.
  """
  @spec decode(binary()) ::
          {:ok, term()}
          | {:error, {:nesting, pos_integer(), pos_integer()} | struct()}
  def decode(body) when is_binary(body) do
    case nesting(body, 0, @max_depth) do
      :ok -> Jason.decode(body)
      {:too_deep, depth} -> {:error, {:nesting, depth, @max_depth}}
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
