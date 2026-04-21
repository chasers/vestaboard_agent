defmodule VestaboardAgent.Tools.ClockTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Tools.Clock

  @noon ~U[2024-06-15 12:00:00Z]
  @midnight ~U[2024-01-01 00:00:00Z]
  @morning ~U[2024-03-20 09:05:00Z]
  @evening ~U[2024-12-31 23:59:00Z]

  test "name/0 returns clock" do
    assert Clock.name() == "clock"
  end

  test "run/1 returns {:ok, string}" do
    assert {:ok, text} = Clock.run(%{now: @noon})
    assert is_binary(text)
  end

  test "formats noon as 12:00 PM" do
    {:ok, text} = Clock.run(%{now: @noon})
    assert String.starts_with?(text, "12:00 PM")
  end

  test "formats midnight as 12:00 AM" do
    {:ok, text} = Clock.run(%{now: @midnight})
    assert String.starts_with?(text, "12:00 AM")
  end

  test "formats morning time correctly" do
    {:ok, text} = Clock.run(%{now: @morning})
    assert String.starts_with?(text, "9:05 AM")
  end

  test "formats evening time correctly" do
    {:ok, text} = Clock.run(%{now: @evening})
    assert String.starts_with?(text, "11:59 PM")
  end

  test "formats date with day of week, month, day, and year" do
    {:ok, text} = Clock.run(%{now: @noon})
    [_time, date] = String.split(text, "\n")
    assert date == "SAT JUN 15 2024"
  end

  test "all days of week render correctly" do
    days = [
      {~U[2024-06-17 12:00:00Z], "MON"},
      {~U[2024-06-18 12:00:00Z], "TUE"},
      {~U[2024-06-19 12:00:00Z], "WED"},
      {~U[2024-06-20 12:00:00Z], "THU"},
      {~U[2024-06-21 12:00:00Z], "FRI"},
      {~U[2024-06-22 12:00:00Z], "SAT"},
      {~U[2024-06-23 12:00:00Z], "SUN"}
    ]

    for {dt, expected_dow} <- days do
      {:ok, text} = Clock.run(%{now: dt})
      [_, date] = String.split(text, "\n")
      assert String.starts_with?(date, expected_dow), "expected #{expected_dow} for #{dt}"
    end
  end

  test "all months render correctly" do
    months = ~w(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)

    for {month_name, month_num} <- Enum.with_index(months, 1) do
      dt = %DateTime{
        year: 2024,
        month: month_num,
        day: 1,
        hour: 12,
        minute: 0,
        second: 0,
        time_zone: "Etc/UTC",
        zone_abbr: "UTC",
        utc_offset: 0,
        std_offset: 0
      }

      {:ok, text} = Clock.run(%{now: dt})
      [_, date] = String.split(text, "\n")
      assert String.contains?(date, month_name), "expected #{month_name} in #{date}"
    end
  end

  test "defaults to current time when no :now in context" do
    assert {:ok, text} = Clock.run(%{})
    assert is_binary(text)
    assert String.contains?(text, "\n")
  end

  test "defaults to current time when context is empty map" do
    assert {:ok, _text} = Clock.run()
  end

  test "output contains a newline separating time and date" do
    {:ok, text} = Clock.run(%{now: @noon})
    assert [_time, _date] = String.split(text, "\n")
  end
end
