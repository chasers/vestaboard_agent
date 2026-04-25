# 2026-04-25_01 — SportsAgent

Display live or final sports scores on the Vestaboard via ESPN's unofficial scoreboard API (no API key required).

---

## Design Decisions

| Decision | Choice |
|---|---|
| Sport detection | Parse from prompt keywords (`nfl`, `nba`, `football`, `basketball`, etc.) |
| Default display | One game (filtered by team if mentioned, otherwise top game for the sport) |
| Live vs. one-shot | Live (refresh via `send_after` in the `SportsAgent` GenServer) when a game is in progress; one-shot when no live game found |
| Sport coverage | Whatever ESPN returns — no hard-coded sport restrictions |

---

## Modules

### `espn_client.ex`

Thin HTTP client over the ESPN unofficial API. All ESPN I/O lives here — `Tools.Sports` and `SportsAgent` never touch `Req` directly.

**Public API:**

```elixir
@spec scoreboard(sport :: String.t(), league :: String.t()) ::
  {:ok, [game()]} | {:error, term()}
```

Returns all games for today's scoreboard sorted by status (in-progress first, then scheduled, then final).

**Types:**

```elixir
@type team   :: %{abbrev: String.t(), name: String.t(), score: non_neg_integer() | nil}
@type status :: :scheduled | :in_progress | :final
@type game   :: %{
  id:         String.t(),
  home:       team(),
  away:       team(),
  status:     status(),
  clock:      String.t() | nil,   # e.g. "4:32"
  period:     non_neg_integer() | nil,
  start_time: String.t() | nil    # ISO-8601 UTC
}
```

**Internals:**

- `GET https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/scoreboard`
- Match `{:ok, %{status: 200, body: body}}` explicitly; all other shapes → `{:error, reason}`
- Parse `status.type.name` → atom:
  - `"STATUS_IN_PROGRESS"` → `:in_progress`
  - `"STATUS_FINAL"` → `:final`
  - anything else → `:scheduled`
- Use `Req.Test` plug injection for tests (same pattern as `Weather` tool)
- Config key: `:espn_client` → `[plug: ...]` for test overrides

### `agents/sports_agent.ex`

- Keywords: `["score", "scores", "game", "nfl", "nba", "mlb", "nhl", "ncaa", "football", "basketball", "baseball", "hockey", "soccer"]`
- GenServer (long-running when a live game is in progress)
- On `handle/2`:
  1. Parse sport/league from prompt keywords
  2. Parse optional team abbreviation from prompt
  3. Call `Tools.Sports.run/1`
  4. If game is in progress → dispatch to board, schedule `send_after(@refresh_ms, :refresh)`, return `{:ok, :running, state}`
  5. If game is final or scheduled → dispatch to board, return `{:ok, :done}`
- On `handle_info(:refresh, state)`:
  1. Re-fetch via `Tools.Sports.run/1`
  2. If still in progress → dispatch, re-schedule `send_after`
  3. If now final/not found → dispatch final score, stop

Refresh interval: `@refresh_ms 60_000` (1 minute).

### `tools/sports.ex`

Context keys:
- `:sport` — ESPN sport slug (e.g. `"football"`, `"basketball"`, `"baseball"`, `"hockey"`)
- `:league` — ESPN league slug (e.g. `"nfl"`, `"nba"`, `"mlb"`, `"nhl"`)
- `:team` — optional team abbreviation to filter on (e.g. `"KC"`, `"LAL"`)

Delegates to `ESPNClient.scoreboard/2` — no HTTP here. Responsibilities:
1. Filter games by `:team` if provided, else take the first game
2. Format the selected game into board-ready text
3. Return `{:ok, %{text: String.t(), live: boolean()}}`

`live: true` when the selected game has `status: :in_progress`.

---

## Display Format (6 rows × 22 cols)

Single game — in progress:
```
NFL   KC vs BUF
      27    24
      Q3  4:32
```

Single game — final:
```
NFL   KC vs BUF
      27    24
      FINAL
```

Single game — scheduled (no score yet):
```
NFL
KC  vs  BUF
TODAY  7:30 PM
```

---

## Keyword → Sport/League Mapping

```elixir
@sport_map %{
  "nfl"        => {"football",    "nfl"},
  "football"   => {"football",    "nfl"},
  "nba"        => {"basketball",  "nba"},
  "basketball" => {"basketball",  "nba"},
  "mlb"        => {"baseball",    "mlb"},
  "baseball"   => {"baseball",    "mlb"},
  "nhl"        => {"hockey",      "nhl"},
  "hockey"     => {"hockey",      "nhl"},
  "ncaa"       => {"football",    "college-football"},
  "college"    => {"football",    "college-football"},
  "soccer"     => {"soccer",      "usa.1"},
  "mls"        => {"soccer",      "usa.1"}
}
```

Default (no keyword matched): `{"football", "nfl"}`.

---

## Files to Create

```
lib/vestaboard_agent/espn_client.ex
lib/vestaboard_agent/agents/sports_agent.ex
lib/vestaboard_agent/tools/sports.ex
test/vestaboard_agent/espn_client_test.exs
test/vestaboard_agent/agents/sports_agent_test.exs
test/vestaboard_agent/tools/sports_test.exs
```

---

## Tests

`espn_client_test.exs`:
- Returns list of games with correct struct shape
- Maps `"STATUS_IN_PROGRESS"` → `:in_progress`, `"STATUS_FINAL"` → `:final`, anything else → `:scheduled`
- Returns `{:error, _}` on non-200 response
- Returns `{:error, _}` on network failure
- HTTP stubbed via `Req.Test`

`sports_test.exs`:
- Filters by team abbreviation (both home and away)
- Falls back to first game when no team given
- Returns `live: true` only for `:in_progress` game
- Formats in-progress, final, and scheduled display text correctly
- Stubs `ESPNClient` (no HTTP in this layer)

`sports_agent_test.exs`:
- Returns `{:ok, :done}` for a final game
- Returns `{:ok, :running, _}` for an in-progress game
- Sends `:refresh` and dispatches again while live
- Stops after game goes final on refresh

---

## Status

| | Item |
|---|---|
| ✅ | `ESPNClient` — HTTP fetch, JSON parse, typed game structs |
| ✅ | `Tools.Sports` — filter, select, format board text |
| ✅ | `SportsAgent` — keyword parsing, one-shot vs. live refresh loop |
| ✅ | Wire into `Agent.Registry` `@default_agents` |
| ✅ | Unit tests (all three modules) |
