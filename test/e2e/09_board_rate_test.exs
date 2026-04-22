defmodule VestaboardAgent.E2E.BoardRateTest do
  use VestaboardAgent.E2ECase

  @moduletag timeout: 300_000

  alias VestaboardAgent.{Client, Dispatcher}

  @rows 6
  @cols 22

  # How many frames to send in each test.
  @frame_count 10

  # Per-frame poll settings.
  @poll_interval_ms 50
  @poll_timeout_ms 10_000

  describe "board rate limiting" do
    @tag timeout: 300_000
    test "measures round-trip latency for sequential frames" do
      frames = build_frames(@frame_count)

      timings =
        Enum.map(Enum.with_index(frames), fn {grid, i} ->
          t0 = System.monotonic_time(:millisecond)

          result = Dispatcher.dispatch(grid)
          dispatch_ms = System.monotonic_time(:millisecond) - t0

          {confirmed, confirm_ms} =
            case result do
              {:ok, _} -> poll_until_match(grid, @poll_timeout_ms)
              {:error, reason} -> {:error_skipped, 0}
            end

          total_ms = System.monotonic_time(:millisecond) - t0

          IO.puts("  frame #{i}: dispatch=#{dispatch_ms}ms confirm=#{confirm_ms}ms total=#{total_ms}ms #{if confirmed == :ok, do: "✓", else: "✗ (#{confirmed})"}")

          %{frame: i, dispatch_ms: dispatch_ms, confirm_ms: confirm_ms, total_ms: total_ms, confirmed: confirmed}
        end)

      print_stats(timings)

      confirmed_count = Enum.count(timings, &(&1.confirmed == :ok))
      assert confirmed_count == @frame_count,
        "Only #{confirmed_count}/#{@frame_count} frames were confirmed by read-back within #{@poll_timeout_ms}ms"
    end

    @tag timeout: 300_000
    test "measures how quickly the board accepts rapid-fire posts" do
      frames = build_frames(@frame_count)

      {timings, error_count} =
        Enum.reduce(Enum.with_index(frames), {[], 0}, fn {grid, i}, {acc, errs} ->
          t0 = System.monotonic_time(:millisecond)
          result = Dispatcher.dispatch(grid)
          elapsed = System.monotonic_time(:millisecond) - t0

          case result do
            {:ok, _} ->
              IO.puts("  rapid frame #{i}: #{elapsed}ms OK")
              {[%{frame: i, ms: elapsed, status: :ok} | acc], errs}

            {:error, :rate_limited} ->
              IO.puts("  rapid frame #{i}: #{elapsed}ms RATE LIMITED")
              {[%{frame: i, ms: elapsed, status: :rate_limited} | acc], errs + 1}

            {:error, reason} ->
              IO.puts("  rapid frame #{i}: #{elapsed}ms ERROR #{inspect(reason)}")
              {[%{frame: i, ms: elapsed, status: {:error, reason}} | acc], errs + 1}
          end
        end)

      timings = Enum.reverse(timings)
      ok_count = Enum.count(timings, &(&1.status == :ok))

      IO.puts("\n  [rate] #{ok_count}/#{@frame_count} accepted, #{error_count} rejected")
      IO.puts("  [rate] min=#{Enum.min_by(timings, & &1.ms).ms}ms max=#{Enum.max_by(timings, & &1.ms).ms}ms")

      # Not asserting a specific rate — this test is diagnostic. Just confirm
      # at least the first frame went through.
      assert ok_count >= 1, "No frames were accepted at all"
    end
  end

  # ---------------------------------------------------------------------------
  # Frame generation
  # ---------------------------------------------------------------------------

  # Generates @frame_count distinct grids. Each frame lights up one row with a
  # unique color code so they are visually and numerically distinct.
  defp build_frames(count) do
    blank = List.duplicate(List.duplicate(0, @cols), @rows)

    Enum.map(0..(count - 1), fn i ->
      # Color cycles through a set of Vestaboard codes (non-zero, non-black).
      # Codes 63–69 are safe (red, orange, yellow, green, blue, violet, white).
      color = rem(i, 7) + 63
      row_index = rem(i, @rows)

      List.replace_at(blank, row_index, List.duplicate(color, @cols))
    end)
  end

  # ---------------------------------------------------------------------------
  # Polling
  # ---------------------------------------------------------------------------

  defp poll_until_match(expected_grid, timeout_ms, elapsed \\ 0) do
    case Client.read() do
      {:ok, ^expected_grid} ->
        {:ok, elapsed}

      {:ok, _other} when elapsed < timeout_ms ->
        Process.sleep(@poll_interval_ms)
        poll_until_match(expected_grid, timeout_ms, elapsed + @poll_interval_ms)

      {:ok, _other} ->
        {:timeout, elapsed}

      {:error, reason} ->
        {{:read_error, reason}, elapsed}
    end
  end

  # ---------------------------------------------------------------------------
  # Stats reporting
  # ---------------------------------------------------------------------------

  defp print_stats(timings) do
    totals = Enum.map(timings, & &1.total_ms) |> Enum.sort()
    confirms = timings |> Enum.filter(&(&1.confirmed == :ok)) |> Enum.map(& &1.confirm_ms) |> Enum.sort()

    IO.puts("\n  ── Dispatch + confirm latency (#{length(totals)} frames) ──")
    IO.puts("  total  min=#{Enum.min(totals)}ms  max=#{Enum.max(totals)}ms  p50=#{percentile(totals, 50)}ms  p95=#{percentile(totals, 95)}ms")

    if confirms != [] do
      IO.puts("  confirm min=#{Enum.min(confirms)}ms  max=#{Enum.max(confirms)}ms  p50=#{percentile(confirms, 50)}ms  p95=#{percentile(confirms, 95)}ms")
    end

    suggested = percentile(totals, 95)
    IO.puts("  ── Suggested min frame interval: ~#{suggested}ms (p95 round-trip) ──")
  end

  defp percentile(sorted_list, p) do
    n = length(sorted_list)
    idx = round(p / 100 * (n - 1))
    Enum.at(sorted_list, idx)
  end
end
