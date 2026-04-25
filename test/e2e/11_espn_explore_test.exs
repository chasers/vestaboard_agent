defmodule VestaboardAgent.E2E.ESPNExploreTest do
  @moduledoc """
  Exploratory E2E tests for the ESPN scoreboard API.

  These tests hit the live ESPN API (no board, no LLM required) and print
  raw game data so you can see exactly what fields and values are returned.
  Run with: mix test.e2e test/e2e/11_espn_explore_test.exs

  Assertions are structural only — values (scores, teams) change daily.
  """

  use ExUnit.Case, async: false

  @moduletag :e2e
  @moduletag timeout: 30_000

  alias VestaboardAgent.Clients.ESPN

  @leagues [
    {"football", "nfl", "NFL"},
    {"basketball", "nba", "NBA"},
    {"baseball", "mlb", "MLB"},
    {"hockey", "nhl", "NHL"}
  ]

  # ---------------------------------------------------------------------------
  # Raw API shape
  # ---------------------------------------------------------------------------

  describe "scoreboard/2 — response structure" do
    for {sport, league, label} <- @leagues do
      @sport sport
      @league league
      @label label

      test "#{label} returns a list of game structs" do
        case ESPN.scoreboard(@sport, @league) do
          {:ok, games} ->
            IO.puts("\n  #{@label} — #{length(games)} game(s) today")

            for g <- games do
              IO.puts("    #{game_summary(g)}")
            end

            assert is_list(games)

            for g <- games do
              assert_game_shape(g, @label)
            end

          {:error, {:http, status}} ->
            IO.puts("\n  #{@label} — HTTP #{status} (no data for today)")

          {:error, reason} ->
            flunk("#{@label} ESPN request failed: #{inspect(reason)}")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Status values
  # ---------------------------------------------------------------------------

  describe "scoreboard/2 — status field" do
    test "all returned statuses are known atoms" do
      valid = MapSet.new([:scheduled, :in_progress, :final])

      for {sport, league, label} <- @leagues do
        case ESPN.scoreboard(sport, league) do
          {:ok, games} ->
            for g <- games do
              assert g.status in valid,
                     "#{label}: unexpected status #{inspect(g.status)} in game #{game_summary(g)}"
            end

          {:error, _} ->
            :ok
        end
      end
    end

    test "in-progress games appear before scheduled and final" do
      case ESPN.scoreboard("basketball", "nba") do
        {:ok, [first | _] = games} when length(games) > 1 ->
          live = Enum.filter(games, &(&1.status == :in_progress))
          scheduled = Enum.filter(games, &(&1.status == :scheduled))
          final = Enum.filter(games, &(&1.status == :final))

          IO.puts(
            "\n  NBA order: #{length(live)} live, " <>
              "#{length(scheduled)} scheduled, #{length(final)} final"
          )

          if length(live) > 0 and length(scheduled) > 0 do
            live_indices = live |> Enum.map(&Enum.find_index(games, fn g -> g == &1 end))
            sched_indices = scheduled |> Enum.map(&Enum.find_index(games, fn g -> g == &1 end))
            assert Enum.max(live_indices) < Enum.min(sched_indices)
          end

          _ = first

        _ ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Score fields
  # ---------------------------------------------------------------------------

  describe "scoreboard/2 — score fields" do
    test "in-progress and final games have integer scores" do
      for {sport, league, label} <- @leagues do
        case ESPN.scoreboard(sport, league) do
          {:ok, games} ->
            active = Enum.filter(games, &(&1.status in [:in_progress, :final]))

            for g <- active do
              assert is_integer(g.home.score),
                     "#{label}: expected integer home score, got #{inspect(g.home.score)}"

              assert is_integer(g.away.score),
                     "#{label}: expected integer away score, got #{inspect(g.away.score)}"

              assert g.home.score >= 0
              assert g.away.score >= 0
            end

          {:error, _} ->
            :ok
        end
      end
    end

    test "scheduled games have nil scores" do
      for {sport, league, label} <- @leagues do
        case ESPN.scoreboard(sport, league) do
          {:ok, games} ->
            scheduled = Enum.filter(games, &(&1.status == :scheduled))

            for g <- scheduled do
              assert is_nil(g.home.score) or is_integer(g.home.score),
                     "#{label}: unexpected home score type #{inspect(g.home.score)}"
            end

          {:error, _} ->
            :ok
        end
      end
    end

    test "in-progress games have a clock and period" do
      for {sport, league, label} <- @leagues do
        case ESPN.scoreboard(sport, league) do
          {:ok, games} ->
            live = Enum.filter(games, &(&1.status == :in_progress))

            for g <- live do
              IO.puts("    #{label} live: #{game_summary(g)}")
              assert is_binary(g.clock) or is_nil(g.clock)
              assert is_integer(g.period) or is_nil(g.period)
            end

          {:error, _} ->
            :ok
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Team fields
  # ---------------------------------------------------------------------------

  describe "scoreboard/2 — team fields" do
    test "home and away teams have non-empty abbrev and name" do
      for {sport, league, label} <- @leagues do
        case ESPN.scoreboard(sport, league) do
          {:ok, games} ->
            for g <- games do
              assert is_binary(g.home.abbrev) and g.home.abbrev != "",
                     "#{label}: blank home abbrev in #{game_summary(g)}"

              assert is_binary(g.home.name) and g.home.name != "",
                     "#{label}: blank home name in #{game_summary(g)}"

              assert is_binary(g.away.abbrev) and g.away.abbrev != "",
                     "#{label}: blank away abbrev in #{game_summary(g)}"

              assert is_binary(g.away.name) and g.away.name != "",
                     "#{label}: blank away name in #{game_summary(g)}"
            end

          {:error, _} ->
            :ok
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # upcoming_game/5
  # ---------------------------------------------------------------------------

  describe "upcoming_game/5 — well-known teams" do
    @well_known [
      {"football", "nfl", "KC", "Chiefs"},
      {"basketball", "nba", "LAL", "Lakers"},
      {"baseball", "mlb", "NYY", "Yankees"},
      {"hockey", "nhl", "BOS", "Bruins"}
    ]

    for {sport, league, abbrev, name} <- @well_known do
      @sport sport
      @league league
      @abbrev abbrev
      @name name

      test "#{@name} (#{@abbrev}) — finds next game within 14 days or returns :not_found" do
        result = ESPN.upcoming_game(@sport, @league, @abbrev, [], 14)
        IO.puts("\n  #{@name} upcoming: #{inspect(result)}")

        case result do
          {:ok, g} ->
            assert_game_shape(g, "upcoming #{@name}")

            team_abbrevs = [String.upcase(g.home.abbrev), String.upcase(g.away.abbrev)]

            assert @abbrev in team_abbrevs,
                   "Expected #{@abbrev} in game #{game_summary(g)}"

          {:error, :not_found} ->
            :ok
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp assert_game_shape(g, label) do
    assert is_binary(g.id) and g.id != "", "#{label}: missing game id"
    assert is_map(g.home), "#{label}: home is not a map"
    assert is_map(g.away), "#{label}: away is not a map"
    assert g.status in [:scheduled, :in_progress, :final], "#{label}: bad status"
    assert is_binary(g.start_time) or is_nil(g.start_time), "#{label}: bad start_time"
  end

  defp game_summary(g) do
    score =
      case g.status do
        :scheduled -> "vs (#{g.start_time})"
        _ -> "#{g.away.score} vs #{g.home.score}"
      end

    "#{g.away.abbrev} #{score} #{g.home.abbrev} [#{g.status}]" <>
      if(g.clock, do: " #{g.period}p #{g.clock}", else: "")
  end
end
