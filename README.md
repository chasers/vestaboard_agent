# VestaboardAgent

An Elixir harness for building agents that drive a [Vestaboard](https://www.vestaboard.com/) display. The project provides a structured framework for composing, scheduling, and dispatching messages to a Vestaboard over the Vestaboard API.

## Overview

Vestaboard is a connected split-flap display. This project wraps the Vestaboard API in an agent harness so you can:

- Build composable message-generating agents (weather, quotes, countdowns, etc.)
- Schedule agents to run on a cadence
- Route and render agent output to one or more boards
- Test agents locally without a physical board

## Getting Started

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Start an interactive session
iex -S mix
```

## Project Structure

| Path | Purpose |
|---|---|
| `lib/vestaboard_agent.ex` | Top-level module and entry point |
| `lib/vestaboard_agent/agents/` | Agents — user-initiated interactions that drive the board |
| `lib/vestaboard_agent/tools/` | Tools — composable modules that fetch or generate content |
| `test/` | ExUnit tests |

See [agents.md](agents.md) for the full architecture: how agents respond to user prompts and how tools are composed within them.

## Configuration

Copy any required API credentials into your config:

```elixir
# config/runtime.exs
config :vestaboard_agent,
  api_key: System.get_env("VESTABOARD_API_KEY"),
  board_id: System.get_env("VESTABOARD_BOARD_ID")
```

## Dependencies

Dependencies will be added to `mix.exs` as the project grows. Likely candidates:

- `req` — HTTP client for the Vestaboard API
- `jason` — JSON encoding/decoding
- `quantum` — cron-style job scheduling for periodic agents

## Development

```bash
mix format        # format code
mix test          # run test suite
mix docs          # generate ExDoc documentation
```
