defmodule VestaboardAgent.E2E.SnakeTest do
  use VestaboardAgent.E2ECase

  @moduletag timeout: 300_000

  alias VestaboardAgent.{Agents.SnakeAgent, Dispatcher}

  # Runs a real snake game (real LLM + real board) for a fixed number of moves,
  # wrapping the dispatch function to count successes and failures.

  describe "snake game" do
    test "dispatches every frame without skipping" do
      ok_count = :counters.new(1, [])
      err_count = :counters.new(1, [])
      errors = Agent.start_link(fn -> [] end) |> elem(1)

      counting_dispatch = fn grid ->
        result = Dispatcher.dispatch(grid)
        case result do
          {:ok, _} ->
            :counters.add(ok_count, 1, 1)
          {:error, reason} ->
            :counters.add(err_count, 1, 1)
            Agent.update(errors, &[reason | &1])
        end
        result
      end

      {:ok, :done} = SnakeAgent.handle("play snake", %{
        dispatch_fn: counting_dispatch,
        max_moves: 8
      })

      ok = :counters.get(ok_count, 1)
      err = :counters.get(err_count, 1)
      skipped = Agent.get(errors, & &1)

      IO.puts("\n  [snake e2e] frames ok=#{ok} skipped=#{err}")
      if err > 0, do: IO.puts("  [snake e2e] skip reasons: #{inspect(skipped)}")

      assert err == 0,
        "#{err} frame(s) were skipped due to dispatch errors: #{inspect(skipped)}"

      # 8 move frames + 1 game-over = 9 total; at minimum the game-over always fires
      assert ok >= 2,
        "Expected at least 2 successful dispatches, got #{ok}"

      # Final board must show the GAME OVER screen
      board = Dispatcher.last_board()
      assert board != nil, "last_board/0 was nil after snake game"
      assert String.contains?(board.text, "GAME") or String.contains?(board.text, "SCORE"),
        "Expected GAME OVER on board, got: #{inspect(board.text)}"
    end
  end
end
