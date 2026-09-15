# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.WillNotImplementTest do
  # The page and the tests are one population, held in both directions. Page -> tree: every
  # test the page cites, by path and by name, exists. Tree -> page: every test file that
  # carries a `# boundary: <entry>` marker is cited on the page, and every file under
  # test/beam_mcp/boundary/ carries the marker. Neither may drift from the other.
  #
  # A citation on the page is a path in backticks followed, on the same line, by one or more
  # test names in straight double quotes: `test/x_test.exs` "a name" "another".
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
        Regex.match?(~r/`test\/[^`]+`/, line),
        {path, names} <- cite_line(line),
        do: {path, names}
  end

  defp cite_line(line) do
    ~r/`(test\/[^`]+)`|"([^"]+)"/
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
