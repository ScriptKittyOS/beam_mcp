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
  end

  test "the severity rubric has four levels in the package's terms, each with its fix window" do
    # The rows themselves are read -- `| **Level** | meaning | window |` -- not the file at
    # large: a first cut asserted "dispatch" anywhere and was satisfied by the In-scope section,
    # so four generic rows with no window cell passed (a lane's plant).
    rows =
      Regex.scan(~r/^\| \*\*(Critical|High|Medium|Low)\*\* \| (.+?) \| (.+?) \|$/m, @policy)
      |> Map.new(fn [_, level, meaning, window] -> {level, {meaning, window}} end)

    assert Map.keys(rows) |> Enum.sort() == ~w(Critical High Low Medium)

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
    assert @policy =~
             ~r/GitHub is a CVE\s+Numbering Authority( \(CNA\))? for repositories it hosts/

    assert @policy =~ ~r/published from this repository's GitHub Security\s+Advisories/
    assert @policy =~ ~r/reaches the GitHub Advisory Database and OSV/
    assert @policy =~ "`mix hex.audit`"
  end

  test "the policy claims no regulatory status" do
    assert @policy =~ "claims no regulatory status"
  end
end
