Running ExUnit with seed: 301433, max_cases: 64

...............

  1) test the HTTP transport's README claims a refusal before the body read ends the connection, as the README now says (BeamMCP.ReadmeClaimsTest)
     test/beam_mcp/readme_claims_test.exs:576
     the README no longer contains the sentence this test pins:
       ends the connection, and says so
     Either the claim moved and this test must move with it, or the claim was deleted and so should this test. A test pinning a sentence nobody makes is worse than no test, because it reads as coverage.
     code: claims("ends the connection, and says so")
     stacktrace:
       test/beam_mcp/readme_claims_test.exs:581: (test)

.

  2) test the HTTP transport's README claims a forbidden x-mcp-header annotation is the host's fault, as the README now says (BeamMCP.ReadmeClaimsTest)
     test/beam_mcp/readme_claims_test.exs:533
     the README no longer contains the sentence this test pins:
       is the host's fault, not the caller's
     Either the claim moved and this test must move with it, or the claim was deleted and so should this test. A test pinning a sentence nobody makes is worse than no test, because it reads as coverage.
     code: claims("is the host's fault, not the caller's")
     stacktrace:
       test/beam_mcp/readme_claims_test.exs:537: (test)

..
Finished in 0.1 seconds (0.1s async, 0.00s sync)
20 tests, 2 failures
TEST_EXIT=2
