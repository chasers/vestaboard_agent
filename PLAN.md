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

## Backlog

- [ ] `Countdown` tool — days/hours/minutes until a target datetime
- [ ] ExDoc documentation site
- [ ] Cloud API parity (transitions, `format_text`)
- [ ] Multi-board support
