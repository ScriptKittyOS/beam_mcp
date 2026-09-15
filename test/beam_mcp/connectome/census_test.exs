# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.CensusTest do
  @moduledoc """
  Two census checks over the package's own source, both derived from `git ls-files`, never
  from a hand list. They pin two invariants the connectome must keep from here on.

  **The sign slot.** Nothing in `lib/` writes a sign other than `:unset`. Read as code, not
  as prose: every occurrence of the token `sign` in a code line under `lib/` must be one of
  the struct default (`sign: :unset`), a typespec, the field's own definition, or the
  membership check `Edge.check/1` performs for `Graph.new/1`; and the
  atoms `:allow`, `:deny`, `:hold` may appear in a code line only inside the `@type sign`
  union that names them. Comment lines and documentation heredocs are excluded from the
  population, because a sentence about signs is not a write.

  The limit, stated, and it is wider than "a key held in a variable". A write evades this
  census when neither the key nor the value is spelled on a code line: a whole-collection
  write with a variable argument (`struct(e, host_fields)`, `Map.merge(e, fields)`,
  `Map.put(e, key, value)`); a compound identifier the word boundary does not split
  (`:default_sign`, `opts[:edge_sign]`); a computed atom (`String.to_atom("si" <> "gn")`);
  and code inside a `\"""` heredoc, which this file reads as documentation. The
  strip-then-match rule also lets a fifth atom appended to the `@type sign` union through;
  the vocabulary census in `connectome_vocabulary_test.exs` is what refuses that. So the
  standing rule for later slices is the one this census cannot enforce by itself: a decoder
  builds an edge through `Edge.new/1`, never through `struct/2` over external input. That is
  what a reader of `lib/` checks by hand.

  **One node-id site.** `Node.id/1` is the only function that turns an identity into an id,
  and every `%Node{}` in `lib/` is built in `node.ex`. A second site is how two id schemes
  arrive; the census refuses it by count. Its limit: it counts `def id(` under
  `lib/beam_mcp/connectome/` and the struct literal spelled `%Node{` or
  `%BeamMCP.Connectome.Node{` or `struct(Node`. A function under another name, an inline
  join of the same parts in a builder, an aliased literal (`%N{`), or a `def id(` elsewhere
  under `lib/` is outside its count.
  """
  use ExUnit.Case, async: true

  @lib_files_cmd ["ls-files", "-z", "--", "lib/"]

  # The token `sign` as a word, or one of the three non-default sign atoms as a whole atom.
  # Whole tokens, not substrings: `:allowed_origins` is not `:allow`, and `assign` is not
  # `sign` -- the first draft matched both and reported the HTTP transport.
  @sign_token ~r/\bsign\b|(?<![\w?!]):(allow|deny|hold|ungoverned|unset)(?![\w?!])/

  test "no code line under lib/ writes or names a sign other than :unset" do
    offenders =
      for file <- tracked(),
          {line, n} <- code_lines(file),
          Regex.match?(@sign_token, line),
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

    assert match?(["lib/beam_mcp/connectome/node.ex:" <> _], id_sites),
           "expected exactly one `def id(` site, in node.ex; found: #{inspect(id_sites)}"

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

  # A line is permitted when, with every permitted form removed from it, no sign token
  # remains. The permitted forms: the struct default `sign: :unset`; the typespec union
  # naming the five values; the struct field's type `sign: sign()`; the typedoc's name.
  # The first form is the struct default in its defstruct spelling only -- `, sign: :unset]`
  # -- because the bare `sign: :unset` let `%{e | sign: :unset}` through: a launder that
  # corrects a host's sign to the default is spelled with exactly the permitted text. Review
  # found it; the narrower form makes that line visible. The last two are the domain check
  # `Edge.check/1` runs for `Graph.new/1`: the membership list, spelled once, and the predicate
  # that reads it -- reading, which the refusal tests hold from the other side.
  @permitted_forms [
    ", sign: :unset]",
    "@type sign :: :allow | :deny | :hold | :ungoverned | :unset",
    "sign: sign()",
    "@signs [:allow, :deny, :hold, :ungoverned, :unset]",
    # The typedoc names the one value the package writes and what it means; prose, by its
    # exact text.
    "@typedoc \"A policy's verdict on the edge; the package itself writes only `:unset`, which means no sign has been supplied to it.\"",
    "{:sign, &(&1 in @signs)}",
    # The serializer carries the sign OUT to bytes and to the exports, under its field name
    # (docs/connectome-canonical.md, rule 5). Each of these is a read of a built edge's
    # sign, spelled once in canonical.ex; none takes a sign in. A new spelling is a new
    # line here, seen in a diff.
    "for {{from, to, kind, prov}, sign} <- edges do",
    "defp json({{from, to, kind, prov}, sign}) do",
    "Atom.to_string(e.sign)}",
    "{\"sign\", sign}",
    "\", sign=\",",
    "dot_q(sign),",
    "xml(sign),",
    "<key id=\"sign\" for=\"edge\" attr.name=\"sign\" attr.type=\"string\"/>",
    "<data key=\"sign\">",
    # The diff engine (014) READS both sides' signs to class an edge as changed-sign, and
    # writes none: a typespec on the changed-sign entry, and one read of a built edge's sign
    # per graph, spelled once in diff.ex.
    "declared_sign: Edge.sign()",
    "observed_sign: Edge.sign()",
    "%Edge{from: from, to: to, kind: kind, sign: sign}",
    "{{nfc(from), nfc(to), kind}, sign}",
    # The one comparison of two signs, spelled once: changed-sign is two authorities
    # disagreeing, so :unset -- no sign supplied to this package -- never participates
    # (016d). Reading, not writing; and not a filter (the test below).
    "declared != :unset and observed != :unset and declared != observed"
  ]

  # 016d, the constraint that makes :ungoverned safe: the package never treats a sign as
  # suppression. No code line under lib/ pairs a sign with a filter, a rejection, a guard or
  # a case on its value -- every read of a sign above carries it out to bytes or compares two
  # of them, and none decides whether an edge is recorded.
  @filtering ~r/Enum\.(filter|reject|split_with|drop_while|take_while|find|any\?|all\?|count|group_by)|\bwhen\b.*\bsign\b|\bcase\b.*\bsign\b|\bif\b.*\bsign\b/

  test "no code line under lib/ filters, hides or downgrades an edge on the basis of its sign" do
    offenders =
      for file <- tracked(),
          {line, n} <- code_lines(file),
          Regex.match?(@sign_token, line),
          Regex.match?(@filtering, line),
          do: "#{file}:#{n}: #{String.trim(line)}"

    assert offenders == [],
           "a sign read beside a filter, guard or branch:\n" <> Enum.join(offenders, "\n")
  end

  defp permitted_sign_line?(line) do
    stripped = Enum.reduce(@permitted_forms, line, &String.replace(&2, &1, ""))
    not Regex.match?(@sign_token, stripped)
  end

  defp tracked do
    {out, 0} = System.cmd("git", @lib_files_cmd)
    String.split(out, <<0>>, trim: true)
  end
end
