# Agents & Tools

This document describes the two-layer architecture of VestaboardAgent: **Tools** that produce content, and **Agents** that respond to user prompts by orchestrating those tools.

---

## Development Rules

### Tests are required

Every new module needs a corresponding test file. Every public function needs at least one test covering the happy path. Run `mix test` after writing any code, and again before marking any implementation task complete.

Test files live under `test/` mirroring the `lib/` path:
- `lib/vestaboard_agent/tools/greeting.ex` → `test/vestaboard_agent/tools/greeting_test.exs`

### New routing behavior always goes in an agent

Never add special cases to `do_display/2` or `VestaboardAgent.display/2` to handle new prompt patterns. If a new routing behavior is needed, create a new agent module and register it in `VestaboardAgent.Agent.Registry`. This keeps the top-level display pipeline stable and all routing logic discoverable in one place.

### Project structure

| Path | Purpose |
|---|---|
| `lib/vestaboard_agent/tool.ex` | `Tool` behaviour |
| `lib/vestaboard_agent/tools/` | Tool implementations |
| `lib/vestaboard_agent/agents/` | Agent implementations |
| `lib/vestaboard_agent/agent/registry.ex` | Routes prompts to agents |
| `lib/vestaboard_agent/clients/` | All HTTP clients (ESPN, Anthropic, OpenMeteo, Vestaboard) |
| `lib/vestaboard_agent/sandbox.ex` | `Sandbox` behaviour + dispatch |
| `lib/vestaboard_agent/sandbox/lua.ex` | Lua sandbox backend |
| `lib/vestaboard_agent/lua_api.ex` | Elixir bindings exposed to Lua scripts |
| `lib/vestaboard_agent/lua_tool.ex` | Public entry point for running script tools |

---

## Tools

A tool is a module that fetches or generates a piece of board-ready content. Tools are pure building blocks — they take a context map and return a result.

### Tool Behaviour

```elixir
defmodule VestaboardAgent.Tool do
  @callback name() :: String.t()
  @callback run(context :: map()) :: {:ok, term()} | {:error, term()}
end
```

### Writing a Tool

Create a module under `lib/vestaboard_agent/tools/`:

```elixir
defmodule VestaboardAgent.Tools.Weather do
  @behaviour VestaboardAgent.Tool

  @impl true
  def name, do: "weather"

  @impl true
  def run(%{config: config}) do
    # fetch current conditions, return a display string
    {:ok, "Sunny 72F"}
  end
end
```

### Planned Tools

| Tool | Description |
|---|---|
| `Weather` | Current conditions from a weather API |
| `Countdown` | Days/hours until a target date |
| `Quote` | Rotating quote from a local list or remote source |
| `Custom` | Arbitrary text passed directly by the caller |

### Tool Context

| Key | Type | Description |
|---|---|---|
| `:now` | `DateTime` | Current UTC time |
| `:board_id` | `String` | Target board identifier |
| `:config` | `map` | Application config from `config/runtime.exs` |

---

## Agents

An agent is a user-facing interaction. It is started when a user prompts the Vestaboard service to do something ("show the weather", "start a countdown to Friday", "display a motivational quote every hour"). The agent interprets the prompt, selects and runs the appropriate tools, and drives the board for the duration of its task.

### Agent Behaviour

```elixir
defmodule VestaboardAgent.Agent do
  @callback name() :: String.t()
  @callback handle(prompt :: String.t(), context :: map()) ::
              {:ok, :done}
              | {:ok, :running, state :: term()}
              | {:error, term()}
end
```

| Callback | Description |
|---|---|
| `name/0` | Identifies the agent in logs and the registry |
| `handle/2` | Receives the user prompt and acts on it; may run once or stay running |

### Agent Lifecycle

```
User Prompt
    │
    ▼
Agent Registry    (match prompt to the right agent)
    │
    ▼
Agent.handle/2    (parse intent, call tools, produce message)
    │
    ▼
Renderer          (text → 6×22 character grid)
    │
    ▼
Dispatcher        (HTTP POST to Vestaboard API)
```

A stateless agent returns `{:ok, :done}` after a single board update. A long-running agent (e.g. a countdown that refreshes every minute) returns `{:ok, :running, state}` and is kept alive by a supervisor until it completes or is cancelled.

### Example: Countdown Agent

