defmodule VestaboardAgent.Tools.SportsTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Tools.Sports

  defp make_game(overrides \\ []) do
    %{
      id: Keyword.get(overrides, :id, "1"),
      home: %{
        abbrev: Keyword.get(overrides, :home, "KC"),
        name: "Kansas City Chiefs",
        score: Keyword.get(overrides, :home_score, 27)
      },
      away: %{
        abbrev: Keyword.get(overrides, :away, "BUF"),
        name: "Buffalo Bills",
        score: Keyword.get(overrides, :away_score, 24)
      },
      status: Keyword.get(overrides, :status, :final),
      clock: Keyword.get(overrides, :clock, nil),
      period: Keyword.get(overrides, :period, nil),
      start_time: Keyword.get(overrides, :start_time, "2026-04-25T23:30:00Z")
    }
  end

  defp build_espn_event(g) do
    status_name =
      case g.status do
        :in_progress -> "STATUS_IN_PROGRESS"
        :final -> "STATUS_FINAL"
        :scheduled -> "STATUS_SCHEDULED"
      end

    %{
      "id" => g.id,
      "competitions" => [
        %{
          "date" => g.start_time,
          "status" => %{
            "type" => %{"name" => status_name},
            "displayClock" => g.clock,
            "period" => g.period
          },
          "competitors" => [
            %{
              "homeAway" => "home",
              "team" => %{"abbreviation" => g.home.abbrev, "displayName" => g.home.name},
              "score" => if(g.home.score, do: Integer.to_string(g.home.score), else: nil)
            },
            %{
              "homeAway" => "away",
              "team" => %{"abbreviation" => g.away.abbrev, "displayName" => g.away.name},
              "score" => if(g.away.score, do: Integer.to_string(g.away.score), else: nil)
            }
          ]
        }
      ]
    }
  end

  defp stub_sports(games) do
    fn ctx ->
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"events" => Enum.map(games, &build_espn_event/1)})
      end)

      Sports.run(Map.put(ctx, :plug, {Req.Test, __MODULE__}))
    end
  end

  test "name/0 returns sports" do
    assert Sports.name() == "sports"
  end

  test "returns {:ok, map} with text and live keys" do
    f = stub_sports([make_game(status: :final)])
    assert {:ok, %{text: text, live: false}} = f.(%{sport: "football", league: "nfl"})
    assert is_binary(text)
  end

  test "live is true for in-progress game" do
    f = stub_sports([make_game(status: :in_progress, clock: "4:32", period: 3)])
    assert {:ok, %{live: true}} = f.(%{sport: "football", league: "nfl"})
  end

  test "live is false for final game" do
    f = stub_sports([make_game(status: :final)])
    assert {:ok, %{live: false}} = f.(%{sport: "football", league: "nfl"})
  end

  test "live is false for scheduled game" do
    f = stub_sports([make_game(status: :scheduled, home_score: nil, away_score: nil)])
    assert {:ok, %{live: false}} = f.(%{sport: "football", league: "nfl"})
  end

  test "returns first game when no team filter" do
    games = [
      make_game(id: "1", home: "KC", away: "BUF", status: :in_progress, clock: "1:00", period: 4),
      make_game(id: "2", home: "DAL", away: "PHI", status: :final)
    ]

    f = stub_sports(games)
    assert {:ok, %{text: text}} = f.(%{sport: "football", league: "nfl"})
    assert String.contains?(text, "KC")
  end

  test "filters by home team abbreviation" do
    games = [
      make_game(id: "1", home: "KC", away: "BUF", status: :final),
      make_game(id: "2", home: "DAL", away: "PHI", status: :final)
    ]

    f = stub_sports(games)
    assert {:ok, %{text: text}} = f.(%{sport: "football", league: "nfl", team: "DAL"})
    assert String.contains?(text, "DAL")
    refute String.contains?(text, "KC")
  end

  test "filters by away team abbreviation" do
    games = [
      make_game(id: "1", home: "KC", away: "BUF", status: :final),
      make_game(id: "2", home: "DAL", away: "PHI", status: :final)
    ]

    f = stub_sports(games)
    assert {:ok, %{text: text}} = f.(%{sport: "football", league: "nfl", team: "PHI"})
    assert String.contains?(text, "PHI")
  end

  test "team filter is case-insensitive" do
    f = stub_sports([make_game(home: "KC", away: "BUF", status: :final)])
    assert {:ok, _} = f.(%{sport: "football", league: "nfl", team: "kc"})
  end

  test "returns no-games message when no games today and no team filter" do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"events" => []}) end)

    assert {:ok, %{text: text, live: false}} =
             Sports.run(%{sport: "football", league: "nfl", plug: {Req.Test, __MODULE__}})

    assert String.contains?(text, "NO")
    assert String.contains?(text, "GAMES")
  end

  test "returns fallback message when team not found in today or upcoming games" do
    # Stub returns KC/BUF for every request (today + all upcoming days), so LAL is never found
    f = stub_sports([make_game(home: "KC", away: "BUF", status: :final)])

    assert {:ok, %{text: text, live: false}} =
             f.(%{sport: "football", league: "nfl", team: "LAL"})

    assert String.contains?(text, "LAL")
    assert String.contains?(text, "NO")
  end

  test "returns upcoming game when team not in today but found in future" do
    # Stub returns different responses based on whether a 'dates' query param is present.
    # No dates param → today's games (KC/BUF only, LAL absent).
    # dates param present → tomorrow's games (LAL/BOS).
    future_game =
      make_game(
        home: "LAL",
        away: "BOS",
        status: :scheduled,
        start_time: "2026-04-26T00:00:00Z",
        home_score: nil,
        away_score: nil
      )

    Req.Test.stub(__MODULE__, fn conn ->
      query = URI.decode_query(conn.query_string)

      games =
        if Map.has_key?(query, "dates"),
          do: [future_game],
          else: [make_game(home: "KC", away: "BUF", status: :final)]

      Req.Test.json(conn, %{"events" => [build_espn_event(hd(games))]})
    end)

    assert {:ok, %{text: text, live: false}} =
             Sports.run(%{
               sport: "basketball",
               league: "nba",
               team: "LAL",
               plug: {Req.Test, __MODULE__}
             })

    assert String.contains?(text, "LAL")
    assert String.contains?(text, "NEXT GAME")
  end

  test "formats in-progress game with score and period/clock" do
    f =
      stub_sports([
        make_game(
          home: "KC",
          home_score: 27,
          away: "BUF",
          away_score: 24,
          status: :in_progress,
          period: 3,
          clock: "4:32"
        )
      ])

    assert {:ok, %{text: text}} = f.(%{sport: "football", league: "nfl"})
    assert String.contains?(text, "27")
    assert String.contains?(text, "24")
    assert String.contains?(text, "Q3")
    assert String.contains?(text, "4:32")
  end

  test "formats final game with FINAL label" do
    f =
      stub_sports([
        make_game(home: "KC", home_score: 27, away: "BUF", away_score: 24, status: :final)
      ])

    assert {:ok, %{text: text}} = f.(%{sport: "football", league: "nfl"})
    assert String.contains?(text, "FINAL")
  end

  test "formats scheduled game with TODAY and tip-off time" do
    f =
      stub_sports([
        make_game(
          status: :scheduled,
          home_score: nil,
          away_score: nil,
          start_time: "2026-04-25T23:30:00Z"
        )
      ])

    assert {:ok, %{text: text}} = f.(%{sport: "football", league: "nfl"})
    assert String.contains?(text, "TODAY")
    assert String.contains?(text, "PM")
  end

  test "uses P prefix for NHL periods" do
    f = stub_sports([make_game(status: :in_progress, period: 2, clock: "10:00")])
    assert {:ok, %{text: text}} = f.(%{sport: "hockey", league: "nhl"})
    assert String.contains?(text, "P2")
  end

  test "uses Q prefix for non-NHL periods" do
    f = stub_sports([make_game(status: :in_progress, period: 2, clock: "5:00")])
    assert {:ok, %{text: text}} = f.(%{sport: "basketball", league: "nba"})
    assert String.contains?(text, "Q2")
  end
end
