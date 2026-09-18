# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.SecurityPolicyTest do
  @moduledoc """
  `SECURITY.md` held to the tree. The intake it names is this repository's private advisory
  form, derived from the project's source URL rather than typed twice; the commitments carry
  their numbers; the supported-versions table names the minor `mix.exs` ships; the severity
  rubric and the CVE path are present and say what they must. A policy that drifts from the
  package it describes is worse than none, because it reads as a promise.
  """
  use ExUnit.Case, async: true

  @policy File.read!("SECURITY.md")

  test "the intake is this repository's private advisory form, and no public issue" do
    source = Mix.Project.config()[:source_url]
    assert @policy =~ "#{source}/security/advisories/new"
    assert @policy =~ "do not open a public issue"
  end

  test "a report that cannot use the form has an address, and the policy ships with the package" do
    assert @policy =~ "ayla@scriptkittyos.com"
    assert "SECURITY.md" in Mix.Project.config()[:package][:files]
    assert "SECURITY.md" in Mix.Project.config()[:docs][:extras]
    # ...and in the Policy group of the sidebar, where a hexdocs reader looks (G-074).
    {_, policy_group} =
      Mix.Project.config()[:docs][:groups_for_extras] |> List.keyfind(:Policy, 0)

    assert "SECURITY.md" =~ policy_group
  end

  test "the commitments carry their numbers, and promise no bounty and no deadline" do
    assert @policy =~ ~r/Acknowledgement within 7 days/
    assert @policy =~ ~r/assessment within 30 days/
    assert @policy =~ "no paid bounty"
    assert @policy =~ "no guaranteed fix deadline"
  end

  test "the supported-versions table names the minor mix.exs ships, and nothing newer" do
    shipped = Version.parse!(Mix.Project.config()[:version])
    assert @policy =~ "| `#{shipped.major}.#{shipped.minor}.x` | yes |"

    # Every row's version, parsed; none may be newer than the shipped minor (a lane's plant
    # added `1.0.x` and `0.7.x` rows past a refute that looked only at minor + 1).
    rows = Regex.scan(~r/^\| `(\d+)\.(\d+)\.x` \|/m, @policy)
    assert rows != []

    newer =
      for [_, major, minor] <- rows,
          {String.to_integer(major), String.to_integer(minor)} > {shipped.major, shipped.minor},
          do: "#{major}.#{minor}.x"

    assert newer == [], "rows newer than the shipped minor: #{inspect(newer)}"

    # Exactly one row is `yes`: the shipped minor. "Earlier minors are not backported" is the
    # file's own sentence, and an older row marked yes would contradict it silently (G-074).
    yes_rows = Regex.scan(~r/^\| `([0-9.]+x)` \| yes \|/m, @policy) |> Enum.map(&Enum.at(&1, 1))

    assert yes_rows == ["#{shipped.major}.#{shipped.minor}.x"],
           "rows marked yes: #{inspect(yes_rows)}"
  end

  test "the severity rubric has four levels in the package's terms, each with its fix window" do
    # The rows themselves are read -- `| **Level** | meaning | window |` -- not the file at
    # large: a first cut asserted "dispatch" anywhere and was satisfied by the In-scope section,
    # so four generic rows with no window cell passed (a lane's plant).
    rows =
      Regex.scan(~r/^\| \*\*(Critical|High|Medium|Low)\*\* \| (.+?) \| (.+?) \|$/m, @policy)
      |> Map.new(fn [_, level, meaning, window] -> {level, {meaning, window}} end)

    assert Map.keys(rows) |> Enum.sort() == ~w(Critical High Low Medium)

    # And no fifth level: every bold-level row in the file is one of the four (G-074).
    levels =
      Regex.scan(~r/^\| \*\*(\w+)\*\* \|/m, @policy) |> Enum.map(&Enum.at(&1, 1)) |> Enum.sort()

    assert levels == ~w(Critical High Low Medium), "severity rows: #{inspect(levels)}"

    # Each meaning names this package's surface -- the words the In-scope section uses for it.
    terms = %{
      "Critical" => ["dispatch", "advertise"],
      "High" => ["revision", "wire"],
      "Medium" => ["bound", "workaround"],
      "Low" => ["error code", "documented"]
    }

    for {level, {meaning, window}} <- rows do
      for term <- terms[level] do
        assert meaning =~ term, "the #{level} row's meaning does not mention #{inspect(term)}"
      end

      assert String.length(String.trim(window)) > 10, "the #{level} row has no fix window"
    end

    # The Critical window is a patch of the supported minor with nothing else in it -- the one
    # place this file and the supported-versions caveat ("a fix may arrive in a release that
    # also carries a wire change") would otherwise contradict a reporter.
    {_, critical_window} = rows["Critical"]
    assert critical_window =~ "patch release of the supported minor carrying only the fix"
  end

  test "the CVE path names GitHub as the CNA and the advisory as where it starts" do
    # The sentence, not the abbreviation: a regex on "GitHub ... CNA" passed a negation and
    # failed a true sentence without the parenthetical (a lane's two plants).
    # Through the consequence, so a negation appended after the clause fails too; \s+ between
    # words, so a reflow of the paragraph does not (G-074).
    assert @policy =~
             ~r/GitHub\s+is\s+a\s+CVE\s+Numbering\s+Authority(\s+\(CNA\))?\s+for\s+repositories\s+it\s+hosts,\s+so\s+a\s+CVE\s+is\s+requested\s+from\s+the\s+advisory\s+draft/

    assert @policy =~ ~r/published\s+from\s+this\s+repository's\s+GitHub\s+Security\s+Advisories/
    assert @policy =~ ~r/reaches\s+the\s+GitHub\s+Advisory\s+Database\s+and\s+OSV/
    assert @policy =~ "`mix hex.audit`"
  end

  test "the policy claims no regulatory status" do
    assert @policy =~ "claims no regulatory status"
  end
end