```elixir
defmodule VestaboardAgent.Agents.Countdown do
  @behaviour VestaboardAgent.Agent

  @impl true
  def name, do: "countdown"

  @impl true
  def handle(prompt, context) do
    # parse a target date out of the prompt
    # run the Countdown tool
    # schedule recurring board updates
    {:ok, :running, %{target: parsed_date}}
  end
end
```

### Testing Agents

```elixir
defmodule VestaboardAgent.Agents.CountdownTest do
  use ExUnit.Case

  test "starts running for a future date" do
    assert {:ok, :running, _state} =
             VestaboardAgent.Agents.Countdown.handle("countdown to Friday", %{})
  end
end
```

Use `VestaboardAgent.FakeDispatcher` in tests so no real HTTP calls are made.

---

## External API Clients

When a tool needs to call an external HTTP API, put all HTTP and JSON parsing in a dedicated client module rather than inside the tool itself. The tool then delegates to the client and handles only selection and formatting.

```
lib/vestaboard_agent/clients/espn.ex  ← all HTTP, JSON, typed structs
lib/vestaboard_agent/tools/sports.ex  ← filters, formats, no HTTP
```

This separation means:
- The client is independently testable with `Req.Test` stubs.
- The tool tests never touch HTTP — they stub the client function directly.
- Swapping the upstream API only requires changing the client.

### Client conventions

- One public function per logical query (e.g. `scoreboard/2`).
- Return typed maps/structs, not raw JSON.
- Match `{:ok, %{status: 200, body: body}}` explicitly; all other shapes → `{:error, reason}`.
- Accept a `plug:` opt for test injection; also check app config for a global plug override.

```elixir
defp build_req(opts) do
  base = Req.new(retry: false)
  plug = Keyword.get(opts, :plug) ||
         get_in(Application.get_env(:vestaboard_agent, :my_client, []), [:plug])
  if plug, do: Req.merge(base, plug: plug), else: base
end
```

---

## Long-Running Agents with Refresh Loops

An agent that must periodically re-fetch and re-display (e.g. live sports scores) runs a blocking loop inside `handle/2`. The loop uses `Process.send_after(self(), :token, ms)` + `receive` rather than `Process.sleep` so the name `:token` is visible in crash dumps and the process is still interruptible via `Process.exit(pid, :kill)`.

```elixir
defp refresh_loop(ctx, sports_fn, dispatch_fn, refresh_ms) do
  Process.send_after(self(), :sports_refresh, refresh_ms)

  receive do
    :sports_refresh ->
      case sports_fn.(ctx) do
        {:ok, %{text: text, live: true}}  -> dispatch_fn.(text); refresh_loop(...)
        {:ok, %{text: text, live: false}} -> dispatch_fn.(text)   # done
        {:error, _}                       -> :ok                  # stop silently
      end
  end
end
```

### Testability

Inject three context keys to avoid real HTTP, real dispatch, and real timing in tests:

| Key | Default | Test value |
|---|---|---|
| `:sports_fn` | `&Tools.Sports.run/1` | function returning canned `{:ok, %{...}}` |
| `:dispatch_fn` | `&Dispatcher.dispatch/1` | function sending `{:dispatched, text}` to test pid |
| `:refresh_ms` | `60_000` | `0` (fires immediately) |

---

## Dynamic Script Tools

If an agent determines that no existing tool fits the user's request, it can write a new tool as a script and execute it immediately — no Elixir compilation required.

### Sandbox Interface

All script execution goes through `VestaboardAgent.Sandbox`, a behaviour with a single callback:

```elixir
@callback run(script :: String.t(), context :: map()) ::
            {:ok, String.t()} | {:error, term()}
```

The active backend is set in config (defaults to Lua):

```elixir
# config/runtime.exs
config :vestaboard_agent, :sandbox, VestaboardAgent.Sandbox.Lua
```

To swap runtimes, implement the behaviour and point the config at the new module — nothing else changes.

### Script Contract

Scripts receive a `context` object and must return a single string — the message to display on the board.

| `context` key | Type | Value |
|---|---|---|
| `context.now` | string | ISO-8601 UTC timestamp |
| `context.board_id` | string | Target board identifier |

### Running a Script Tool

```elixir
script = """
function run(ctx)
  return "Time is " .. ctx.now
end

return run(context)
"""

{:ok, message} = VestaboardAgent.LuaTool.run(script, context)
# or call the sandbox directly:
{:ok, message} = VestaboardAgent.Sandbox.run(script, context)
```

