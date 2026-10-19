#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The running Erlang/OTP is at or above its line's patched floor (tools/otp-floors), or this
# refuses by name. The full version is read from the release's own OTP_VERSION file, not from
# `otp_release` (which is the major alone, so 28.1.1 and 28.5.0.8 both answer "28"). A line
# newer than every recorded one passes and says so; a line older than every recorded one, or a
# recorded line below its floor, is refused. Used by tools/gate.sh and by the FIPS workflow,
# which builds its OTP from source and runs no gate.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
floors="$root/tools/otp-floors"
have=$(erl -noshell -eval '
  R = erlang:system_info(otp_release),
  F = filename:join([code:root_dir(), "releases", R, "OTP_VERSION"]),
  {ok, B} = file:read_file(F),
  io:format("~s", [string:trim(B)]),
  halt().')
have=${have%%[!0-9.]*}
major=${have%%.*}
floor=$(awk -v m="$major" '$1 == m { print $2 }' "$floors")
newest=$(awk '$1 ~ /^[0-9]+$/ { print $1 }' "$floors" | sort -n | tail -1)
if [ -z "$floor" ]; then
  if [ "$major" -gt "$newest" ]; then
    echo "OTP $have: a line newer than every recorded floor (newest recorded: $newest); passes"
    exit 0
  fi
  echo "OTP $have: line $major has no patched release recorded in tools/otp-floors; refused"
  exit 1
fi
lowest=$(printf '%s\n%s\n' "$floor" "$have" | sort -V | head -1)
if [ "$lowest" = "$floor" ]; then
  echo "OTP $have: at or above the patched floor $floor for line $major"
else
  echo "OTP $have: below the patched floor $floor for line $major (CVE-2026-55737); refused"
  exit 1
fi
