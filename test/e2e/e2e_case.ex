defmodule VestaboardAgent.E2ECase do
  @moduledoc """
  Shared ExUnit.CaseTemplate for all E2E tests.

  Every module that `use VestaboardAgent.E2ECase` gets:
  - @moduletag :e2e
  - setup_all that guards required env vars
  - setup that clears conversation context, cancels stray jobs, and paces writes
  - Helper functions: e2e_display/1, assert_board_contains/2, assert_line_lengths/2,
    log_board_state/1, e2e_http_post/2, e2e_http_get/1

  On failure, assert_board_contains includes a structured diagnostic block so the
  output can be pasted directly into a Claude Code conversation for diagnosis.
  """

  use ExUnit.CaseTemplate

  alias VestaboardAgent.{Agents.ScheduleAgent, ConversationContext, Dispatcher}

  using do
    quote do
      @moduletag :e2e
      @moduletag timeout: 60_000
      import VestaboardAgent.E2ECase
    end
  end

  setup_all do
    required = ["VESTABOARD_LOCAL_API_KEY", "ANTHROPIC_API_KEY"]
    missing = Enum.filter(required, &(System.get_env(&1) == nil))

    unless Enum.empty?(missing) do
      raise """
      E2E suite requires these environment variables:
        #{Enum.join(missing, "\n  ")}

      Run: export VESTABOARD_LOCAL_API_KEY=... ANTHROPIC_API_KEY=... && mix test.e2e
      """
    end

    port = Application.get_env(:vestaboard_agent, :http_port, 4000)
    {:ok, http_base: "http://localhost:#{port}"}
  end

  setup context do
    ConversationContext.clear()

    ScheduleAgent.list()
    |> Enum.each(fn {name, _} -> ScheduleAgent.cancel(name) end)

    pace = System.get_env("E2E_PACE_MS", "1000") |> String.to_integer()
    if pace > 0, do: Process.sleep(pace)

    {:ok, http_base: context[:http_base]}
  end

  # ---------------------------------------------------------------------------
  # Display helpers
  # ---------------------------------------------------------------------------

  @doc "Run display/1 and return a result map for use with assert_board_* helpers."
  def e2e_display(prompt) do
    t0 = System.monotonic_time(:millisecond)
    result = VestaboardAgent.display(prompt)
    elapsed = System.monotonic_time(:millisecond) - t0

    %{
      prompt: prompt,
      display_result: result,
      last_board: Dispatcher.last_board(),
      elapsed_ms: elapsed,
      timestamp: DateTime.utc_now()
    }
  end

  @doc "Assert the decoded board text contains `expected` (string or regex)."
  def assert_board_contains(%{last_board: board} = result, expected) do
    text = (board && board.text) || ""

    matched =
      case expected do
        %Regex{} = r -> String.match?(text, r)
        s when is_binary(s) -> String.contains?(text, s)
      end

    unless matched do
      ExUnit.Assertions.flunk(format_failure(result, {:contains, expected}))
    end
  end

  @doc "Assert every non-empty line in the decoded board text is at most `max_len` chars."
  def assert_line_lengths(%{last_board: board} = result, max_len) do
    text = (board && board.text) || ""

    violations =
      text
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.filter(&(String.length(&1) > max_len))

    unless violations == [] do
      ExUnit.Assertions.flunk(
        format_failure(result, {:line_lengths, max_len, violations})
      )
    end
  end

  @doc "Log the board state without asserting. Always passes."
  def log_board_state(%{last_board: board, prompt: prompt, elapsed_ms: ms}) do
    text = (board && board.text) || "(no board state)"
    ExUnit.CaptureLog
    IO.puts("\n  [board] #{inspect(prompt)} → #{inspect(text)} (#{ms}ms)")
  end

  # ---------------------------------------------------------------------------
  # HTTP helpers
  # ---------------------------------------------------------------------------

  @doc "POST JSON to /chat. Returns the decoded response body map."
  def e2e_http_post(context, body) do
    base = context[:http_base] || "http://localhost:4000"
    Req.post!("#{base}/chat", json: body).body
  end

  @doc "GET /board. Returns the decoded response and status."
  def e2e_http_get(context) do
    base = context[:http_base] || "http://localhost:4000"
    resp = Req.get!("#{base}/board")
    {resp.status, resp.body}
  end

  # ---------------------------------------------------------------------------
  # Failure formatting
  # ---------------------------------------------------------------------------

  defp format_failure(%{prompt: prompt, display_result: dr, last_board: board, elapsed_ms: ms, timestamp: ts}, expectation) do
    text = (board && board.text) || "(nil)"
    grid_summary = board && grid_preview(board.grid)

    expectation_line =
      case expectation do
        {:contains, %Regex{} = r} -> "contains regex  #{inspect(r)}"
        {:contains, s} -> "contains        #{inspect(s)}"
        {:line_lengths, max, violations} ->
          "each line ≤ #{max} chars\nVIOLATIONS\n  #{Enum.join(violations, "\n  ")}"
      end

    """

    ═══════════════════════════════════════════════════════════
    E2E FAILURE
    Timestamp:   #{DateTime.to_iso8601(ts)}
    Elapsed:     #{ms} ms

    PROMPT SENT
      #{inspect(prompt)}

    EXPECTED
      #{expectation_line}

    ACTUAL BOARD TEXT
      #{inspect(text)}

    DISPLAY RESULT
      #{inspect(dr)}
    #{if grid_summary, do: "\nBOARD GRID (non-blank rows)\n#{grid_summary}", else: ""}
    ═══════════════════════════════════════════════════════════
    """
  end

  defp grid_preview(grid) do
    grid
    |> Enum.with_index()
    |> Enum.reject(fn {row, _i} -> Enum.all?(row, &(&1 == 0)) end)
    |> Enum.map(fn {row, i} -> "  row #{i}: #{inspect(row)}" end)
    |> Enum.join("\n")
  end
end
