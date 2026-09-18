# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ProvenanceTest do
  @moduledoc """
  The README's provenance claim, pinned in its two halves. (1) The workflow that attests the
  release tarball exists, runs on release tags, pins the attestation action by commit, asks for
  the permissions an attestation needs, and verifies against the bytes hex.pm serves -- pinned
  by source, because the run itself happens on GitHub and is quoted in the slice record, not
  here. (2) `mix hex.build` is byte-deterministic and the tarball's SHA-256 is the "Package
  checksum" hex prints -- measured here, twice, because the whole binding rests on it: if this
  ever fails, the attestation describes bytes hex.pm does not serve.
  """
  use ExUnit.Case, async: false

  @workflow ".github/workflows/provenance.yml"

  test "the provenance workflow attests the tarball on a release tag, pinned by commit, and verifies against hex.pm" do
    wf = File.read!(@workflow)
    assert wf =~ ~r/^\s+tags: \["v\*"\]/m
    assert wf =~ ~r/uses: actions\/attest-build-provenance@[0-9a-f]{40}$/m
    assert wf =~ ~r/id-token: write/
    assert wf =~ ~r/attestations: write/
    assert wf =~ "mix hex.build"
    assert wf =~ "https://repo.hex.pm/tarballs/beam_mcp-"
    assert wf =~ "gh attestation verify"
    # The workflow attests; the owner publishes. Its comment says so by name, so the check is
    # on the lines that run: none may invoke hex.publish.
    publishing =
      wf |> String.split("\n") |> Enum.reject(&String.starts_with?(String.trim(&1), "#"))

    assert Enum.filter(publishing, &String.contains?(&1, "hex.publish")) == []
  end

  test "the README and the page make the claim, and the page names the 0.5.0 measurement" do
    readme = File.read!("README.md")
    page = File.read!("docs/provenance.md")
    assert readme =~ "the tarball hex.pm serves is attested"
    assert readme =~ "gh attestation verify"
    assert page =~ "c95d7b2a2a9113bfa5641ea8a42de1e30af8dc813cadb70c76297aa54290911e"
    assert Mix.Project.config()[:docs][:extras] |> Enum.member?("docs/provenance.md")
  end

  @tag timeout: 120_000
  test "mix hex.build is byte-deterministic, and the tarball's sha256 is the package checksum hex prints" do
    dir =
      Path.join(System.tmp_dir!(), "beam_mcp-provenance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    try do
      [{sha_a, printed_a}, {sha_b, printed_b}] =
        for n <- [:a, :b] do
          out = Path.join(dir, "#{n}.tar")
          {log, 0} = System.cmd("mix", ["hex.build", "-o", out], stderr_to_stdout: true)
          [_, printed] = Regex.run(~r/Package checksum: ([0-9a-f]{64})/, log)
          sha = :crypto.hash(:sha256, File.read!(out)) |> Base.encode16(case: :lower)
          {sha, printed}
        end

      assert sha_a == printed_a, "the tarball's sha256 is not the package checksum hex printed"
      assert sha_a == sha_b, "two builds of one tree gave two tarballs: #{sha_a} / #{sha_b}"
      assert printed_a == printed_b
    after
      File.rm_rf!(dir)
    end
  end
end
