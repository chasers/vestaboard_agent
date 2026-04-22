# VestaboardAgent — Project Plan

Status legend: ✅ done · 🔄 in progress · ⬜ not started

---

## Phase 1 — Foundation ✅

| | Item |
|---|---|
| ✅ | Project scaffolding (mix, deps, formatter) |
| ✅ | `Tool` behaviour |
| ✅ | `Agent` behaviour |
| ✅ | `Sandbox` behaviour + Lua backend |
| ✅ | `LuaTool` — run scripts via sandbox |
| ✅ | `LuaAPI` — Elixir bindings exposed to Lua |
| ✅ | `Greeting` tool (first Lua-backed tool) |
| ✅ | Vestaboard API client — local + cloud backends |
| ✅ | Test suite (61 tests, 86% coverage) |
| ✅ | Network discovery scripts (`make find`) |
| ✅ | Local API enablement script (`make enable`) |
| ✅ | Connectivity test script (`make ping`) |

---

## Phase 2 — Core Runtime ✅

Turn the pipeline from a diagram into running code.

| | Item | Notes |
|---|---|---|
| ✅ | `Renderer` — convert a string to a 6×22 character grid | Local character map; word-wrap; center/left align; vertical centering |
| ✅ | `Dispatcher` — send a rendered grid via `Client` | Accepts text or pre-rendered grid; serialized GenServer |
| ✅ | Wire `Tool → Renderer → Dispatcher` end-to-end | `Dispatcher.dispatch_tool/2`; `Greeter` agent proves full path |
| ✅ | `Agent.Registry` — map a prompt string to an agent module | GenServer; keyword match; runtime registration |
| ✅ | Supervision tree — start registry + dispatcher under an OTP supervisor | `VestaboardAgent.Application` |

---

## Phase 3 — Real Tools ✅

| | Tool | Description |
|---|---|---|
| ✅ | `Weather` | Fetch current conditions from Open-Meteo (no API key) |
| ⬜ | `Countdown` | Days/hours/minutes until a target datetime |
| ✅ | `Quote` | Rotating quotes from a local list |
| ✅ | `Clock` | Current time displayed on the board |

---

## Phase 4 — Agent Intelligence ✅

| | Item | Notes |
|---|---|---|
| ✅ | First real agent — `ScheduleAgent` | Runs a tool on a cron schedule (Quantum) |
| ✅ | `ToolRegistry` — store and retrieve tools by name | Includes persisted Lua scripts |
| ✅ | LLM-backed dynamic tool generation | Agent writes a Lua script when no tool matches |
| ✅ | Long-running agent lifecycle | Supervisor keeps `:running` agents alive; supports cancellation |
| ✅ | Natural language prompt routing | LLM picks the right agent from a prompt |

---

## Phase 5 — Display Quality ✅

| | Item | Notes |
|---|---|---|
| ✅ | `Formatter` — LLM-based layout + border color selection | Returns `{text, render_opts}` |
| ✅ | `Renderer` border support | 1-cell colored ring; 4×20 inner content area |
| ✅ | Vertical centering | Blank rows split evenly above and below content |
| ✅ | `VestaboardAgent.display/1` — single entry point | Routes prompt → agent → formatter → dispatcher |
| ✅ | Agents return `{:ok, text}` | Formatter runs on tool output, not raw prompt |

---

## Phase 6 — Chat Interface

| | Item | Notes |
|---|---|---|
| ✅ | **6a** HTTP chat endpoint | `POST /chat` via Plug.Router; returns displayed text + border |
| ✅ | **6b** `ScheduleAgent` NLP wiring | Parse "show clock every 15 seconds" into a schedule call; extended cron for sub-minute intervals |
| ✅ | **6c** Conversation context | Track last N board states; pass to LLM so follow-ups ("make it bigger") work |
| ✅ | **6d** Board read-back | `GET /board` returns current grid + decoded text; include in LLM context |

---