### Lua Backend

The default backend is `VestaboardAgent.Sandbox.Lua`, which runs scripts inside [Luerl](https://github.com/rvirding/luerl) (a Lua VM on the BEAM) via the [`lua`](https://hex.pm/packages/lua) library.

Elixir functions are exposed to Lua scripts via `VestaboardAgent.LuaAPI` under the `vestaboard` namespace:

| Lua function | Description |
|---|---|
| `vestaboard.log(msg)` | Write a message to Elixir Logger |
| `vestaboard.truncate(str, len)` | Truncate a string to `len` characters |

Add new bindings by adding `deflua` functions to `lib/vestaboard_agent/lua_api.ex`.

### Implementing a New Sandbox Backend

```elixir
defmodule VestaboardAgent.Sandbox.MyRuntime do
  @behaviour VestaboardAgent.Sandbox

  @impl true
  def run(script, context) do
    # execute script, inject context, return {:ok, string} | {:error, reason}
  end
end
```

### Agent-Authored Tools

When an agent (backed by an LLM) decides it needs a new tool, the flow is:

```
Agent receives prompt
    │
    ▼
Check tool registry — no match found
    │
    ▼
LLM generates a script for the configured sandbox
    │
    ▼
VestaboardAgent.Sandbox.run(script, context)
    │
    ▼
Optionally persist the script to the tool registry for reuse
```

The sandbox prevents scripts from accessing the filesystem or network directly. All external I/O must go through explicit bindings registered with the active backend.

---

## Elixir Best Practices

### Return tagged tuples from all public functions

Every public function that can fail must return `{:ok, value}` or `{:error, reason}`. Never raise from a function that a caller is expected to handle — raise only for truly unrecoverable programmer errors.

```elixir
# good
def run(context), do: {:ok, "result"}

# bad — caller cannot pattern-match on failure
def run(context), do: "result"
```

### Implement behaviours explicitly

Always declare `@behaviour` and mark each callback with `@impl true`. This catches missing or mistyped callbacks at compile time.

```elixir
defmodule VestaboardAgent.Tools.Weather do
  @behaviour VestaboardAgent.Tool

  @impl true
  def name, do: "weather"

  @impl true
  def run(context), do: {:ok, "Sunny"}
end
```

### Use `@moduledoc` and `@doc`

Every public module gets a `@moduledoc`. Every public function gets a `@doc`. One-line summaries are fine — the goal is discoverability in `iex` and generated docs, not prose.

### Keep functions small and pattern-match at the head

Prefer multiple function clauses over `cond`/`case` inside a single body. Pattern matching at the function head is easier to test and extend.

```elixir
# good
defp extract(%{"currentMessage" => %{"text" => chars}}), do: chars
defp extract(body) when is_list(body), do: body
defp extract(body), do: body

# avoid
defp extract(body) do
  cond do
    is_map(body) and Map.has_key?(body, "currentMessage") -> ...
    is_list(body) -> ...
    true -> body
  end
end
```

### Avoid application config in library code

Read config with `Application.get_env` only at the boundary (dispatch functions, not deep helpers). Pass values as arguments into pure functions so they are easy to test without manipulating global state.

### Test every public function

Each module under `lib/` must have a matching file under `test/`. Every public function needs at least one test covering the happy path. Run `mix test` after every change.

### Use `async: true` by default, `async: false` only when touching global state

Tests that modify `Application` env (client backend, sandbox config) must use `async: false`. Everything else should use `async: true` to keep the suite fast.

### Prefer `Req` for HTTP, pattern-match on status

Always match on `{:ok, %{status: status, body: body}}` and handle non-2xx explicitly. Never let an unexpected status code silently succeed.

```elixir
case Req.get(url) do
  {:ok, %{status: 200, body: body}} -> {:ok, body}
  {:ok, %{status: status}}          -> {:error, {:http, status}}
  {:error, reason}                  -> {:error, reason}
end
```

### Scripts (`.exs`) use plain variables, not module attributes

Module attributes (`@foo`) are only valid inside a module. Top-level script variables are plain Elixir:

```elixir
# good — .exs script
known_macs = ["4C:93:A6:03:5C:5B"]
MyModule.run(known_macs)

# bad
@known_macs ["4C:93:A6:03:5C:5B"]  # raises outside a module
```
