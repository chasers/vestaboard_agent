defmodule VestaboardAgent.Tools.Sports do
  @moduledoc """
  Fetches and formats a sports score for display on the board.

  Delegates all HTTP and JSON parsing to `ESPNClient`. This module is
  responsible only for game selection and text formatting.

  ## Game resolution order

  1. Today's scoreboard — if the team has a game today (any status), show it.
  2. Upcoming games — if the team isn't in today's scoreboard, search the next
     7 days and display the next scheduled game time.
  3. Fallback message — if the team can't be found at all, display a
     board-friendly "no games found" message so the user always sees something.

  Context keys:
  - `:sport`  — ESPN sport slug, e.g. `"football"`, `"basketball"`
  - `:league` — ESPN league slug, e.g. `"nfl"`, `"nba"`
  - `:team`   — optional team abbreviation filter, e.g. `"KC"`, `"PHX"`
  - `:plug`   — forwarded to `ESPNClient` for test injection
  """

  @behaviour VestaboardAgent.Tool

  alias VestaboardAgent.Clients.ESPN, as: ESPNClient

  @impl true
  def name, do: "sports"

  @impl true
  def run(context \\ %{}) do
    sport = Map.get(context, :sport, "football")
    league = Map.get(context, :league, "nfl")
    team = Map.get(context, :team)
    opts = espn_opts(context)

    case ESPNClient.scoreboard(sport, league, opts) do
      {:ok, games} ->
        case select_game(games, team) do
          {:ok, game} ->
            {:ok, %{text: format(game, league), live: game.status == :in_progress}}

          {:error, _} when not is_nil(team) ->
            find_upcoming(sport, league, team, league, opts)

          {:error, :no_games} ->
            {:ok, %{text: "NO #{String.upcase(league)}\nGAMES TODAY", live: false}}
        end

      {:error, _} = err ->
        err
    end
  end

  defp espn_opts(%{plug: plug}), do: [plug: plug]
  defp espn_opts(_), do: []

  defp select_game([], _team), do: {:error, :no_games}
  defp select_game([first | _], nil), do: {:ok, first}

  defp select_game(games, team) do
    up = String.upcase(team)

    case Enum.find(games, fn g ->
           String.upcase(g.home.abbrev) == up or String.upcase(g.away.abbrev) == up
         end) do
      nil -> {:error, {:team_not_found, team}}
      game -> {:ok, game}
    end
  end

  defp find_upcoming(sport, league, team, league_label, opts) do
    case ESPNClient.upcoming_game(sport, league, team, opts) do
      {:ok, game} ->
        {:ok, %{text: format_upcoming(game, league_label), live: false}}

      {:error, :not_found} ->
        label = String.upcase(league_label)
        {:ok, %{text: "NO #{team} GAMES\nFOUND IN #{label}", live: false}}
    end
  end

  defp format(game, league) do
    label = String.upcase(league)
    away = game.away.abbrev
    home = game.home.abbrev

    case game.status do
      :in_progress ->
        away_score = game.away.score || 0
        home_score = game.home.score || 0
        period = period_label(game.period, league)
        clock = if game.clock, do: " #{game.clock}", else: ""
        "#{label} #{away} vs #{home}\n#{away_score} - #{home_score}\n#{period}#{clock}"

      :final ->
        away_score = game.away.score || 0
        home_score = game.home.score || 0
        "#{label} #{away} vs #{home}\n#{away_score} - #{home_score}\nFINAL"

      :scheduled ->
        time = format_game_time(game.start_time)
        "#{label} #{away} vs #{home}\nTODAY #{time}"
    end
  end

  defp format_upcoming(game, league) do
    label = String.upcase(league)
    away = game.away.abbrev
    home = game.home.abbrev
    time = format_game_time(game.start_time)
    "#{label} #{away} vs #{home}\nNEXT GAME\n#{time}"
  end

  # ESPN times are UTC; approximate ET as UTC-4 (covers EDT, most of the sports season)
  defp format_game_time(nil), do: "TBD"

  defp format_game_time(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} ->
        et = DateTime.add(dt, -4 * 3600, :second)
        date = DateTime.to_date(et)
        dow = Enum.at(~w[MON TUE WED THU FRI SAT SUN], Date.day_of_week(date) - 1)
        mon = Enum.at(~w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC], date.month - 1)
        h = et.hour
        ampm = if h >= 12, do: "PM", else: "AM"
        h12 = rem(h, 12)
        h12 = if h12 == 0, do: 12, else: h12
        min = String.pad_leading(Integer.to_string(et.minute), 2, "0")
        "#{dow} #{mon} #{date.day} #{h12}:#{min}#{ampm}"

      _ ->
        "TBD"
    end
  end

  defp period_label(nil, _), do: "Q?"
  defp period_label(p, "nhl"), do: "P#{p}"
  defp period_label(p, _), do: "Q#{p}"
end
