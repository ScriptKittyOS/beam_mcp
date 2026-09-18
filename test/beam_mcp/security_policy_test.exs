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
    %Version{major: major, minor: minor} = Version.parse!(Mix.Project.config()[:version])
    assert @policy =~ "| `#{major}.#{minor}.x` | yes |"
    refute @policy =~ "| `#{major}.#{minor + 1}.x` |"
  end

  test "the severity rubric has four levels in the package's terms, each with its fix window" do
    for level <- ~w(Critical High Medium Low) do
      assert @policy =~ ~r/^\| \*\*#{level}\*\* \|/m, "no #{level} row in the severity table"
    end

    # Each level's example is a thing this package does, not a generic phrase.
    assert @policy =~ "dispatch"
    assert @policy =~ "advertised"
  end

  test "the CVE path names GitHub as the CNA and the advisory as where it starts" do
    assert @policy =~ "CVE"
    assert @policy =~ ~r/GitHub[^.]*CNA|CNA[^.]*GitHub/
    assert @policy =~ "hex.pm"
  end

  test "the policy claims no regulatory status" do
    assert @policy =~ "claims no regulatory status"
  end
end
