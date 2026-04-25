defmodule VestaboardAgent.Agents.SportsAgentTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Agents.SportsAgent

  defp capture_dispatches do
    parent = self()
    fn text -> send(parent, {:dispatched, text}); {:ok, %{}} end
  end

  defp sports_returning(results) do
    ref = :counters.new(1, [])

    fn _ctx ->
      idx = :counters.get(ref, 1)
      :counters.add(ref, 1, 1)
      Enum.at(results, idx, List.last(results))
    end
  end

  defp ctx(overrides \\ []) do
    Map.merge(%{dispatch_fn: capture_dispatches(), refresh_ms: 0}, Map.new(overrides))
  end

  describe "name/0 and keywords/0" do
    test "name is 'sports'" do
      assert SportsAgent.name() == "sports"
    end

    test "keywords includes score, nfl, nba, mlb, nhl" do
      kw = SportsAgent.keywords()
      assert "score" in kw
      assert "nfl" in kw
      assert "nba" in kw
      assert "mlb" in kw
      assert "nhl" in kw
    end
  end

  describe "handle/2 — one-shot (no live game)" do
    test "returns {:ok, :done} for a final game" do
      sports_fn = sports_returning([{:ok, %{text: "KC 27 BUF 24\nFINAL", live: false}}])
      assert {:ok, :done} = SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))
    end

    test "dispatches the score text to the board" do
      sports_fn = sports_returning([{:ok, %{text: "SCORE TEXT", live: false}}])
      SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))
      assert_received {:dispatched, "SCORE TEXT"}
    end

    test "returns {:error, reason} when tool fails" do
      sports_fn = sports_returning([{:error, :no_games}])
      assert {:error, :no_games} = SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))
    end
  end

  describe "handle/2 — live game refresh loop" do
    test "returns {:ok, :done} after game ends" do
      sports_fn =
        sports_returning([
          {:ok, %{text: "LIVE 14-7 Q2 5:00", live: true}},
          {:ok, %{text: "FINAL 14-7", live: false}}
        ])

      assert {:ok, :done} = SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))
    end

    test "dispatches on initial fetch and on each refresh" do
      sports_fn =
        sports_returning([
          {:ok, %{text: "LIVE", live: true}},
          {:ok, %{text: "STILL LIVE", live: true}},
          {:ok, %{text: "FINAL", live: false}}
        ])

      SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))

      dispatched = for _ <- 1..3, do: assert_receive({:dispatched, _})
      assert length(dispatched) == 3
    end

    test "stops loop and dispatches final score when game ends" do
      sports_fn =
        sports_returning([
          {:ok, %{text: "LIVE", live: true}},
          {:ok, %{text: "FINAL 27-24", live: false}}
        ])

      SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))

      assert_receive {:dispatched, "LIVE"}
      assert_receive {:dispatched, "FINAL 27-24"}
      refute_receive {:dispatched, _}
    end

    test "stops loop silently on refresh error" do
      sports_fn =
        sports_returning([
          {:ok, %{text: "LIVE", live: true}},
          {:error, :no_games}
        ])

      assert {:ok, :done} = SportsAgent.handle("nfl score", ctx(sports_fn: sports_fn))
    end
  end

  describe "sport/team parsing — league keywords" do
    test "detects nba from league keyword" do
      {league, _} = capture_ctx("show me nba scores")
      assert league == "nba"
    end

    test "detects mlb from league keyword" do
      {league, _} = capture_ctx("mlb scores today")
      assert league == "mlb"
    end

    test "detects nhl from league keyword" do
      {league, _} = capture_ctx("nhl scores tonight")
      assert league == "nhl"
    end

    test "defaults to nfl when no sport or team keyword in prompt" do
      {league, _} = capture_ctx("show me the score")
      assert league == "nfl"
    end
  end

  describe "sport/team parsing — team name lookup" do
    test "resolves 'Suns' to NBA/PHX" do
      {league, team} = capture_ctx("latest Suns score")
      assert league == "nba"
      assert team == "PHX"
    end

    test "resolves 'Chiefs' to NFL/KC" do
      {league, team} = capture_ctx("show me the Chiefs score")
      assert league == "nfl"
      assert team == "KC"
    end

    test "resolves 'Lakers' to NBA/LAL" do
      {league, team} = capture_ctx("Lakers game tonight")
      assert league == "nba"
      assert team == "LAL"
    end

    test "resolves 'Yankees' to MLB/NYY" do
      {league, team} = capture_ctx("Yankees score")
      assert league == "mlb"
      assert team == "NYY"
    end

    test "resolves 'Penguins' to NHL/PIT" do
      {league, team} = capture_ctx("Penguins score")
      assert league == "nhl"
      assert team == "PIT"
    end

    test "resolves multi-word 'Red Sox' to MLB/BOS" do
      {league, team} = capture_ctx("Red Sox score today")
      assert league == "mlb"
      assert team == "BOS"
    end

    test "resolves 'Trail Blazers' to NBA/POR" do
      {league, team} = capture_ctx("Trail Blazers game")
      assert league == "nba"
      assert team == "POR"
    end

    test "team name takes precedence over league keyword in sport detection" do
      # 'Suns' should win over a hypothetical conflicting keyword
      {league, team} = capture_ctx("Suns nba score")
      assert league == "nba"
      assert team == "PHX"
    end
  end

  describe "sport/team parsing — abbreviation fallback" do
    test "extracts all-caps abbreviation when no team name matches" do
      {_league, team} = capture_ctx("show me the KC score")
      assert team == "KC"
    end

    test "team is nil when neither team name nor abbreviation found" do
      {_league, team} = capture_ctx("show me the score")
      assert team == nil
    end
  end

  # Runs handle/2 with a capturing sports_fn and returns {league, team}
  defp capture_ctx(prompt) do
    table = :ets.new(:capture, [:set, :public])

    sports_fn = fn ctx ->
      :ets.insert(table, {:ctx, ctx})
      {:ok, %{text: "SCORE", live: false}}
    end

    SportsAgent.handle(prompt, ctx(sports_fn: sports_fn))
    [{:ctx, captured}] = :ets.lookup(table, :ctx)
    {captured.league, captured.team}
  end
end
