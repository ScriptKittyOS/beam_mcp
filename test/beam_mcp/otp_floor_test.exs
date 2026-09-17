# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.OTPFloorTest do
  @moduledoc """
  The OTP floor is enforced at compile time, in `mix.exs`, because Mix has no key for a minimum
  OTP the way it has `elixir:` for Elixir. `BeamMCP.MixProject.check_otp!/1` is the guard's pure
  half: it takes the release string `:erlang.system_info(:otp_release)` returns and raises, with
  a named message, below the floor. `project/0` calls it with the running release, so a
  below-floor build fails to compile.

  This file demonstrates the raise and its message on this OTP (a synthetic below-floor string),
  and pins the floor number and the reason equal across `mix.exs` and the README. It does NOT
  compile the package under a real below-floor OTP — none is installed here; 023's CI matrix
  floor leg runs the package on the floor release itself, and a real below-floor compile is
  named as a gap in the slice record.
  """
  use ExUnit.Case, async: true

  @floor 27

  test "the floor is #{@floor}, and check_otp!/1 accepts it and every release above it" do
    assert BeamMCP.MixProject.otp_floor() == @floor
    assert BeamMCP.MixProject.check_otp!("#{@floor}") == :ok
    assert BeamMCP.MixProject.check_otp!("#{@floor + 1}") == :ok
    assert BeamMCP.MixProject.check_otp!("29") == :ok
  end

  test "a below-floor release raises with a message that names the floor, the version found, and why" do
    e = assert_raise Mix.Error, fn -> BeamMCP.MixProject.check_otp!("26") end

    # The floor, and the version actually found.
    assert e.message =~ "#{@floor}"
    assert e.message =~ "26"

    # The reason, not just the number: the keyed process_info read the tracer uses, added in
    # OTP 26.2, and that 27 is the oldest release the project supports -- stated as what is true
    # today (the suite runs on OTP 28; the floor leg of the CI matrix is 023's), not as a
    # measurement that does not exist yet. A floor without a reason gets raised by the next
    # person who finds it inconvenient.
    assert e.message =~ "keyed process_info"
    assert e.message =~ "26.2 is the hard requirement"
    assert e.message =~ "oldest release this project supports"
    assert e.message =~ "Today the suite is run on OTP 28"
  end

  test "the running OTP is at or above the floor (this build compiled, so the guard passed)" do
    running = List.to_integer(:erlang.system_info(:otp_release))
    assert running >= @floor
    assert BeamMCP.MixProject.check_otp!(:erlang.system_info(:otp_release)) == :ok
  end

  test "mix.exs and the README name the same floor and the same reason, so neither drifts" do
    mix = File.read!("mix.exs")
    readme = File.read!("README.md")

    # The floor integer is one number, in the attribute and in the README prose.
    assert mix =~ "@otp_floor #{@floor}"
    assert readme =~ "OTP #{@floor}"

    # And the guard is wired into project/0 against the running release: pinned by source,
    # because no below-floor OTP is installed here to fail a real compile (named as a gap in
    # the slice record; 023's CI floor leg compiles on the floor release itself).
    assert mix =~ "check_otp!(:erlang.system_info(:otp_release))"

    # The reason travels with it: the keyed process_info read and its OTP version.
    for text <- [mix, readme] do
      assert text =~ "process_info"
      assert text =~ "26.2"
    end
  end
end
