defmodule VestaboardAgent.E2E.BoardRateTest do
  @moduledoc """
  Benchmarks real-world Vestaboard write and read-back latency.

  Results as of 2026-04-22 (192.168.0.105, firmware Vestaboard/v4.1.0):

    Write time (network round-trip):  10–43ms  (p50 ~19ms)
    Read-back confirmation:           200–250ms (p50 ~200ms)
    Total round-trip:                 271–326ms (p95 ~326ms)
    Suggested min frame interval:     ~326ms

  No rate limiting observed at 1s between frames. Zero-delay rapid-fire
  appeared to crash/reboot the board — avoid sending faster than ~500ms.
  """

  use VestaboardAgent.E2ECase

  @moduletag timeout: 300_000

  alias VestaboardAgent.Clients.Vestaboard, as: Client

  @rows 6
  @cols 22
  @frame_count 10
  @poll_interval_ms 50
  @poll_timeout_ms 15_000

  # Vestaboard color codes that are NOT printable ASCII (>= 128 or == 0).
  # Codes 71-87 are safe: they're above printable ASCII so Elixir won't
  # display them as charlists, and they're valid board color codes.
  @frame_colors [71, 72, 73, 74, 75, 76, 77, 78]

  describe "board rate limiting" do
    test "measures round-trip latency for sequential frames" do
      frames = build_frames(@frame_count)

      IO.puts("\n  [rate] sending #{@frame_count} frames sequentially, polling for read-back...")

      timings =
        Enum.map(Enum.with_index(frames), fn {grid, i} ->
          t0 = System.monotonic_time(:millisecond)

          case Client.write_characters(grid) do
            {:ok, _} ->
              dispatch_ms = System.monotonic_time(:millisecond) - t0
              {confirmed, confirm_ms} = poll_until_match(grid, @poll_timeout_ms)
              total_ms = System.monotonic_time(:millisecond) - t0

              status = if confirmed == :ok, do: "✓", else: "✗ (#{confirmed})"
              IO.puts("  frame #{i}: write=#{dispatch_ms}ms  confirm=#{confirm_ms}ms  total=#{total_ms}ms  #{status}")

              %{frame: i, write_ms: dispatch_ms, confirm_ms: confirm_ms, total_ms: total_ms, ok: confirmed == :ok}

            {:error, reason} ->
              elapsed = System.monotonic_time(:millisecond) - t0
              IO.puts("  frame #{i}: WRITE ERROR #{inspect(reason)} (#{elapsed}ms)")
              %{frame: i, write_ms: elapsed, confirm_ms: 0, total_ms: elapsed, ok: false}
          end
        end)

      print_stats(timings)

      ok_count = Enum.count(timings, & &1.ok)
      assert ok_count == @frame_count,
        "Only #{ok_count}/#{@frame_count} frames confirmed by read-back within #{@poll_timeout_ms}ms"
    end

    test "measures raw write throughput with 1s between frames" do
      frames = build_frames(@frame_count)

      IO.puts("\n  [rate] sending #{@frame_count} writes with 1s between frames...")

      timings =
        Enum.map(Enum.with_index(frames), fn {grid, i} ->
          if i > 0, do: Process.sleep(1_000)
          t0 = System.monotonic_time(:millisecond)
          result = Client.write_characters(grid)
          elapsed = System.monotonic_time(:millisecond) - t0

          status =
            case result do
              {:ok, _}              -> :ok
              {:error, :rate_limited} -> :rate_limited
              {:error, reason}      -> {:error, reason}
            end

          IO.puts("  write #{i}: #{elapsed}ms  #{inspect(status)}")
          %{frame: i, ms: elapsed, status: status}
        end)

      ok_count      = Enum.count(timings, &(&1.status == :ok))
      limited_count = Enum.count(timings, &(&1.status == :rate_limited))
      error_count   = Enum.count(timings, &(match?({:error, _}, &1.status)))

      IO.puts("\n  [rate] accepted=#{ok_count}  rate_limited=#{limited_count}  errors=#{error_count}")

      all_ms = Enum.map(timings, & &1.ms) |> Enum.sort()
      IO.puts("  [rate] write time  min=#{Enum.min(all_ms)}ms  max=#{Enum.max(all_ms)}ms  p50=#{percentile(all_ms, 50)}ms")

      assert ok_count >= 1, "No frames were accepted at all"
    end
  end

  # ---------------------------------------------------------------------------
  # Frame generation — each frame fills one row with a distinct color
  # ---------------------------------------------------------------------------

  defp build_frames(count) do
    blank = List.duplicate(List.duplicate(0, @cols), @rows)

    Enum.map(0..(count - 1), fn i ->
      color = Enum.at(@frame_colors, rem(i, length(@frame_colors)))
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
  # Stats
  # ---------------------------------------------------------------------------

  defp print_stats(timings) do
    totals   = timings |> Enum.map(& &1.total_ms) |> Enum.sort()
    confirms = timings |> Enum.filter(& &1.ok) |> Enum.map(& &1.confirm_ms) |> Enum.sort()

    IO.puts("\n  ── Sequential round-trip stats (#{length(totals)} frames) ──")
    IO.puts("  total    min=#{Enum.min(totals)}ms  max=#{Enum.max(totals)}ms  p50=#{percentile(totals, 50)}ms  p95=#{percentile(totals, 95)}ms")

    if confirms != [] do
      IO.puts("  confirm  min=#{Enum.min(confirms)}ms  max=#{Enum.max(confirms)}ms  p50=#{percentile(confirms, 50)}ms  p95=#{percentile(confirms, 95)}ms")
    end

    suggested = percentile(totals, 95)
    IO.puts("  ── Suggested min frame interval: ~#{suggested}ms ──")
  end

  defp percentile(sorted, p) do
    n   = length(sorted)
    idx = round(p / 100 * (n - 1))
    Enum.at(sorted, idx)
  end
end
