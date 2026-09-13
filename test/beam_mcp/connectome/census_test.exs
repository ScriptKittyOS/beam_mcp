# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.CensusTest do
  @moduledoc """
  Two census checks over the package's own source, both derived from `git ls-files`, never
  from a hand list. They pin two invariants the connectome must keep from here on.

  **The sign slot.** Nothing in `lib/` writes a sign other than `:unknown`. Read as code, not
  as prose: every occurrence of the token `sign` in a code line under `lib/` must be one of
  the struct default (`sign: :unknown`), a typespec, or the field's own definition; and the
  atoms `:allow`, `:deny`, `:hold` may appear in a code line only inside the `@type sign`
  union that names them. Comment lines and documentation heredocs are excluded from the
  population, because a sentence about signs is not a write. The limit, stated: a write
  through a name the census does not know -- `Map.put(e, :sign, x)` is caught by `:sign`,
  but a key held in a variable is not. That is what reviewer lane (a) reads for.

  **One node-id site.** `Node.id/1` is the only function that turns an identity into an id,
  and every `%Node{}` in `lib/` is built in `node.ex`. A second site is how two id schemes
  arrive; the census refuses it by count.
  """
  use ExUnit.Case, async: true

  @lib_files_cmd ["ls-files", "-z", "--", "lib/"]

  test "no code line under lib/ writes or names a sign other than :unknown" do
    offenders =
      for file <- tracked(),
          {line, n} <- code_lines(file),
          String.contains?(line, "sign") or
            Enum.any?([":allow", ":deny", ":hold"], &String.contains?(line, &1)),
          not permitted_sign_line?(line),
          do: "#{file}:#{n}: #{String.trim(line)}"

    assert offenders == [],
           "sign written or named outside the permitted forms:\n" <> Enum.join(offenders, "\n")
  end

  test "exactly one def id( under lib/beam_mcp/connectome/, and every %Node{} is built in node.ex" do
    connectome = Enum.filter(tracked(), &String.starts_with?(&1, "lib/beam_mcp/connectome/"))
    assert connectome != [], "no connectome modules tracked under lib/"

    id_sites =
      for file <- connectome,
          {line, n} <- code_lines(file),
          Regex.match?(~r/^\s*defp?\s+id\(/, line),
          do: "#{file}:#{n}"

    assert id_sites == [
             "lib/beam_mcp/connectome/node.ex:" <> hd(String.split(hd(id_sites), ":") |> tl())
           ],
           "expected one Node.id/1 clause site in node.ex, found: #{inspect(id_sites)}"

    node_literals =
      for file <- tracked(),
          file != "lib/beam_mcp/connectome/node.ex",
          {line, n} <- code_lines(file),
          Regex.match?(
            ~r/%(BeamMCP\.Connectome\.)?Node\{|struct!?\((BeamMCP\.Connectome\.)?Node[,)]/,
            line
          ),
          do: "#{file}:#{n}"

    assert node_literals == [], "%Node{} built outside node.ex: #{inspect(node_literals)}"
  end

  # A code line is a line that is not a comment and not inside a `"""` heredoc.
  defp code_lines(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, fn {line, n}, {acc, in_doc} ->
      cond do
        String.contains?(line, ~s(""")) ->
          # A heredoc opener or closer; the line itself is never code we need to read.
          {acc, not in_doc}

        in_doc ->
          {acc, in_doc}

        String.match?(line, ~r/^\s*#/) ->
          {acc, in_doc}

        true ->
          {[{line, n} | acc], in_doc}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp permitted_sign_line?(line) do
    t = String.trim(line)

    Regex.match?(~r/^sign: :unknown,?$/, t) or
      Regex.match?(~r/^@type sign :: :allow \| :deny \| :hold \| :unknown$/, t) or
      Regex.match?(~r/^sign: sign\(\),?$/, t)
  end

  defp tracked do
    {out, 0} = System.cmd("git", @lib_files_cmd)
    String.split(out, <<0>>, trim: true)
  end
end
