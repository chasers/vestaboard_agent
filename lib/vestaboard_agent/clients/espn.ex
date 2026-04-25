defmodule VestaboardAgent.Clients.ESPN do
  @moduledoc """
  HTTP client for the ESPN unofficial scoreboard API (no API key required).

  All ESPN I/O lives here. Callers receive typed `game()` structs and never
  interact with raw HTTP or JSON.

  ## Test injection

      ESPN.scoreboard("football", "nfl", plug: {Req.Test, MyTest})

  Configure the plug at the app level to avoid threading it through every call:

      Application.put_env(:vestaboard_agent, :espn_client, plug: {Req.Test, MyTest})
  """

  @base_url "https://site.api.espn.com/apis/site/v2/sports"

  @type team :: %{abbrev: String.t(), name: String.t(), score: non_neg_integer() | nil}
  @type status :: :scheduled | :in_progress | :final
  @type game :: %{
          id: String.t(),
          home: team(),
          away: team(),
          status: status(),
          clock: String.t() | nil,
          period: non_neg_integer() | nil,
          start_time: String.t() | nil
        }

  @doc """
  Fetch the scoreboard for the given sport and league.

  Returns games sorted by status: in-progress first, then scheduled, then final.

  Pass `dates: "YYYYMMDD"` in opts to fetch a specific date instead of today.
  """
  @spec scoreboard(String.t(), String.t(), keyword()) :: {:ok, [game()]} | {:error, term()}
  def scoreboard(sport, league, opts \\ []) do
    req = build_req(opts)
    url = "#{@base_url}/#{sport}/#{league}/scoreboard"
    params = if d = Keyword.get(opts, :dates), do: [dates: d], else: []

    case Req.get(req, url: url, params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, parse_games(body)}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Find the next game (today or within `lookahead` days) for `team_abbrev`.

  Searches day by day starting from today. Returns `{:ok, game()}` for the
  first day the team appears, or `{:error, :not_found}` if nothing is found
  within the lookahead window.
  """
  @spec upcoming_game(String.t(), String.t(), String.t(), keyword(), non_neg_integer()) ::
          {:ok, game()} | {:error, :not_found}
  def upcoming_game(sport, league, team_abbrev, opts \\ [], lookahead \\ 7) do
    up = String.upcase(team_abbrev)
    today = Date.utc_today()

    Enum.find_value(0..lookahead, {:error, :not_found}, fn offset ->
      date_str = today |> Date.add(offset) |> Date.to_string() |> String.replace("-", "")

      case scoreboard(sport, league, Keyword.put(opts, :dates, date_str)) do
        {:ok, games} ->
          Enum.find_value(games, nil, fn g ->
            if String.upcase(g.home.abbrev) == up or String.upcase(g.away.abbrev) == up,
              do: {:ok, g}
          end)

        {:error, _} ->
          nil
      end
    end)
  end

  defp build_req(opts) do
    base = Req.new(retry: false)
    plug = Keyword.get(opts, :plug) || get_in(Application.get_env(:vestaboard_agent, :espn_client, []), [:plug])
    if plug, do: Req.merge(base, plug: plug), else: base
  end

  defp parse_games(%{"events" => events}) when is_list(events) do
    events
    |> Enum.map(&parse_event/1)
    |> Enum.sort_by(fn g -> status_sort(g.status) end)
  end

  defp parse_games(_), do: []

  defp parse_event(event) do
    [competition | _] = event["competitions"]
    competitors = competition["competitors"]
    home = Enum.find(competitors, &(&1["homeAway"] == "home"))
    away = Enum.find(competitors, &(&1["homeAway"] == "away"))

    %{
      id: event["id"],
      home: parse_team(home),
      away: parse_team(away),
      status: parse_status(get_in(competition, ["status", "type", "name"])),
      clock: get_in(competition, ["status", "displayClock"]),
      period: get_in(competition, ["status", "period"]),
      start_time: competition["date"]
    }
  end

  defp parse_team(nil), do: %{abbrev: "?", name: "Unknown", score: nil}

  defp parse_team(competitor) do
    %{
      abbrev: get_in(competitor, ["team", "abbreviation"]) || "?",
      name: get_in(competitor, ["team", "displayName"]) || "Unknown",
      score: parse_score(competitor["score"])
    }
  end

  defp parse_score(nil), do: nil
  defp parse_score(s) when is_binary(s), do: elem(Integer.parse(s), 0)
  defp parse_score(n) when is_integer(n), do: n

  defp parse_status("STATUS_IN_PROGRESS"), do: :in_progress
  defp parse_status("STATUS_FINAL"), do: :final
  defp parse_status(_), do: :scheduled

  defp status_sort(:in_progress), do: 0
  defp status_sort(:scheduled), do: 1
  defp status_sort(:final), do: 2
end
