# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

# A hot reload of a module replaces the beam `mix test --cover` instrumented, and cover then
# cannot collect that module at all (measured: `Observed` and `Tracer` vanished from the table
# once the reload tests landed). Under cover those tests are excluded -- the gate runs the
# plain suite, where they run -- so the coverage record keeps the modules they reload.
cover? = Code.ensure_loaded?(:cover) and :cover.modules() != []
ExUnit.start(exclude: if(cover?, do: [:hot_reload], else: []))
