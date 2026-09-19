# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.GovernanceTest do
  # The governance record and the workflows' posture, held to the tree.
  #
  # What the OpenSSF Scorecard reads of a repository is mostly its tree: CODEOWNERS, a
  # security policy, a licence, workflows whose actions are pinned by commit SHA (a tag can be
  # moved; a SHA cannot) and whose token permissions are the least the job needs. This census
  # holds those on every push, so the Scorecard's number is a measurement of a tree that
  # keeps them, not a snapshot of one that happened to. The governance and succession pages
  # are held to what the tree and the platform actually show -- one maintainer, an org-owned
  # repository, no off-account archive -- so they state, and do not promise.
  use ExUnit.Case, async: true

  @workflows Path.wildcard(".github/workflows/*.yml") |> Enum.sort()
  @owner_login "HackTuah"

  test "CODEOWNERS names the maintainer for every path, and the maintainer is the merger of record" do
    assert File.exists?("CODEOWNERS")

    lines =
      File.read!("CODEOWNERS")
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))

    assert ["* @" <> @owner_login] = lines
  end

  test "the governance and succession pages exist, ship, and are documented" do
    for page <- ["docs/governance.md", "docs/succession.md"] do
      assert File.exists?(page), page
      assert page in Mix.Project.config()[:docs][:extras], "#{page} is not an ex_doc extra"
      shipped = Mix.Project.config()[:package][:files] |> Enum.flat_map(&Path.wildcard/1)
      assert page in shipped, "#{page} is not in the tarball"
    end
  end

  test "the governance page states what the tree shows: one maintainer, the gate, the lanes, the tier rule, the merge word" do
    text = File.read!("docs/governance.md")

    for phrase <- [
          "one maintainer",
          "tools/gate.sh",
          "CONVENTIONS.md",
          "CODEOWNERS",
          "Scorecard",
          "bus factor"
        ] do
      assert text =~ phrase, "governance.md does not say #{inspect(phrase)}"
    end
  end

  test "the succession page states the archive is not in place and what a successor needs" do
    text = File.read!("docs/succession.md")

    for phrase <- ["off-account archive", "not in place", "hex.pm", "ScriptKittyOS"] do
      assert text =~ phrase, "succession.md does not say #{inspect(phrase)}"
    end
  end

  test "every workflow pins every action by a 40-hex commit SHA, with the version it stands for beside it" do
    assert length(@workflows) >= 4

    for wf <- @workflows,
        {line, n} <- Enum.with_index(String.split(File.read!(wf), "\n"), 1),
        line =~ ~r/^\s*-?\s*uses:/ do
      assert line =~ ~r/uses:\s+\S+@[0-9a-f]{40}\s+#\s*v?\d/,
             "#{wf}:#{n} is not pinned by SHA with its version beside it: #{String.trim(line)}"
    end
  end

  test "every workflow declares top-level permissions, and write permissions live on the job that needs them" do
    for wf <- @workflows do
      text = File.read!(wf)
      assert text =~ ~r/^permissions:/m, "#{wf} declares no top-level permissions"
      [top, jobs] = String.split(text, ~r/^jobs:/m, parts: 2)
      refute top =~ ~r/^(\s+\S+|permissions):\s*write/m, "#{wf} grants write at the top level"

      # A job may write only where the record says one does: provenance's attestation and
      # the Scorecard's SARIF upload. Any other job block that says write is a finding.
      writers = Enum.map(["provenance.yml", "scorecard.yml"], &(".github/workflows/" <> &1))

      unless wf in writers do
        refute jobs =~ ~r/^\s+\S+:\s*write/m, "#{wf} grants write on a job"
      end
    end
  end

  test "the Scorecard workflow runs on push to main and weekly, publishes, and holds only the permissions the action documents" do
    wf = ".github/workflows/scorecard.yml"
    assert wf in @workflows
    text = File.read!(wf)
    assert text =~ ~r/branches:\s*\[\s*main\s*\]/ or text =~ ~r/branches:\n\s+- main/
    assert text =~ ~r/schedule:/
    assert text =~ "ossf/scorecard-action@"
    assert text =~ "publish_results: true"
    assert text =~ ~r/^permissions:\s*read-all/m
    assert text =~ ~r/security-events:\s*write/
    assert text =~ ~r/id-token:\s*write/
    refute text =~ ~r/contents:\s*write/
  end
end
