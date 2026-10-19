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
    assert wf =~ ~r/uses: actions\/attest-build-provenance@[0-9a-f]{40} # v[0-9.]+$/m
    assert wf =~ ~r/subject-path: beam_mcp-/
    assert wf =~ "https://repo.hex.pm/tarballs/beam_mcp-"
    assert wf =~ "gh attestation verify"

    # On a tag a digest mismatch fails the run; off a tag the tarball is nobody's release and
    # the same mismatch is NOT MEASURED -- a manual run must be able to be green, or it proves
    # nothing (a review lane found the proof run red by construction). Pinned by BEHAVIOUR: the
    # step's script is lifted from the file and run, with a curl that answers 200 and bytes
    # that do not match, under each ref type. A shape pin cannot enumerate shapes (two lanes'
    # plants passed one); running the step is the exact pin, and it costs a fake curl.
    # Four cases: a 200 with the wrong bytes, and a 404, each on and off a tag. The fake curl
    # answers the code it is given; the fake gh is on the same PATH so no plant can reach the
    # real one (a lane found the real gh reached under a plant that skipped the mismatch).
    for {on_tag, code, expected_exit, expected_line} <- [
          {"false", "200", 0, "NOT MEASURED: hex.pm serves"},
          {"true", "200", 1, "FAIL: the published tarball is not the bytes"},
          {"false", "404", 0, "NOT MEASURED: hex.pm answered 404"},
          {"true", "404", 1, "FAIL: hex.pm answered 404"}
        ] do
      {out, exit} = run_hex_step(wf, on_tag, code)
      assert exit == expected_exit, "ON_TAG=#{on_tag} code=#{code}: exit #{exit}, output:\n#{out}"
      assert out =~ expected_line
      # On a 200 the fake's bytes were read and hashed: the step compared real digests.
      if code == "200",
        do:
          assert(
            out =~
              "published sha256 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
          )

      refute out =~ "fake gh reached"
    end

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

  # The hex.pm step's `run:` block, its two `${{ steps.build.outputs.* }}` expressions substituted,
  # run by bash with a fake curl on PATH that writes a file and answers 200 -- so the bytes
  # published (sha256 of "hello") never equal the built digest given, and the mismatch branch is
  # the one exercised. A fake gh is never reached on a mismatch.
  defp run_hex_step(wf, on_tag, code) do
    [_, rest] =
      String.split(wf, "verify the attestation against the bytes hex.pm serves for this version",
        parts: 2
      )

    [_, rest] = String.split(rest, "run: |\n", parts: 2)
    [block | _] = String.split(rest, "\n      - ", parts: 2)

    script =
      block
      |> String.replace("${{ steps.build.outputs.version }}", "0.5.0")
      |> String.replace("${{ steps.build.outputs.sha256 }}", "deadbeef")

    dir = Path.join(System.tmp_dir!(), "beam_mcp-hexstep-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    curl = Path.join([dir, "bin", "curl"])

    File.write!(
      curl,
      "#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in -o) printf hello > \"$2\"; shift;; esac; shift; done; printf #{code}\n"
    )

    File.chmod!(curl, 0o755)
    gh = Path.join([dir, "bin", "gh"])
    File.write!(gh, "#!/bin/sh\necho \"fake gh reached: $*\"; exit 3\n")
    File.chmod!(gh, 0o755)
    File.write!(Path.join(dir, "step.sh"), script)

    try do
      System.cmd("bash", ["step.sh"],
        cd: dir,
        stderr_to_stdout: true,
        env: [
          {"PATH", Path.join(dir, "bin") <> ":" <> System.get_env("PATH")},
          {"ON_TAG", on_tag},
          {"GITHUB_REPOSITORY", "ScriptKittyOS/beam_mcp"},
          {"GH_TOKEN", "unused"}
        ]
      )
    after
      File.rm_rf!(dir)
    end
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
      # Under whatever Hex this machine has: the structure is the claim here, and the pin is
      # the next test's. RELEASE_HEX is the script's own override, set to the installed version.
      {log, 0} =
        System.cmd("bash", ["tools/release_tarball.sh", "HEAD", out],
          stderr_to_stdout: true,
          env: [{"RELEASE_HEX", installed_hex()}]
        )

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

      # The order is the Hex that built it, read from the build's own line. Up to Hex 2.5.1 a
      # glob's files came in Path.wildcard's order, sorted, and the globs in files: order (a
      # directory in files: would be readdir order and fail here on some machine). From Hex
      # 2.5.2 (hex_core 0.20) the tarball's entries are sorted by name whatever files: says --
      # measured 2026-10-19, the change that put this test red on every pull request.
      [_, hex] = Regex.run(~r/built with Hex ([0-9][0-9.]*)/, log)
      globbed = Enum.map(Mix.Project.config()[:package][:files], &Enum.sort(Path.wildcard(&1)))

      expected =
        if Version.compare(hex, "2.5.2") == :lt,
          do: Enum.concat(globbed),
          else: globbed |> Enum.concat() |> Enum.sort()

      assert Enum.map(entries, &elem(&1, 0)) == expected
      assert length(expected) >= 39

      # A non-ASCII name is written in the machine's locale encoding (Erlang's native name
      # encoding is latin1 under LC_ALL=C, utf8 otherwise -- a review lane measured two
      # checksums for one such file), so the canonical bytes hold only while every name is ASCII.
      non_ascii =
        Enum.reject(expected, fn name ->
          name == for(<<c <- name>>, c < 128, into: "", do: <<c>>)
        end)

      assert non_ascii == [], "packaged names that are not ASCII: #{inspect(non_ascii)}"
    after
      File.rm_rf!(dir)
    end
  end

  test "the release script builds only with the Hex tools/hex-version names, and says how to get it" do
    # The pin is what makes the publisher's checksum and CI's attested one the same bytes. A
    # version no machine has stands in for "not the pinned one", so this holds on any machine.
    pinned = "tools/hex-version" |> File.read!() |> String.trim()
    assert Version.parse!(pinned)

    out =
      Path.join(System.tmp_dir!(), "beam_mcp-hexpin-#{System.unique_integer([:positive])}.tar")

    {log, status} =
      System.cmd("bash", ["tools/release_tarball.sh", "HEAD", out],
        stderr_to_stdout: true,
        env: [{"RELEASE_HEX", "0.0.1"}]
      )

    assert status == 3
    assert log =~ "this build needs Hex 0.0.1"
    assert log =~ "mix local.hex 0.0.1 --force"
    refute File.exists?(out)

    # Without the override the script reads tools/hex-version itself: on a machine whose Hex is
    # the pinned one it builds and says so; on any other it refuses naming the pinned version.
    # Either way the version in the outcome is the file's, which a substring match on the
    # script's text could not show.
    {log, status} =
      System.cmd("bash", ["tools/release_tarball.sh", "HEAD", out],
        stderr_to_stdout: true,
        env: [{"RELEASE_HEX", nil}]
      )

    if installed_hex() == pinned do
      assert status == 0
      assert log =~ "built with Hex #{pinned}"
    else
      assert status == 3
      assert log =~ "this build needs Hex #{pinned}"
    end

    File.rm(out)

    script = File.read!("tools/release_tarball.sh")
    assert script =~ "tools/hex-version"
    assert File.read!(".github/workflows/provenance.yml") =~ "< tools/hex-version"
  end

  defp installed_hex do
    {info, 0} = System.cmd("mix", ["hex.info"], stderr_to_stdout: true)
    [_, version] = Regex.run(~r/^Hex: +([0-9][0-9.]*)/m, info)
    version
  end
end
