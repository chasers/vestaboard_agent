defmodule VestaboardAgent.Tools.Clock do
  @moduledoc """
  Displays the current time on the board.

  Renders two lines: the time (HH:MM AM/PM) centered on row 2,
  and the date (DAY MON DD) centered on row 3.
  """

  @behaviour VestaboardAgent.Tool

  @impl true
  def name, do: "clock"

  @impl true
  def run(context \\ %{}) do
    now =
      case Map.get(context, :now) do
        %DateTime{} = dt -> dt
        _ -> DateTime.utc_now()
      end

    {:ok, format(now)}
  end

  defp format(dt) do
    time = format_time(dt)
    date = format_date(dt)
    "#{time}\n#{date}"
  end

  defp format_time(%DateTime{hour: hour, minute: minute}) do
    {h, ampm} = if hour >= 12, do: {hour - 12, "PM"}, else: {hour, "AM"}
    h = if h == 0, do: 12, else: h
    "#{h}:#{String.pad_leading(to_string(minute), 2, "0")} #{ampm}"
  end

  defp format_date(%DateTime{year: year, month: month, day: day} = dt) do
    dow = day_of_week(dt)
    mon = month_name(month)
    "#{dow} #{mon} #{day} #{year}"
  end

  defp day_of_week(dt) do
    case Date.day_of_week(DateTime.to_date(dt)) do
      1 -> "MON"
      2 -> "TUE"
      3 -> "WED"
      4 -> "THU"
      5 -> "FRI"
      6 -> "SAT"
      7 -> "SUN"
    end
  end

  defp month_name(month) do
    ~w(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)
    |> Enum.at(month - 1)
  end
end
