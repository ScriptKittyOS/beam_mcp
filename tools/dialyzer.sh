#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Dialyzer over the package's beams, with the OTP binary and a PLT that survives sessions.
#
#     tools/dialyzer.sh          builds the PLT if this OTP/Elixir pair has none, then runs
#                                dialyzer over _build/dev/lib/beam_mcp/ebin; prints one line
#
# WHY THE OTP BINARY AND NOT `mix dialyzer`: dialyxir was declined for its transitive
# dependencies (CX-055); the invocation below is the one archived per slice since 010. WHY
# THE PLT IS WHERE IT IS: it lived in one session's scratchpad under /tmp and was rebuilt or
# forgotten on the next (G-013); now it is `_build/dialyzer/<otp>-<elixir>.plt`, keyed by the
# pair that built it, because a PLT built for one OTP is wrong for another, and CI caches that
# directory by the same key. The cost is the cold build, measured here on the first run of
# every seat and printed on the line so the number is never a memory.
#
# `-pa` with Elixir's ebin on both calls: without it dialyzer crashes in elixir_erl:debug_info
# reading Elixir's own beams (measured in 010; the decoder was not on its path).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
elixir_ebin=$(elixir -e 'IO.puts(:code.lib_dir(:elixir, :ebin))' 2>/dev/null)
[ -d "$elixir_ebin" ] || { echo "dialyzer FAIL: cannot find Elixir's ebin"; exit 1; }
# THE KEY IS THE EXACT VERSIONS, NOT THE PAIR. Dialyzer refuses a PLT written by another
# dialyzer app version ("Old PLT file"), and `--no_check_plt` does not bypass that; keyed by
# the OTP major, a runner image's patch bump (28.1 -> 28.5 carries dialyzer 5.4 -> 5.4.0.1,
# measured by a review lane) turned the same file name into a permanent failure. So the name
# carries erts and dialyzer's own versions plus Elixir's, and a PLT that still reads as old is
# rebuilt once rather than reported as "0 warnings, FAIL".
otp=$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null)
erts=$(erl -noshell -eval 'io:format("~s", [erlang:system_info(version)]), halt().' 2>/dev/null)
dzv=$(erl -noshell -eval 'application:load(dialyzer), {ok, V} = application:get_key(dialyzer, vsn), io:format("~s", [V]), halt().' 2>/dev/null)
elx=$(elixir -e 'IO.puts(System.version())' 2>/dev/null)
# The PLT is the pair's plus the lock's dependencies (their beams, so a callback behaviour
# like Plug and a called module like Jason are known, not "unknown"); the file name carries
# the versions and the lock's hash, so a bumped dependency builds a fresh one.
lock=$(sha256sum mix.lock | cut -c1-12)
plt="_build/dialyzer/otp${otp}-erts${erts}-dialyzer${dzv}-elixir${elx}-lock${lock}.plt"
mkdir -p _build/dialyzer
# Always the current beams: standalone, a stale _build/dev read as "0 warnings" over a planted
# type error (a review lane measured it). The gate compiles --force before this step anyway.
mix compile >/dev/null 2>&1 || { echo "dialyzer FAIL: mix compile failed"; exit 1; }
built=""
build_plt() {
  t0=$(date +%s)
  logger_ebin=$(elixir -e 'IO.puts(:code.lib_dir(:logger, :ebin))' 2>/dev/null)
  rm -f "$plt"
  out=$(dialyzer -pa "$elixir_ebin" --build_plt --output_plt "$plt" --apps erts kernel stdlib crypto tools "$elixir_ebin" "$logger_ebin" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && [ ! -f "$plt" ]; then
    echo "dialyzer FAIL: the PLT could not be built (exit $rc)"; printf '%s\n' "$out" | tail -5; exit 1
  fi
  # shellcheck disable=SC2046
  dialyzer -pa "$elixir_ebin" --add_to_plt --plt "$plt" $(ls -d _build/dev/lib/*/ebin | grep -v '/beam_mcp/') >/dev/null 2>&1 || true
  t1=$(date +%s)
  built="${built}PLT built cold in $((t1 - t0)) s; "
}
[ -f "$plt" ] || build_plt
analyse() { dialyzer -pa "$elixir_ebin" --plt "$plt" --no_check_plt _build/dev/lib/beam_mcp/ebin 2>&1; }
t0=$(date +%s)
out=$(analyse); rc=$?
if printf '%s\n' "$out" | grep -qE 'Old PLT file|could not read|not a PLT'; then
  # A PLT this dialyzer will not read (the key should prevent it; if it happens, rebuild once
  # and say so rather than fail on "0 warnings").
  built="stale PLT rebuilt; "
  build_plt
  out=$(analyse); rc=$?
fi
t1=$(date +%s)
key="otp${otp}/erts${erts}/dialyzer${dzv}/elixir${elx}"
n=$(printf '%s\n' "$out" | grep -cE '^[^ ].*\.ex:[0-9]+:' || true)
if [ "$rc" -eq 0 ] || printf '%s\n' "$out" | grep -q 'done (passed successfully)'; then
  echo "dialyzer ok: 0 warnings over $(ls _build/dev/lib/beam_mcp/ebin/*.beam | wc -l) beams in $((t1 - t0)) s (${built}PLT ${key})"
  exit 0
fi
if [ "$n" -eq 0 ]; then
  echo "dialyzer FAIL: dialyzer exited $rc with no warning lines -- not an analysis result (${built}PLT ${key})"
  printf '%s\n' "$out" | tail -8 | sed 's/^/  /'; exit 1
fi
echo "dialyzer FAIL: $n warning(s) in $((t1 - t0)) s (${built}PLT ${key})"
printf '%s\n' "$out" | grep -vE '^\s*$|Checking|Proceeding|Compiling|done in|^ *Unknown' | head -40
exit 1
