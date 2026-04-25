defmodule VestaboardAgent.Agents.SportsAgent do
  @moduledoc """
  Displays live or final sports scores on the board via ESPN's unofficial API.

  When a game is in progress the agent enters a refresh loop, dispatching an
  updated score every `@default_refresh_ms` milliseconds until the game ends.
  When no game is live it dispatches once and returns.

  The refresh loop uses `Process.send_after/3` so it is interruptible — a
  `Process.exit(pid, :kill)` from `VestaboardAgent.preempt_running_display/0`
  stops it cleanly mid-sleep.

  ## Prompt parsing

  Team names are resolved via `@team_lookup` before falling back to sport
  keywords or all-caps abbreviation detection. "Suns score" correctly resolves
  to NBA/PHX; "Chiefs game" resolves to NFL/KC.

  Ambiguous nicknames (where the same word is used by teams in multiple leagues)
  are documented inline in `@team_lookup` with the chosen resolution.

  ## Testability

  Pass these context keys to override defaults in tests:

  - `:dispatch_fn` — replaces `Dispatcher.dispatch/1`
  - `:sports_fn`   — replaces `Tools.Sports.run/1`
  - `:refresh_ms`  — overrides `@default_refresh_ms` (use 0 in tests)
  """

  require Logger

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.{Dispatcher, Formatter, Tools.Sports}

  @default_refresh_ms 60_000

  # Ordered list — first match wins for ambiguous nicknames.
  # Ambiguity notes are inline where a nickname exists in multiple leagues.
  @team_lookup [
    # ── NFL ──────────────────────────────────────────────────────────────────
    {"cardinals",    {"football",   "nfl", "ARI"}},  # ARI; MLB Cardinals → "cards"/"stl cardinals"
    {"falcons",      {"football",   "nfl", "ATL"}},
    {"ravens",       {"football",   "nfl", "BAL"}},
    {"bills",        {"football",   "nfl", "BUF"}},
    {"panthers",     {"football",   "nfl", "CAR"}},  # CAR; NHL Panthers → "florida panthers"
    {"bears",        {"football",   "nfl", "CHI"}},
    {"bengals",      {"football",   "nfl", "CIN"}},
    {"browns",       {"football",   "nfl", "CLE"}},
    {"cowboys",      {"football",   "nfl", "DAL"}},
    {"broncos",      {"football",   "nfl", "DEN"}},
    {"lions",        {"football",   "nfl", "DET"}},
    {"packers",      {"football",   "nfl", "GB"}},
    {"texans",       {"football",   "nfl", "HOU"}},
    {"colts",        {"football",   "nfl", "IND"}},
    {"jaguars",      {"football",   "nfl", "JAX"}},
    {"chiefs",       {"football",   "nfl", "KC"}},
    {"raiders",      {"football",   "nfl", "LV"}},
    {"chargers",     {"football",   "nfl", "LAC"}},
    {"rams",         {"football",   "nfl", "LAR"}},
    {"dolphins",     {"football",   "nfl", "MIA"}},
    {"vikings",      {"football",   "nfl", "MIN"}},
    {"patriots",     {"football",   "nfl", "NE"}},
    {"saints",       {"football",   "nfl", "NO"}},
    {"giants",       {"football",   "nfl", "NYG"}},  # NYG; MLB Giants → "sf giants"
    {"jets",         {"football",   "nfl", "NYJ"}},  # NYJ; NHL Jets → "winnipeg jets"
    {"eagles",       {"football",   "nfl", "PHI"}},
    {"steelers",     {"football",   "nfl", "PIT"}},
    {"49ers",        {"football",   "nfl", "SF"}},
    {"seahawks",     {"football",   "nfl", "SEA"}},
    {"buccaneers",   {"football",   "nfl", "TB"}},
    {"bucs",         {"football",   "nfl", "TB"}},
    {"titans",       {"football",   "nfl", "TEN"}},
    {"commanders",   {"football",   "nfl", "WSH"}},
    # ── NBA ──────────────────────────────────────────────────────────────────
    {"hawks",        {"basketball", "nba", "ATL"}},
    {"celtics",      {"basketball", "nba", "BOS"}},
    {"nets",         {"basketball", "nba", "BKN"}},
    {"hornets",      {"basketball", "nba", "CHA"}},
    {"bulls",        {"basketball", "nba", "CHI"}},
    {"cavaliers",    {"basketball", "nba", "CLE"}},
    {"cavs",         {"basketball", "nba", "CLE"}},
    {"mavericks",    {"basketball", "nba", "DAL"}},
    {"mavs",         {"basketball", "nba", "DAL"}},
    {"nuggets",      {"basketball", "nba", "DEN"}},
    {"pistons",      {"basketball", "nba", "DET"}},
    {"warriors",     {"basketball", "nba", "GSW"}},
    {"rockets",      {"basketball", "nba", "HOU"}},
    {"pacers",       {"basketball", "nba", "IND"}},
    {"clippers",     {"basketball", "nba", "LAC"}},
    {"lakers",       {"basketball", "nba", "LAL"}},
    {"grizzlies",    {"basketball", "nba", "MEM"}},
    {"heat",         {"basketball", "nba", "MIA"}},
    {"bucks",        {"basketball", "nba", "MIL"}},
    {"timberwolves", {"basketball", "nba", "MIN"}},
    {"wolves",       {"basketball", "nba", "MIN"}},
    {"pelicans",     {"basketball", "nba", "NOP"}},
    {"knicks",       {"basketball", "nba", "NYK"}},
    {"thunder",      {"basketball", "nba", "OKC"}},
    {"magic",        {"basketball", "nba", "ORL"}},
    {"sixers",       {"basketball", "nba", "PHI"}},
    {"76ers",        {"basketball", "nba", "PHI"}},
    {"suns",         {"basketball", "nba", "PHX"}},
    {"trail blazers",{"basketball", "nba", "POR"}},
    {"blazers",      {"basketball", "nba", "POR"}},
    {"kings",        {"basketball", "nba", "SAC"}},  # SAC; NHL Kings → "la kings"
    {"spurs",        {"basketball", "nba", "SAS"}},
    {"raptors",      {"basketball", "nba", "TOR"}},
    {"jazz",         {"basketball", "nba", "UTA"}},
    {"wizards",      {"basketball", "nba", "WAS"}},
    # ── MLB ──────────────────────────────────────────────────────────────────
    {"diamondbacks", {"baseball",   "mlb", "ARI"}},
    {"dbacks",       {"baseball",   "mlb", "ARI"}},
    {"braves",       {"baseball",   "mlb", "ATL"}},
    {"orioles",      {"baseball",   "mlb", "BAL"}},
    {"red sox",      {"baseball",   "mlb", "BOS"}},
    {"cubs",         {"baseball",   "mlb", "CHC"}},
    {"white sox",    {"baseball",   "mlb", "CWS"}},
    {"reds",         {"baseball",   "mlb", "CIN"}},
    {"guardians",    {"baseball",   "mlb", "CLE"}},
    {"rockies",      {"baseball",   "mlb", "COL"}},
    {"tigers",       {"baseball",   "mlb", "DET"}},
    {"astros",       {"baseball",   "mlb", "HOU"}},
    {"royals",       {"baseball",   "mlb", "KC"}},
    {"angels",       {"baseball",   "mlb", "LAA"}},
    {"dodgers",      {"baseball",   "mlb", "LAD"}},
    {"marlins",      {"baseball",   "mlb", "MIA"}},
    {"brewers",      {"baseball",   "mlb", "MIL"}},
    {"twins",        {"baseball",   "mlb", "MIN"}},
    {"mets",         {"baseball",   "mlb", "NYM"}},
    {"yankees",      {"baseball",   "mlb", "NYY"}},
    {"athletics",    {"baseball",   "mlb", "ATH"}},
    {"phillies",     {"baseball",   "mlb", "PHI"}},
    {"pirates",      {"baseball",   "mlb", "PIT"}},
    {"padres",       {"baseball",   "mlb", "SD"}},
    {"mariners",     {"baseball",   "mlb", "SEA"}},
    {"cardinals",    {"baseball",   "mlb", "STL"}},  # unreachable — NFL cardinals match first
    {"cards",        {"baseball",   "mlb", "STL"}},
    {"rays",         {"baseball",   "mlb", "TB"}},
    {"rangers",      {"baseball",   "mlb", "TEX"}},  # TEX; NHL Rangers → "new york rangers"
    {"blue jays",    {"baseball",   "mlb", "TOR"}},
    {"jays",         {"baseball",   "mlb", "TOR"}},
    {"nationals",    {"baseball",   "mlb", "WSH"}},
    {"nats",         {"baseball",   "mlb", "WSH"}},
    # ── NHL ──────────────────────────────────────────────────────────────────
    {"ducks",        {"hockey",     "nhl", "ANA"}},
    {"bruins",       {"hockey",     "nhl", "BOS"}},
    {"sabres",       {"hockey",     "nhl", "BUF"}},
    {"flames",       {"hockey",     "nhl", "CGY"}},
    {"hurricanes",   {"hockey",     "nhl", "CAR"}},
    {"blackhawks",   {"hockey",     "nhl", "CHI"}},
    {"avalanche",    {"hockey",     "nhl", "COL"}},
    {"blue jackets", {"hockey",     "nhl", "CBJ"}},
    {"jackets",      {"hockey",     "nhl", "CBJ"}},
    {"stars",        {"hockey",     "nhl", "DAL"}},
    {"red wings",    {"hockey",     "nhl", "DET"}},
    {"oilers",       {"hockey",     "nhl", "EDM"}},
    {"florida panthers", {"hockey", "nhl", "FLA"}},
    {"golden knights",   {"hockey", "nhl", "VGK"}},
    {"knights",      {"hockey",     "nhl", "VGK"}},
    {"la kings",     {"hockey",     "nhl", "LAK"}},
    {"wild",         {"hockey",     "nhl", "MIN"}},
    {"canadiens",    {"hockey",     "nhl", "MTL"}},
    {"habs",         {"hockey",     "nhl", "MTL"}},
    {"predators",    {"hockey",     "nhl", "NSH"}},
    {"preds",        {"hockey",     "nhl", "NSH"}},
    {"devils",       {"hockey",     "nhl", "NJD"}},
    {"islanders",    {"hockey",     "nhl", "NYI"}},
    {"new york rangers", {"hockey", "nhl", "NYR"}},
    {"senators",     {"hockey",     "nhl", "OTT"}},
    {"flyers",       {"hockey",     "nhl", "PHI"}},
    {"penguins",     {"hockey",     "nhl", "PIT"}},
    {"pens",         {"hockey",     "nhl", "PIT"}},
    {"sharks",       {"hockey",     "nhl", "SJS"}},
    {"kraken",       {"hockey",     "nhl", "SEA"}},
    {"blues",        {"hockey",     "nhl", "STL"}},
    {"lightning",    {"hockey",     "nhl", "TBL"}},
    {"bolts",        {"hockey",     "nhl", "TBL"}},
    {"maple leafs",  {"hockey",     "nhl", "TOR"}},
    {"leafs",        {"hockey",     "nhl", "TOR"}},
    {"utah hockey",  {"hockey",     "nhl", "UTA"}},
    {"canucks",      {"hockey",     "nhl", "VAN"}},
    {"capitals",     {"hockey",     "nhl", "WSH"}},
    {"caps",         {"hockey",     "nhl", "WSH"}},
    {"winnipeg jets",{"hockey",     "nhl", "WPG"}}
  ]

  @sport_keywords [
    {"nfl",        {"football",   "nfl"}},
    {"nba",        {"basketball", "nba"}},
    {"mlb",        {"baseball",   "mlb"}},
    {"nhl",        {"hockey",     "nhl"}},
    {"ncaa",       {"football",   "college-football"}},
    {"college",    {"football",   "college-football"}},
    {"mls",        {"soccer",     "usa.1"}},
    {"soccer",     {"soccer",     "usa.1"}},
    {"football",   {"football",   "nfl"}},
    {"basketball", {"basketball", "nba"}},
    {"baseball",   {"baseball",   "mlb"}},
    {"hockey",     {"hockey",     "nhl"}}
  ]

  @impl true
  def name, do: "sports"

  @impl true
  def keywords,
    do: [
      "score",
      "scores",
      "game",
      "nfl",
      "nba",
      "mlb",
      "nhl",
      "ncaa",
      "football",
      "basketball",
      "baseball",
      "hockey",
      "soccer"
    ]

  @impl true
  def handle(prompt, context) do
    {sport, league} = parse_sport(prompt)
    team = parse_team(prompt)

    ctx = Map.merge(context, %{sport: sport, league: league, team: team})
    dispatch_fn = Map.get(context, :dispatch_fn, &Dispatcher.dispatch/2)
    sports_fn = Map.get(context, :sports_fn, &Sports.run/1)
    refresh_ms = Map.get(context, :refresh_ms, @default_refresh_ms)

    format_fn =
      Map.get(context, :format_fn, fn text ->
        Formatter.format(text,
          llm_opts: Map.get(context, :llm_opts, []),
          history: Map.get(context, :history, [])
        )
      end)

    case sports_fn.(ctx) do
      {:ok, %{text: text, live: true}} ->
        {:ok, formatted, render_opts} = format_fn.(text)
        dispatch_fn.(formatted, render_opts)
        Logger.info("[sports] #{league} game in progress — refreshing every #{refresh_ms}ms")
        refresh_loop(ctx, sports_fn, format_fn, dispatch_fn, refresh_ms)
        {:ok, :done}

      {:ok, %{text: text, live: false}} ->
        {:ok, formatted, render_opts} = format_fn.(text)
        dispatch_fn.(formatted, render_opts)
        {:ok, :done}

      {:error, reason} ->
        Logger.warning("[sports] fetch failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp refresh_loop(ctx, sports_fn, format_fn, dispatch_fn, refresh_ms) do
    Process.send_after(self(), :sports_refresh, refresh_ms)

    receive do
      :sports_refresh ->
        case sports_fn.(ctx) do
          {:ok, %{text: text, live: true}} ->
            {:ok, formatted, render_opts} = format_fn.(text)
            dispatch_fn.(formatted, render_opts)
            Logger.info("[sports] refreshed live score")
            refresh_loop(ctx, sports_fn, format_fn, dispatch_fn, refresh_ms)

          {:ok, %{text: text, live: false}} ->
            {:ok, formatted, render_opts} = format_fn.(text)
            dispatch_fn.(formatted, render_opts)
            Logger.info("[sports] game ended — stopping refresh")

          {:error, reason} ->
            Logger.warning("[sports] refresh failed: #{inspect(reason)}")
        end
    end
  end

  # Returns {sport, league, abbrev} for the first team name found in the prompt,
  # or nil if no team name matches.
  defp lookup_team(prompt) do
    normalized = String.downcase(prompt)

    Enum.find_value(@team_lookup, fn {name, result} ->
      if String.contains?(normalized, name), do: result
    end)
  end

  defp parse_sport(prompt) do
    case lookup_team(prompt) do
      {sport, league, _abbrev} ->
        {sport, league}

      nil ->
        normalized = String.downcase(prompt)

        Enum.find_value(@sport_keywords, {"football", "nfl"}, fn {keyword, sport_league} ->
          if String.contains?(normalized, keyword), do: sport_league
        end)
    end
  end

  defp parse_team(prompt) do
    case lookup_team(prompt) do
      {_sport, _league, abbrev} ->
        abbrev

      nil ->
        prompt
        |> String.split(~r/\s+/)
        |> Enum.find_value(nil, fn word ->
          clean = String.replace(word, ~r/[^A-Za-z]/, "")
          len = String.length(clean)

          if len in 2..4 and clean == String.upcase(clean) and String.match?(clean, ~r/^[A-Z]+$/),
            do: clean
        end)
    end
  end
end
