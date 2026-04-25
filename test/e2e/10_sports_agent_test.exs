defmodule VestaboardAgent.E2E.SportsAgentTest do
  use VestaboardAgent.E2ECase

  alias VestaboardAgent.{Dispatcher, Tools.Sports}

  # Live score data changes by the minute, so these tests assert on structure
  # (team abbreviations, score patterns, board constraints) rather than exact
  # values. Any game may or may not be in progress when the suite runs.

  describe "Sports tool — direct dispatch" do
    test "NFL scoreboard dispatches non-empty board text" do
      case Sports.run(%{sport: "football", league: "nfl"}) do
        {:ok, %{text: text}} ->
          {:ok, _} = Dispatcher.dispatch(text)
          board = Dispatcher.last_board()
          assert board != nil
          assert board.text != "", "Sports tool produced empty board text"

        {:error, :no_games} ->
          # No NFL games today — acceptable outside the season
          :ok
      end
    end

    test "NBA scoreboard dispatches non-empty board text" do
      case Sports.run(%{sport: "basketball", league: "nba"}) do
        {:ok, %{text: text}} ->
          {:ok, _} = Dispatcher.dispatch(text)
          board = Dispatcher.last_board()
          assert board != nil
          assert board.text != ""

        {:error, :no_games} ->
          :ok
      end
    end

    test "board output fits within 6 rows of 22 columns" do
      case Sports.run(%{sport: "football", league: "nfl"}) do
        {:ok, %{text: text}} ->
          {:ok, _} = Dispatcher.dispatch(text)
          result = %{
            prompt: "sports tool direct",
            display_result: {:ok, :done},
            last_board: Dispatcher.last_board(),
            elapsed_ms: 0,
            timestamp: DateTime.utc_now()
          }

          assert_line_lengths(result, 22)
          assert length(result.last_board.grid) == 6
          assert Enum.all?(result.last_board.grid, &(length(&1) == 22))

        {:error, :no_games} ->
          :ok
      end
    end

    test "league label appears in board text" do
      case Sports.run(%{sport: "football", league: "nfl"}) do
        {:ok, %{text: text}} ->
          {:ok, _} = Dispatcher.dispatch(text)
          board = Dispatcher.last_board()
          assert String.contains?(board.text, "NFL"),
                 "Expected 'NFL' in board text, got: #{inspect(board.text)}"

        {:error, :no_games} ->
          :ok
      end
    end
  end

  describe "SportsAgent — prompt routing" do
    test "'show nfl scores' routes to SportsAgent and updates the board" do
      result = e2e_display("show nfl scores")

      # Agent always returns {:ok, :done} — it dispatches directly
      assert result.display_result == {:ok, :done},
             "Expected {:ok, :done}, got: #{inspect(result.display_result)}"
    end

    test "'show nba scores' routes to SportsAgent and updates the board" do
      result = e2e_display("show nba scores")
      assert result.display_result == {:ok, :done},
             "Expected {:ok, :done}, got: #{inspect(result.display_result)}"
    end

    test "'latest Suns score' resolves to NBA/PHX and always shows something" do
      # 'Suns' → @team_lookup → NBA/PHX.
      # The tool now always dispatches: live score, scheduled game, next game
      # time, or a "no games found" fallback — never an error.
      result = e2e_display("latest Suns score")

      assert result.display_result == {:ok, :done},
             "Expected {:ok, :done}, got: #{inspect(result.display_result)}"

      assert result.last_board != nil, "Board should always be updated"
      assert result.last_board.text != "", "Board text should be non-empty"

      assert String.contains?(result.last_board.text, "NBA"),
             "Expected 'NBA' in board text, got: #{inspect(result.last_board.text)}"

      assert_line_lengths(result, 22)
    end

    test "'Chiefs score' resolves to NFL/KC and always shows something" do
      result = e2e_display("Chiefs score")

      assert result.display_result == {:ok, :done},
             "Expected {:ok, :done}, got: #{inspect(result.display_result)}"

      assert result.last_board != nil
      assert result.last_board.text != ""

      assert String.contains?(result.last_board.text, "NFL"),
             "Expected 'NFL' in board text, got: #{inspect(result.last_board.text)}"

      assert_line_lengths(result, 22)
    end
  end
end
