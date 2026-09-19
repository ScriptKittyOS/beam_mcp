# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ExportControlTest do
  # The README's export-control paragraph, held to the tree and to the citations that exist.
  #
  # A compliance reader relies on this paragraph, so every claim in it about the package is
  # checked against the code here, and its citations are held to the sections that say what
  # the paragraph says they say -- the first draft cited 15 CFR 740.13(e), which is
  # "[Reserved]" in the current text (the provision it meant is 742.15(b)); this census
  # refuses that citation so it cannot come back. The caveat sentence is held too: the
  # paragraph says it is not legal advice and not counsel-reviewed until the maintainer
  # records otherwise.
  use ExUnit.Case, async: true

  alias BeamMCP.Boundary
  alias BeamMCP.Connectome.Canonical

  @readme File.read!("README.md")

  defp section do
    [_, rest] = String.split(@readme, "\n## Export control\n", parts: 2)
    rest |> String.split(~r/\n## /, parts: 2) |> hd()
  end

  test "the paragraph is present, with its caveat, its two citations, and no stale one" do
    text = section()
    assert text =~ "not legal advice"
    assert text =~ "has not been reviewed by counsel"
    assert text =~ "15 CFR 734.7(a)(4)"
    assert text =~ "734.7(b)"
    assert text =~ "742.15(b)"

    refute text =~ "740.13",
           "740.13(e) is [Reserved] in the current eCFR; the provision is 742.15(b)"

    assert text =~ ~r/posting on the Internet on\s+sites available to the public/
    assert text =~ "Downstream integrators remain responsible"
  end

  test "what it says about the package is what the code shows: one digest site, the SHA-2 set, no other crypto call, no key" do
    text = section()
    assert text =~ "It contains no encryption."
    assert text =~ "SHA-256 by default, SHA-384 or SHA-512 by option"
    assert Canonical.algorithms() == [:sha256, :sha384, :sha512]
    assert text =~ "at one call site"
    assert length(Boundary.hits(~r/:crypto\.hash\(/)) == 1
    assert Boundary.hits(~r/:crypto\.(?!hash\()/) == []
    assert text =~ "holds no key material"
    assert text =~ "Apache License 2.0"
    assert File.exists?("LICENSES/Apache-2.0.txt")
  end
end
