Compiling 5 files (.ex)
Generated beam_mcp app
Running ExUnit with seed: 281372, max_cases: 64

....

  1) test the dependency requirement the README hands a consumer it does not span the wire break this release documents (BeamMCP.ReadmeClaimsTest)
     test/beam_mcp/readme_claims_test.exs:80
     the README no longer contains the sentence this test pins:
       {:beam_mcp, "~> 0.2"}
     Either the claim moved and this test must move with it, or the claim was deleted and so should this test. A test pinning a sentence nobody makes is worse than no test, because it reads as coverage.
     code: claims(~s({:beam_mcp, "~> 0.2"}))
     stacktrace:
       test/beam_mcp/readme_claims_test.exs:81: (test)

...
Finished in 0.03 seconds (0.03s async, 0.00s sync)
8 tests, 1 failure
