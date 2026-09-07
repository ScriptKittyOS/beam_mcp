Compiling 5 files (.ex)
Generated beam_mcp app
Running ExUnit with seed: 284997, max_cases: 64

....

  1) test methods available at both eras tools/call and shutdown are served under either declared revision (BeamMCP.ReadmeClaimsTest)
     test/beam_mcp/readme_claims_test.exs:182
     tools/call at 2026-07-28
     code: for version <- [@modern, @legacy] do
     stacktrace:
       test/beam_mcp/readme_claims_test.exs:191: anonymous fn/1 in BeamMCP.ReadmeClaimsTest."test methods available at both eras tools/call and shutdown are served under either declared revision"/1
       (elixir 1.19.2) lib/enum.ex:1688: Enum."-map/2-lists^map/1-1-"/2
       test/beam_mcp/readme_claims_test.exs:185: (test)

.

  2) test the session is tracked, not enforced every method is served bare, tools/call included, and tools/call reaches dispatch (BeamMCP.ReadmeClaimsTest)
     test/beam_mcp/readme_claims_test.exs:139
     no initialize, no _meta, no session -- and it executes. This is the package's stated contract, not an accident, and the README says refusing unestablished callers is the host's job. Pinned so that neither adding nor removing that refusal can happen silently.
     code: assert r["result"]["isError"] == false,
     stacktrace:
       test/beam_mcp/readme_claims_test.exs:151: (test)

.
Finished in 0.03 seconds (0.03s async, 0.00s sync)
8 tests, 2 failures
