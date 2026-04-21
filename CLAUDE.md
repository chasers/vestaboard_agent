# VestaboardAgent — Claude Code Guidelines

## Tests are required

Every new module needs a corresponding test file. Every public function needs at least one test covering the happy path. Run `mix test` after writing any code, and again before marking any implementation task complete.

Test files live under `test/` mirroring the `lib/` path:
- `lib/vestaboard_agent/tools/greeting.ex` → `test/vestaboard_agent/tools/greeting_test.exs`

## Project structure

| Path | Purpose |
|---|---|
| `lib/vestaboard_agent/tool.ex` | `Tool` behaviour |
| `lib/vestaboard_agent/tools/` | Tool implementations |
| `lib/vestaboard_agent/agents/` | Agent implementations |
| `lib/vestaboard_agent/sandbox.ex` | `Sandbox` behaviour + dispatch |
| `lib/vestaboard_agent/sandbox/lua.ex` | Lua sandbox backend |
| `lib/vestaboard_agent/lua_api.ex` | Elixir bindings exposed to Lua scripts |
| `lib/vestaboard_agent/lua_tool.ex` | Public entry point for running script tools |

See `AGENTS.md` for architecture details.
