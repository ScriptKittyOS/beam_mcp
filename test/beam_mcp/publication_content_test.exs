# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PublicationContentTest do
  @moduledoc """
  The package's code and tests describe the package. They do not name who consumes it, and they
  do not carry identifiers from the board that plans it.

  Two anchors over one population -- every tracked file under `lib/` and `test/`, from
  `git ls-files`, never a hand list:

  1. No file contains a board identifier. The pattern names the board's key. That key is
     already in the repository's history and in the tracked slice records, so this file states
     no new fact. The gate's `messages` step reads the same pattern over the branch's commit
     messages; this test reads it over the tree. Two populations, one pattern, each spelled
     where its population is read.
  2. No file names a consumer. The names are the ones on the README's consumer line -- the one
     place the project description allows them -- and this file asserts that line still carries
     each name, so the list here cannot outlive the sentence it is derived from.

  The asymmetry, stated: the gate polices PATHS (which files may be tracked) and this file
  polices CONTENT (what two directories' files may say), and neither sees the other's
  population. A leak in a file outside `lib/` and `test/` is not this file's to catch.

  Written red: on the tree it was added to, one moduledoc named a consumer and one test file
  carried three board identifiers.
  """
  use ExUnit.Case, async: true

  @board_id ~r/SCR-[0-9]+/

  # README.md:351, quoted so a change to the sentence fails here rather than silently
  # orphaning the list below.
  @consumer_line "Consumers today: Ultraviolet, and Trinity as a candidate under its own evaluation."
  @consumers ["Ultraviolet", "Trinity"]

  test "no tracked file under lib/ or test/ carries a board identifier" do
    hits =
      for file <- tracked(["lib/", "test/"]),
          {line, n} <- numbered_lines(file),
          Regex.match?(@board_id, line),
          do: "#{file}:#{n}"

    assert hits == [], "board identifiers in: #{inspect(hits)}"
  end

  test "no tracked file under lib/ or test/ names a consumer" do
    readme = File.read!("README.md")
    assert String.contains?(readme, @consumer_line), "the README consumer line moved"
    for name <- @consumers, do: assert(String.contains?(@consumer_line, name))

    hits =
      for file <- tracked(["lib/", "test/"]),
          file != Path.relative_to_cwd(__ENV__.file),
          {line, n} <- numbered_lines(file),
          Enum.any?(@consumers, &String.contains?(line, &1)),
          do: "#{file}:#{n}"

    assert hits == [], "consumer names in: #{inspect(hits)}"
  end

  defp tracked(prefixes) do
    {out, 0} = System.cmd("git", ["ls-files", "-z", "--" | prefixes])
    out |> String.split(<<0>>, trim: true)
  end

  defp numbered_lines(file) do
    file |> File.read!() |> String.split("\n") |> Enum.with_index(1)
  end
end
