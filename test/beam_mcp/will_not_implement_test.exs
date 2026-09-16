# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.WillNotImplementTest do
  # The page and the tests are one population, held in both directions. Page -> tree: every
  # test the page cites, by path and by name, exists. Tree -> page: every test file that
  # carries a `# boundary: <entry>` marker is cited on the page, and every file under
  # test/beam_mcp/boundary/ carries the marker. Neither may drift from the other.
  #
  # A citation on the page is a test file's path in backticks followed, on the same line, by one
  # or more test names in straight double quotes: `test/x_test.exs` "a name" "another". A path
  # under test/ that is not a test file (the support reader) is prose, not a citation.
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @page "docs/will-not-implement.md"
  @boundary_dir "test/beam_mcp/boundary"
  @marker ~r/^\s*#\s*boundary:\s*\S/m

  defp page do
    path = Path.join(@root, @page)
    assert File.exists?(path), "#{@page} is not in the tree"
    File.read!(path)
  end

  # [{path, [name]}] in page order; a name belongs to the last path on its line.
  defp citations(text) do
    for line <- String.split(text, "\n"),
        Regex.match?(~r/`test\/[^`]+_test\.exs`/, line),
        {path, names} <- cite_line(line),
        do: {path, names}
  end

  defp cite_line(line) do
    ~r/`(test\/[^`]+_test\.exs)`|"([^"]+)"/
    |> Regex.scan(line)
    |> Enum.reduce([], fn
      [_, path], acc when path != "" -> [{path, []} | acc]
      [_, "", name], [{path, names} | rest] -> [{path, names ++ [name]} | rest]
      [_, "", _name], [] -> []
    end)
    |> Enum.reverse()
  end

  defp marked_files do
    @root
    |> Path.join("test/**/*_test.exs")
    |> Path.wildcard()
    |> Enum.filter(&Regex.match?(@marker, File.read!(&1)))
    |> Enum.map(&Path.relative_to(&1, @root))
    |> Enum.sort()
  end

  test "every test the page cites exists, by path and by name, and every citation names a test" do
    cited = citations(page())
    assert cited != [], "the page cites no test"

    for {path, names} <- cited do
      full = Path.join(@root, path)
      assert File.exists?(full), "the page cites #{path}, which is not in the tree"
      assert names != [], "the page cites #{path} without naming a test in it"
      source = File.read!(full)

      for name <- names do
        assert String.contains?(source, ~s(test "#{name}")),
               "the page cites #{path} #{inspect(name)}, and no test of that name is in the file"
      end
    end
  end

  test "every test file carrying a boundary marker is cited on the page" do
    cited_paths = page() |> citations() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    marked = marked_files()
    assert marked != [], "no test file carries a # boundary: marker"

    assert marked -- cited_paths == [],
           "boundary tests the page does not cite:\n  " <>
             Enum.join(marked -- cited_paths, "\n  ")
  end

  @words ~w(one two three four five six seven eight nine ten eleven twelve thirteen fourteen
            fifteen sixteen seventeen eighteen nineteen twenty)

  # The page's numbered rows: `| 12 | **...` -- the population every count below is held to.
  defp rows(text),
    do: Regex.scan(~r/^\| (\d+) \|/m, text, capture: :all_but_first) |> List.flatten()

  test "the README's count of entries is the page's row count, spelled as the README spells it" do
    n = length(rows(page()))
    assert n > 0
    readme = File.read!(Path.join(@root, "README.md"))
    word = Enum.at(@words, n - 1)
    assert word, "#{n} rows: more than this test spells; extend @words"

    # The README's own idiom, on one line ("boundary — twelve entries,"); a reflow at the em
    # dash goes red here and is fixed by keeping the phrase whole.
    assert readme =~ "boundary — #{word} entries",
           "the page has #{n} rows and the README does not say \"boundary — #{word} entries\" " <>
             "-- a row was added or removed and the README's count did not move with it"
  end

  test "the page's placement sentence names every row exactly once" do
    # "for entries 1, 4, 7, 11 and 12; ... for entries 2 and 3; ... for entries 9, 5, 8 and 10;
    # and for entry 6" -- every row has an owner to point a request at, and none has two.
    # The page's whitespace is folded first, so the paragraph may be reflowed anywhere -- the
    # anchor phrase, a number list, "entry 6" -- and the scan below still reads it whole
    # (`rows/1` reads the raw page: its `^| n |` anchors need the newlines).
    folded = String.replace(page(), ~r/\s+/u, " ")
    [sentence | _] = String.split(folded, "Such a request is answered", parts: 2)
    [_, sentence] = String.split(sentence, "request to cross one of these lines", parts: 2)

    # `u`: the en dash is three bytes, and without it the class consumes one of them. A
    # range in any glyph, spaced or not, or worded, is refused by name rather than read.
    refute sentence =~ ~r/\d\s*[-–—]\s*\d|\d (?:to|through) \d/u,
           "the placement sentence writes a range; list each entry so the census can read it"

    placed =
      ~r/entr(?:y|ies) ([\d, and]+?)(?:;|\.|,\s+the)/
      |> Regex.scan(sentence, capture: :all_but_first)
      |> List.flatten()
      |> Enum.flat_map(&Regex.scan(~r/\d+/, &1))
      |> List.flatten()

    expected = page() |> rows() |> Enum.sort()

    assert Enum.sort(placed) == expected,
           "rows #{inspect(expected)}; the placement sentence names #{inspect(Enum.sort(placed))}"
  end

  test "every file under test/beam_mcp/boundary/ carries the marker" do
    files = @root |> Path.join(@boundary_dir <> "/*_test.exs") |> Path.wildcard()
    assert files != []

    unmarked =
      for f <- files, not Regex.match?(@marker, File.read!(f)), do: Path.relative_to(f, @root)

    assert unmarked == [],
           "under #{@boundary_dir} without a # boundary: marker:\n  " <>
             Enum.join(unmarked, "\n  ")
  end
end
