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

  The limit, stated: anchor 3 reads `@type` unions only, and only their BARE-ATOM alternatives
  (`:: :a | :b`), checking for a definition row anywhere in the document rather than under a
  particular heading, because a typespec does not say which family it belongs to. An atom
  inside a tuple alternative -- an error reason such as `{:label_value, id, key, value}` -- is
  not vocabulary and is not read; the first version read every atom in the union and reported
  the canonical encoder's error tags as undefined terms. An atom used as a value outside a
  typespec is not in its population. Slice 010's census over edge construction sites is the
  other half.
  """
  use ExUnit.Case, async: true

  @doc_path "docs/connectome.md"

  # The vocabulary as ratified. Each atom must have a DEFINITION ROW in the document -- a table
  # row that opens `| \`:atom\` |` -- and each name must appear bold, which is how the document
  # marks a term at the sentence that defines it. A definition is a sentence, and the document is
  # where it lives; this file only checks that the sentence exists.
  #
  # "Has a row", not "appears in backticks anywhere": the first version checked the latter, and
  # deleting the `:unset` row survived, because `:unset` is also mentioned in the invariant
  # paragraph. A mention is not a definition, and an anchor that a mention satisfies cannot move
  # when the definition goes (CONVENTIONS.md, the contained anchor). Measured, not assumed:
  # deleting that row was a mutation this file survived until the anchor changed.
  #
  # Each family is checked under ITS OWN HEADING, because `:module` and `:server` are both a
  # node kind and a level: two terms sharing an atom. Checked over the whole document, deleting
  # the node-kind row for `:module` survived -- the level row satisfied it (mutation Md5). The
  # heading is the family, and a row outside it does not define the term in it.
  @families [
    {"Node kinds", [:server, :tool, :resource, :prompt, :process, :module]},
    {"Edge kinds", [:invoke, :read, :message, :supervise]},
    {"Sign", [:allow, :deny, :hold, :ungoverned, :unset]},
    {"Level", [:mfa, :module, :boundary, :server]},
    {"Provenance", [:declared, :observed]},
    {"Algorithm", [:sha256, :sha384, :sha512]},
    {"Scheme", [:ed25519, :ecdsa_p384_sha384, :mldsa87]},
    {"Identity", [:application, :boundary_module]}
  ]
  @names ["connectome", "declared connectome", "observed connectome", "drift finding"]

  # The one-paragraph invariant, pinned by its first sentence.
  @invariant "beam_mcp renders authority; it never decides it."

  test "the vocabulary document exists" do
    assert File.exists?(@doc_path), "#{@doc_path} is absent"
  end

  test "every ratified term is defined in the document" do
    doc = File.read!(@doc_path)

    sections = sections(doc)

    for {family, atoms} <- @families do
      section = Map.get(sections, family)
      assert section, "#{@doc_path} has no \"## #{family}\" section"

      for atom <- atoms do
        assert defined?(section, atom),
               "#{inspect(atom)} has no definition row under \"## #{family}\" in #{@doc_path}"
      end
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

    undefined = Enum.reject(used, fn {atom, _file} -> defined?(doc, atom) end)

    assert undefined == [],
           "atoms in @type unions with no definition in #{@doc_path}: #{inspect(undefined)}"
  end

  # A term is defined when a table row opens with it. The row form is the one every table in
  # the document uses, and it is what a reader would call the definition.
  defp defined?(text, atom), do: String.contains?(text, "| `#{inspect(atom)}` |")

  # The document split at its `## ` headings: heading title -> the text under it.
  defp sections(doc) do
    doc
    |> String.split(~r/^## /m)
    |> Enum.drop(1)
    |> Map.new(fn chunk ->
      [title | body] = String.split(chunk, "\n", parts: 2)
      {String.trim(title), Enum.join(body)}
    end)
  end

  # Every `@type name :: alt | alt | ...` in the file, and every bare atom among its
  # alternatives, tagged with the file it came from so a failure names its source.
  defp type_union_atoms(file) do
    file
    |> File.read!()
    |> then(&Regex.scan(~r/@type\s+\w+(?:\([^)]*\))?\s*::\s*([^\n]+(?:\n\s+\|[^\n]+)*)/, &1))
    |> Enum.flat_map(fn [_, rhs] -> String.split(rhs, "|") end)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(~r/^:[a-z_][a-z0-9_?!]*$/, &1))
    |> Enum.map(fn atom -> {String.to_atom(String.trim_leading(atom, ":")), file} end)
  end
end
