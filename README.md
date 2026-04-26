# VestaboardAgent

An Elixir harness for building agents that drive a [Vestaboard](https://www.vestaboard.com/) display. Prompts are routed through a two-tier system (scored keyword matching → LLM with confidence score), formatted for the 6×22 grid, and dispatched to the board.

## Getting Started

```bash
mix deps.get
mix test
iex -S mix
```

Send a prompt to the board:

```elixir
VestaboardAgent.display("Lakers score")
VestaboardAgent.display("show the weather")
VestaboardAgent.display("show clock every 30 seconds")
```

Or via HTTP:

```bash
curl -X POST http://localhost:4000/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt": "good morning"}'
```

## Agents

Agents respond to user prompts. Routing tries keyword matching first; if nothing scores high enough it asks the LLM, which returns a confidence score — low-confidence picks fall back to `dynamic`.

| Agent | Trigger keywords | What it does |
|---|---|---|
| `display` | "display" | Renders the literal text that follows the keyword verbatim |
| `greeter` | "hello", "good morning", "greet", … | Shows a time-appropriate greeting |
| `weather` | "weather", "forecast", "temperature", … | Fetches current conditions from Open-Meteo (no API key) |
| `sports` | "score", "nba", "nfl", "game", … | Shows live or final scores via ESPN |
| `schedule` | "every", "schedule", "remind", … | Runs any tool on a repeating interval |
| `snake` | "snake" | Plays an LLM-driven Snake game on the board |
| `conversational` | *(LLM-routed)* | Answers knowledge and trivia questions |
| `dynamic` | *(fallback)* | Generates a Lua tool on the fly for anything else |
| `explain` | "explain that", "why did you", … | Explains how and why the previous prompt was routed |

## Tools

Tools are pure content generators called by agents. They take a context map and return a string for the board.

| Tool | Description |
|---|---|
| `Clock` | Current time |
| `Greeting` | Time-appropriate greeting (Lua-backed) |
| `Quote` | Rotating quote from a local list, cycling by day |
| `Sports` | Fetches and formats a score from ESPN via `ESPNClient` |
| `Weather` | Current conditions from Open-Meteo |

## Project Structure

| Path | Purpose |
|---|---|
| `lib/vestaboard_agent.ex` | Top-level `display/1` entry point |
| `lib/vestaboard_agent/agents/` | Agent implementations |
| `lib/vestaboard_agent/tools/` | Tool implementations |
| `lib/vestaboard_agent/clients/` | HTTP clients (Anthropic, ESPN, Open-Meteo, Vestaboard) |
| `lib/vestaboard_agent/agent/registry.ex` | Keyword + LLM routing |
| `lib/vestaboard_agent/formatter.ex` | LLM-based layout and border color selection |
| `lib/vestaboard_agent/dispatcher.ex` | Renders and sends to the board |
| `lib/vestaboard_agent/sandbox/` | Lua sandbox for dynamic tool execution |
| `test/e2e/` | End-to-end tests against a real board and real LLM |

See [`AGENTS.md`](AGENTS.md) for the full architecture and development conventions.

## Configuration

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export VESTABOARD_LOCAL_API_KEY=...   # for local board
```

Optional:

```bash
export TELEGRAM_BOT_TOKEN=...         # enables Telegram bot
export TELEGRAM_ALLOWED_USERS=123,456 # restrict to chat IDs
```

## Development

```bash
mix format                            # format code
mix test                              # unit tests
mix test.e2e                          # end-to-end (requires env vars above)
mix test.e2e test/e2e/07_routing_eval_test.exs  # routing accuracy eval
```