## Phase 7 — End-to-End Test Suite

Hits the real board and real LLM. Run with `mix test.e2e`. Never part of the normal `mix test` run.

### Infrastructure

| | Item | Notes |
|---|---|---|
| ✅ | `test/e2e/e2e_case.ex` — shared `CaseTemplate` | `assert_board_contains/2`, `assert_line_lengths/2`, `log_board_state/1`, rich failure formatter |
| ✅ | `test/e2e/e2e_helper.exs` — ExUnit bootstrap for E2E | Sets timeout, includes `:e2e` tag |
| ✅ | `lib/mix/tasks/test.e2e.ex` — `mix test.e2e` task | Guards env vars, wires e2e path + helper, passes remaining args through |
| ✅ | `mix.exs` — add `test/e2e` to `elixirc_paths` for `:test` | So `e2e_case.ex` compiles as a support module |

### Setup / teardown contract (in `E2ECase`)

- `setup_all`: guard `VESTABOARD_LOCAL_API_KEY` + `ANTHROPIC_API_KEY`; skip module cleanly if missing
- `setup`: `ConversationContext.clear()`, cancel any leftover scheduled jobs, sleep `E2E_PACE_MS` (default 3000 ms) between tests
- `on_exit`: each test cleans up its own scheduled jobs and registered Lua scripts

### Test groups

| | Group | File | Scenarios |
|---|---|---|---|
| ✅ | **7a** Direct render | `01_direct_render_test.exs` | Greeting, explicit text, word-wrap, border color, 22-char line, special chars (`$`, `.`, `/`) |
| ✅ | **7b** Tool dispatch | `02_tool_dispatch_test.exs` | Clock (time pattern), Weather (temp pattern), Quote (non-empty), Greeting, registered Lua script |
| ✅ | **7c** HTTP chat | `03_http_chat_test.exs` | `POST /chat` happy path, missing prompt → 400, `GET /board` returns `{grid, text}`, board-before-write → 404 |
| ✅ | **7d** Conversation context | `04_conversation_context_test.exs` | "change border to red" follow-up, "do that again" re-routes same agent, history capped at 5, clear then follow-up is treated as fresh |
| ✅ | **7e** Scheduling | `05_schedule_agent_test.exs` | 2s interval fires and updates board, cancel-before-fire leaves board unchanged, NL "show clock every 5 seconds" registers job |
| ✅ | **7f** Edge cases | `06_edge_cases_test.exs` | Empty prompt, 200-char prompt, unicode, concurrent `display/1` calls, LLM key missing → graceful fallback |

### Failure output format

Each `assert_board_contains` failure prints a structured block designed to be pasted into Claude Code:

```
═══════════════════════════════════════════════════
E2E FAILURE: direct render / plain text
Prompt:      "happy Tuesday"
Expected:    contains "TUESDAY"
Actual text: "HAPPY\nTUESDAY"
Grid rows:   row 2: [0,0,0,8,1,16,16,25,...]
             row 3: [0,0,0,20,21,5,19,4,1,25,...]
Elapsed:     1842 ms  |  2026-04-22T14:03:01Z
═══════════════════════════════════════════════════
```

### Optional JSONL report

Set `E2E_REPORT_FILE=/tmp/e2e.jsonl` to append one JSON object per test (prompt, expected, actual_text, matched, elapsed_ms, timestamp). Useful for diffing runs or feeding a batch of failures to Claude Code.

### How to run

```bash
mix test.e2e                                          # full suite
mix test.e2e test/e2e/03_http_chat_test.exs           # single file
E2E_PACE_MS=500 mix test.e2e                          # faster (CI)
E2E_REPORT_FILE=/tmp/e2e.jsonl mix test.e2e           # with report
```

---

## Backlog

- [ ] `Countdown` tool — days/hours/minutes until a target datetime
- [ ] ExDoc documentation site
- [ ] Cloud API parity (transitions, `format_text`)
- [ ] Multi-board support
