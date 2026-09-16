# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.LivebookTest do
  # The notebook under livebooks/ renders the connectome from the JSON export alone. What
  # this file holds it to, against the tracked artefacts and never a description of them:
  # the exports it reads are what the package produces today, byte for byte; its setup cell
  # installs no beam_mcp and no cell names the package; every cell parses; every export it
  # names is tracked. Evaluating the cells needs Kino and so a network: tools/livebook_eval.exs
  # does that by hand, with its run recorded, and this test does the rest offline.
  use ExUnit.Case, async: true

  alias BeamMCP.Fixture.Livebook, as: Fixture

  @root Path.expand("../..", __DIR__)
  @exports_dir "livebooks/exports"

  defp tracked(prefix) do
    {out, 0} = System.cmd("git", ["ls-files", "--", prefix], cd: @root)
    String.split(out, "\n", trim: true)
  end

  defp cells(livemd) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(livemd)
    |> Enum.map(fn [_, code] -> code end)
  end

  describe "the Neo4j cell" do
    # The round-trip the issue asked of a Cypher exporter, made of the idiom instead: the
    # cell's two statements name the export's `nodes` and `edges` arrays and the fields the
    # canonical bytes carry, and the counts it reports are the export's own.
    test "loads the export's nodes and edges by the fields the canonical bytes carry, and counts what the export counts" do
      livemd = File.read!(Path.join(@root, "livebooks/connectome.livemd"))
      [cell] = Enum.filter(cells(livemd), &String.contains?(&1, "apoc.load.json"))
      assert cell =~ "UNWIND value.nodes AS n"
      assert cell =~ "MERGE (v:Node {id: n.id})"
      assert cell =~ "UNWIND value.edges AS e"
      assert cell =~ "MATCH (a:Node {id: e.from}), (b:Node {id: e.to})"
      assert cell =~ ~S|length(declared["nodes"])|
      assert cell =~ ~S|length(declared["edges"])|
      # The counts are the export's: the tracked declared export has these many.
      declared = Jason.decode!(File.read!(Path.join(@root, "livebooks/exports/fx.declared.json")))
      assert declared["nodes"] != [] and declared["edges"] != []
      for field <- ~w(id kind level labels), do: assert(cell =~ "n.#{field}")
      for field <- ~w(from to kind provenance sign), do: assert(cell =~ "e.#{field}")
    end
  end

  describe "the exports" do
    test "every tracked export is what the package produces from the fixtures, and nothing else is tracked there" do
      expected = Fixture.exports()
      files = tracked(@exports_dir)
      json = Enum.filter(files, &String.ends_with?(&1, ".json"))

      assert Enum.sort(json) ==
               Enum.sort(Enum.map(Map.keys(expected), &Path.join(@exports_dir, &1)))

      for {name, bytes} <- expected do
        assert File.read!(Path.join([@root, @exports_dir, name])) == bytes,
               "#{name} differs from what the package produces today"
      end

      # Every export carries its licence in a sidecar (JSON has no comment to carry one).
      for name <- Map.keys(expected) do
        assert Path.join(@exports_dir, name <> ".license") in files
      end
    end

    test "the export shows three classes and the drift the running catalog carries" do
      diff = Jason.decode!(Fixture.exports()["fx.diff.json"])
      assert length(diff["classes"]["declared_and_observed"]) == 2
      assert length(diff["classes"]["declared_never_observed"]) == 2
      assert [%{"to" => "fx/tool/probe"}] = diff["classes"]["observed_but_undeclared"]
      assert diff["classes"]["changed_sign"] == []
    end
  end

  describe "the notebook" do
    test "there is at least one, its setup cell installs no beam_mcp, no cell names the package, every cell parses, every export it names is tracked" do
      notebooks = tracked("livebooks/*.livemd")
      assert notebooks != [], "no notebook under livebooks/"
      exports = tracked(@exports_dir) |> Enum.map(&Path.basename/1)

      for path <- notebooks do
        cells = cells(File.read!(Path.join(@root, path)))
        assert [setup | _] = cells, "#{path}: no Elixir cell"
        assert setup =~ "Mix.install(", "#{path}: the first cell is not the Mix.install cell"
        refute setup =~ "beam_mcp", "#{path}: the notebook installs the package"

        for {code, i} <- Enum.with_index(cells, 1) do
          refute code =~ "BeamMCP", "#{path}: cell #{i} names the package"
          assert {:ok, _} = Code.string_to_quoted(code), "#{path}: cell #{i} does not parse"
        end

        # Every string literal naming a .json file is an export the notebook reads.
        named =
          cells
          |> Enum.flat_map(&Regex.scan(~r/"([^"#]+\.json)"/, &1, capture: :all_but_first))
          |> List.flatten()
          |> Enum.uniq()

        assert named != [], "#{path}: reads no export"

        for name <- named,
            do: assert(name in exports, "#{path} reads exports/#{name}, not tracked")
      end
    end
  end
end
