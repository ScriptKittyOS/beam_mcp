# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Credo's defaults, plus the two security-relevant warnings its defaults leave off, on the code
# that ships (lib/). UnsafeToAtom: an atom made from input the package does not control can
# exhaust the atom table, which the BEAM never collects -- the denial of service a wire-facing
# library must not offer. LeakyEnvironment: a spawned command inheriting the parent's
# environment, secrets included. Neither is enabled on test/ or tools/, whose System.cmd calls
# and fixture atoms are the harness's, not the package's. Every other check is Credo's default,
# run in --strict by the gate.
%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {Credo.Check.Warning.UnsafeToAtom, [files: %{included: ["lib/"]}]},
          {Credo.Check.Warning.LeakyEnvironment, [files: %{included: ["lib/"]}]}
        ]
      }
    }
  ]
}
