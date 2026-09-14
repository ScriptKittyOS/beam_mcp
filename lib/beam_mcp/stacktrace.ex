# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Stacktrace do
  @moduledoc """
  A stacktrace with its argument lists replaced by their lengths, and each frame's location
  reduced to what the compiler writes.

  The BEAM puts a call's argument list in the top frame of a `function_clause` or a BIF
  error's stacktrace -- three of four common failure shapes -- so a stacktrace written
  anywhere a caller's bytes must not go (a telemetry event's metadata, a transport's fault
  log) carries the arguments with it. `arities/1` is the one rewrite, used by every such
  site in the package:

    * an argument list becomes its length, as the BEAM itself writes frames below the top;
    * a location keeps `file:` only when it is a charlist and `line:` only when it is an
      integer -- a host can put any term into a frame's location through
      `:erlang.error/3`'s `error_info`, and it does not travel;
    * a frame whose arity position is neither a list nor an integer is dropped, as a fun
      frame is: no compiler writes one, and a host hand-building frames for
      `:erlang.raise/3` put its arguments there (measured).

  Total over any term `:erlang.raise/3` accepts, because it runs inside catch clauses,
  where a raise of its own would replace the host's error and leave a span open (measured,
  by a review lane). The host's own stacktrace is never touched: callers re-raise the
  original and hand this function a copy.
  """

  @typedoc "A frame as `arities/1` writes it: module, function, arity, file and line only."
  @type frame :: {module(), atom(), non_neg_integer(), [file: charlist(), line: integer()]}

  @doc """
  The stacktrace with arities for argument lists and plain locations, frames of no known
  shape dropped.

      iex> BeamMCP.Stacktrace.arities([{Enum, :map, [[1, 2], nil], [file: ~c"lib/enum.ex", line: 1]}])
      [{Enum, :map, 2, [file: ~c"lib/enum.ex", line: 1]}]
  """
  @spec arities(Exception.stacktrace() | list()) :: [frame()]
  def arities(stacktrace) when is_list(stacktrace) do
    for {m, f, args_or_arity, loc} <- stacktrace,
        is_list(args_or_arity) or is_integer(args_or_arity) do
      {m, f, arity(args_or_arity), location(loc, [])}
    end
  end

  defp arity(args) when is_list(args), do: count(args, 0)
  defp arity(arity) when is_integer(arity), do: arity

  # An improper list is counted, not measured with length/1, which raises on it.
  defp count([_ | rest], n), do: count(rest, n + 1)
  defp count(_, n), do: n

  # What the compiler writes: a charlist for the file, an integer for the line.
  defp location([{:file, file} | rest], acc) when is_list(file) do
    if :io_lib.char_list(file),
      do: location(rest, [{:file, file} | acc]),
      else: location(rest, acc)
  end

  defp location([{:line, line} | rest], acc) when is_integer(line),
    do: location(rest, [{:line, line} | acc])

  defp location([_ | rest], acc), do: location(rest, acc)
  defp location(_, acc), do: Enum.reverse(acc)
end
