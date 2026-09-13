# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ConnectomeVocabularyTest do
  @moduledoc """
  The connectome vocabulary lives in `docs/connectome.md`, and this file keeps the code from
  drifting away from it silently.

  Three anchors, in the order they can fail:

  1. The document exists. Written before it did, so the first run of this file was red on
     that line alone.
  2. Every ratified term is defined in it. The term lists below are literal, the way
     `readme_claims_test.exs` quotes README sentences: a term that leaves the document leaves
     this file red, and a term added here without the document being updated does the same.
  3. Every atom in a `@type` union under `lib/beam_mcp/connectome/` is defined in the document.
     Derived by reading the tree, not listed: the population is every `.ex` file under that
     directory, and the atoms are the alternatives of every `@type` there. Empty today, which is
     the point -- the first `@type sign :: :allow | ...` a later slice writes is policed by a
     test that already runs, and a fifth edge kind or a new sign cannot arrive without a
     sentence in the public vocabulary.

  The limit, stated: anchor 3 reads `@type` unions only. An atom used as a value outside a
  typespec is not in its population. Slice 010's census over edge construction sites is the
  other half.
  """
  use ExUnit.Case, async: true

  @doc_path "docs/connectome.md"

  # The vocabulary as ratified. Each atom must appear in the document as `:atom` -- the
  # backticked form the document uses to define a term -- and each name as a heading or a
  # bold term. A definition is a sentence, and the document is where it lives; this file only
  # checks that the sentence exists.
  @node_kinds [:server, :tool, :resource, :prompt, :process, :module]
  @edge_kinds [:invoke, :read, :message, :supervise]
  @signs [:allow, :deny, :hold, :unknown]
  @levels [:mfa, :module, :boundary, :server]
  @provenances [:declared, :observed]
  @names ["connectome", "declared connectome", "observed connectome", "drift finding"]

  # The one-paragraph invariant, pinned by its first sentence.
  @invariant "beam_mcp renders authority; it never decides it."

  test "the vocabulary document exists" do
    assert File.exists?(@doc_path), "#{@doc_path} is absent"
  end

  test "every ratified term is defined in the document" do
    doc = File.read!(@doc_path)

    for atom <- @node_kinds ++ @edge_kinds ++ @signs ++ @levels ++ @provenances do
      assert String.contains?(doc, "`#{inspect(atom)}`"),
             "#{inspect(atom)} is not defined in #{@doc_path}"
    end

    for name <- @names do
      assert String.contains?(doc, "**#{name}**"),
             "the name \"#{name}\" is not defined in #{@doc_path}"
    end

    assert String.contains?(doc, @invariant),
           "the invariant sentence is not in #{@doc_path}: #{inspect(@invariant)}"
  end

  test "every atom in a @type union under lib/beam_mcp/connectome/ is defined in the document" do
    doc = File.read!(@doc_path)

    used =
      Path.wildcard("lib/beam_mcp/connectome/**/*.ex")
      |> Enum.flat_map(&type_union_atoms/1)
      |> Enum.uniq()
      |> Enum.sort()

    undefined =
      Enum.reject(used, fn {atom, _file} -> String.contains?(doc, "`#{inspect(atom)}`") end)

    assert undefined == [],
           "atoms in @type unions with no definition in #{@doc_path}: #{inspect(undefined)}"
  end

  # Every `@type name :: alt | alt | ...` in the file, and every bare atom among its
  # alternatives, tagged with the file it came from so a failure names its source.
  defp type_union_atoms(file) do
    file
    |> File.read!()
    |> then(&Regex.scan(~r/@type\s+\w+(?:\([^)]*\))?\s*::\s*([^\n]+(?:\n\s+\|[^\n]+)*)/, &1))
    |> Enum.flat_map(fn [_, rhs] -> Regex.scan(~r/(?<![\w?])(:[a-z_][a-z0-9_?!]*)/, rhs) end)
    |> Enum.map(fn [_, atom] -> {String.to_atom(String.trim_leading(atom, ":")), file} end)
  end
end
