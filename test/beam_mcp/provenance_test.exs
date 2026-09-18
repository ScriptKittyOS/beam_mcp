# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ProvenanceTest do
  @moduledoc """
  The README's provenance claim, pinned in its parts. (1) The workflow that attests the release
  tarball exists, runs on release tags, builds with the canonical script, pins the attestation
  action by commit, scopes the attestation permissions to its job, and verifies against the
  bytes hex.pm serves -- by source, because the run happens on GitHub. (2) The tarball
  `tools/release_tarball.sh` builds is canonical BY STRUCTURE, not by luck: every entry mode
  644, the entry order the sorted expansion of `files:`, the tarball's sha256 the checksum hex
  prints -- so the same commit gives the same bytes on any machine. A review lane measured the
  two ways a working-tree build is not: on-disk modes (umask) and readdir order (filesystem).
  Building twice on one machine proved nothing about that, which is why this test does not.
  """
  use ExUnit.Case, async: false

  @workflow ".github/workflows/provenance.yml"

  test "the provenance workflow attests the canonical tarball on a release tag, pinned by commit, and verifies against hex.pm" do
    wf = File.read!(@workflow)
    assert wf =~ ~r/^\s+tags: \["v\*"\]/m
    assert wf =~ ~r/^\s+workflow_dispatch:/m
    assert wf =~ "tools/release_tarball.sh"
    assert wf =~ ~r/uses: actions\/attest-build-provenance@[0-9a-f]{40}$/m
    assert wf =~ ~r/subject-path: beam_mcp-/
    assert wf =~ "https://repo.hex.pm/tarballs/beam_mcp-"
    assert wf =~ "gh attestation verify"

    # The attestation permissions are the attesting job's, not the workflow's: the top-level
    # block grants read only, and id-token/attestations appear inside a job's block.
    [top | _] = String.split(wf, ~r/^jobs:/m)
    assert top =~ ~r/^permissions:\n  contents: read\n/m
    refute top =~ "id-token"
    assert wf =~ ~r/^    permissions:\n(      [a-z-]+: [a-z]+\n)*      id-token: write\n/m
    assert wf =~ ~r/^      attestations: write$/m

    # The workflow attests; the owner publishes. Its comment says so by name, so the check is
    # on the lines that run: none may invoke hex.publish.
    publishing =
      wf |> String.split("\n") |> Enum.reject(&String.starts_with?(String.trim(&1), "#"))

    assert Enum.filter(publishing, &String.contains?(&1, "hex.publish")) == []
  end

  test "the README and the page make the claim, and the page names the measurements" do
    readme = File.read!("README.md")
    page = File.read!("docs/provenance.md")
    assert readme =~ "tools/release_tarball.sh"
    assert readme =~ "gh attestation verify"
    assert page =~ "tools/release_tarball.sh"
    assert page =~ "tar.umask=022"
    assert Mix.Project.config()[:docs][:extras] |> Enum.member?("docs/provenance.md")
  end

  @tag timeout: 120_000
  test "the canonical tarball is canonical by structure: every entry 644, the order the sorted expansion of files:, the sha256 the checksum hex prints" do
    dir =
      Path.join(System.tmp_dir!(), "beam_mcp-provenance-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    out = Path.join(dir, "canonical.tar")

    try do
      # HEAD's tree, the way CI and the publisher build it. The lock's dependencies are the
      # tree's own (the script resolves them; here they are already fetched).
      {log, 0} =
        System.cmd("bash", ["tools/release_tarball.sh", "HEAD", out], stderr_to_stdout: true)

      [_, printed] = Regex.run(~r/Package checksum: ([0-9a-f]{64})/, log)
      sha = :crypto.hash(:sha256, File.read!(out)) |> Base.encode16(case: :lower)
      assert sha == printed, "the tarball's sha256 is not the package checksum hex printed"

      {:ok, outer} = :erl_tar.extract(String.to_charlist(out), [:memory])
      {_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)
      {:ok, inner} = :erl_tar.table({:binary, contents}, [:compressed, :verbose])

      entries =
        for {name, :regular, _size, _mtime, mode, _uid, _gid} <- inner,
            do: {to_string(name), mode}

      modes = entries |> Enum.map(fn {_, m} -> Bitwise.band(m, 0o777) end) |> Enum.uniq()
      assert modes == [0o644], "entry modes are #{inspect(modes, base: :octal)}, not 644 alone"

      # The order Hex gives a glob is Path.wildcard's, sorted; the tarball's is the globs' in
      # files: order. A directory in files: would be readdir order and fail here on some machine.
      expected =
        Mix.Project.config()[:package][:files]
        |> Enum.flat_map(fn glob -> glob |> Path.wildcard() |> Enum.sort() end)

      assert Enum.map(entries, &elem(&1, 0)) == expected
      assert length(expected) >= 39
    after
      File.rm_rf!(dir)
    end
  end
end
