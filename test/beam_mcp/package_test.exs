# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PackageTest do
  @moduledoc """
  The Hex tarball carries every page a public page links to.

  The premise of the pages is that a stranger with the package -- not the repository -- can
  read the byte-layout page and reproduce a hash, and open the boundary contract. A relative
  link in the README that names a file the tarball does not carry breaks that premise for
  everyone who meets the package the ordinary way.

  This file reads the BUILT TARBALL, not the `files:` stanza in `mix.exs` that is supposed to
  produce it: `mix hex.build` runs into a temporary directory, the outer tar is opened, and
  `contents.tar.gz` is listed. The stanza is what we meant; the tarball is what a consumer
  gets. Three populations, none a hand list:

  1. every file reachable by a relative link from `README.md` and `CHANGELOG.md` -- inline,
     reference-style or an HTML `href` -- following links page to page, must be in the
     tarball (any relative target, not only `.md`);
  2. every tracked page under `docs/` (`git ls-files`) must be in the tarball -- a page added
     next year is caught whether or not anyone has linked it yet;
  3. every ExDoc extra (`docs: [extras: ...]` in `mix.exs`) must be in the tarball -- what
     hexdocs renders and what the package carries are the same set.

  Written red: on the tree it was added to, the six pages under `docs/` were absent from a
  116,736-byte tarball of 22 entries.
  """
  use ExUnit.Case, async: false

  @root Path.expand("../..", __DIR__)
  @roots ["README.md", "CHANGELOG.md"]
  # A relative link, in each form Markdown and HTML give it: inline `](target)`, a
  # reference definition `[name]: target` at the start of a line (up to three spaces in, as
  # Markdown allows), and an HTML `href` in either quote. A target that names a scheme
  # (`https://`, `MAILTO:`, any case) or a host (`//cdn/x`), or is only a fragment, is not
  # relative; a `#fragment` after the path is dropped.
  @relative_link ~r/(?:\]\(|^ {0,3}\[[^\]]+\]:[ \t]*|href=["'])(?![a-z][a-z0-9+.-]*:|\/\/|#)([^)"'#\s]+)(?:#[^)"'\s]*)?/mi

  setup_all do
    dir =
      Path.join(System.tmp_dir!(), "beam_mcp_package_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, entries: tarball_entries(dir)}
  end

  test "every page reachable by a relative link from the README or CHANGELOG is in the tarball",
       %{entries: entries} do
    reachable =
      reachable_pages(@roots, MapSet.new(@roots)) |> MapSet.difference(MapSet.new(@roots))

    assert MapSet.size(reachable) > 0,
           "no relative link found from the roots; the reader is broken"

    assert_shipped(reachable, entries, "linked from a public page")
  end

  test "every tracked page under docs/ is in the tarball", %{entries: entries} do
    pages = tracked(["docs/"]) |> Enum.filter(&String.ends_with?(&1, ".md"))
    assert pages != [], "no tracked page under docs/; the population is broken"
    assert_shipped(MapSet.new(pages), entries, "tracked under docs/")
  end

  test "every ExDoc extra is in the tarball", %{entries: entries} do
    extras =
      Mix.Project.config()[:docs][:extras]
      |> Enum.map(fn
        {path, _opts} -> to_string(path)
        path -> to_string(path)
      end)

    assert extras != [], "no ExDoc extras configured; the population is broken"
    assert_shipped(MapSet.new(extras), entries, "an ExDoc extra")
  end

  defp assert_shipped(wanted, entries, why) do
    missing = wanted |> Enum.reject(&MapSet.member?(entries, &1)) |> Enum.sort()

    assert missing == [],
           "#{length(missing)} page(s) #{why} absent from the built tarball " <>
             "(#{MapSet.size(entries)} entries): #{inspect(missing)}"
  end

  # Follows every relative link from `pending`, page to page, returning every path seen. A
  # target that is not a tracked file is still returned: a dead link is a page the tarball
  # cannot carry, and the assertion names it.
  defp reachable_pages([], seen), do: seen

  defp reachable_pages([page | rest], seen) do
    targets =
      case File.read(Path.join(@root, page)) do
        {:ok, text} ->
          @relative_link
          |> Regex.scan(text, capture: :all_but_first)
          |> Enum.map(fn [target] -> resolve(page, target) end)
          |> Enum.reject(&MapSet.member?(seen, &1))
          |> Enum.uniq()

        {:error, _} ->
          []
      end

    reachable_pages(rest ++ targets, Enum.into(targets, seen))
  end

  # A relative link resolves against the linking page's directory, as a browser resolves it.
  defp resolve(page, target) do
    page |> Path.dirname() |> Path.join(target) |> Path.expand("/") |> String.trim_leading("/")
  end

  defp tracked(prefixes) do
    {out, 0} = System.cmd("git", ["ls-files", "-z", "--" | prefixes], cd: @root)
    out |> String.split(<<0>>, trim: true)
  end

  # The built artefact: `mix hex.build` into `dir`, the outer plain tar opened, and the
  # entries of `contents.tar.gz` listed. Nothing is published; the tarball is deleted with
  # the directory. A subprocess, not `Mix.Task.run/2`: Mix prunes the code path to the
  # project's own dependencies once the project loads (`prune_code_paths`, default true), and
  # the Hex archive is not one, so the task is not loadable from inside the test VM (measured:
  # `Mix.NoTaskError`). The subprocess is the command a release runs; the environment is
  # pinned to `test` and is harmless either way, since `hex.build` compiles nothing.
  defp tarball_entries(dir) do
    out = Path.join(dir, "package.tar")

    {log, 0} =
      System.cmd("mix", ["hex.build", "-o", out],
        cd: @root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert File.exists?(out), "mix hex.build wrote no tarball:\n#{log}"

    :ok = :erl_tar.extract(String.to_charlist(out), [{:cwd, String.to_charlist(dir)}])
    contents = Path.join(dir, "contents.tar.gz")
    {:ok, names} = :erl_tar.table(String.to_charlist(contents), [:compressed])
    names |> Enum.map(&to_string/1) |> MapSet.new()
  end
end
