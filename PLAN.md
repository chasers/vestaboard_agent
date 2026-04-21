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

## Phase 2 — Core Runtime

Turn the pipeline from a diagram into running code.

| | Item | Notes |
|---|---|---|
| ✅ | `Renderer` — convert a string to a 6×22 character grid | Local character map; word-wrap; center/left align |
| ✅ | `Dispatcher` — send a rendered grid via `Client` | Accepts text or pre-rendered grid |
| ✅ | Wire `Tool → Renderer → Dispatcher` end-to-end | `Dispatcher.dispatch_tool/2`; `Greeter` agent proves full path |
| ✅ | `Agent.Registry` — map a prompt string to an agent module | GenServer; keyword match; runtime registration |
| ✅ | Supervision tree — start registry + dispatcher under an OTP supervisor | `VestaboardAgent.Application` |

---

## Phase 3 — Real Tools

| | Tool | Description |
|---|---|---|
| ✅ | `Weather` | Fetch current conditions from Open-Meteo (no API key) |
| ⬜ | `Countdown` | Days/hours/minutes until a target datetime |
| ✅ | `Quote` | Rotating quotes from a local list |
| ✅ | `Clock` | Current time displayed on the board |

---

## Phase 4 — Agent Intelligence

| | Item | Notes |
|---|---|---|
| ⬜ | First real agent — `ScheduleAgent` | Runs a tool on a cron schedule |
| ⬜ | `ToolRegistry` — store and retrieve tools by name | Includes persisted Lua scripts |
| ⬜ | LLM-backed dynamic tool generation | Agent writes a Lua script when no tool matches |
| ⬜ | Long-running agent lifecycle | Supervisor keeps `:running` agents alive; supports cancellation |
| ⬜ | Natural language prompt routing | LLM picks the right agent from a prompt |

---

## Backlog

- [ ] ExDoc documentation site
- [ ] Cloud API parity (transitions, `format_text`)
- [ ] Multi-board support
- [ ] Web UI or CLI for sending ad-hoc messages
