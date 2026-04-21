defmodule VestaboardAgent.ToolRegistry do
  @moduledoc """
  Stores and retrieves tools by name.

  Supports two kinds of entries:
  - `{:module, module}` — a compiled Elixir module that implements `Tool`
  - `{:script, content}` — a Lua script string run via `LuaTool`

  Lua scripts are persisted as `.lua` files in a configurable directory
  (defaults to `priv/lua_tools/`) and reloaded automatically on restart.

  Built-in tools (Clock, Weather, Quote, Greeting) are registered at startup.

  ## Configuration

      config :vestaboard_agent, :tool_registry,
        scripts_dir: "/path/to/scripts"

  ## Example

      ToolRegistry.register(:clock, VestaboardAgent.Tools.Clock)
      ToolRegistry.register_script(:greeter, "return 'Hello!'")

      {:ok, output} = ToolRegistry.run(:clock, %{})
      ToolRegistry.list()
      ToolRegistry.unregister(:greeter)
  """

  use GenServer

  alias VestaboardAgent.{LuaTool, Tools}

  @default_tools [
    clock: Tools.Clock,
    weather: Tools.Weather,
    quote: Tools.Quote,
    greeting: Tools.Greeting
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Register a module-based tool under `name`."
  @spec register(atom(), module()) :: :ok
  def register(name, module) when is_atom(name) and is_atom(module) do
    GenServer.call(__MODULE__, {:register, name, {:module, module}})
  end

  @doc "Register a Lua script under `name` and persist it to disk."
  @spec register_script(atom(), String.t()) :: :ok | {:error, term()}
  def register_script(name, script) when is_atom(name) and is_binary(script) do
    GenServer.call(__MODULE__, {:register_script, name, script})
  end

  @doc "Remove a tool from the registry (and delete its script file if applicable)."
  @spec unregister(atom()) :: :ok
  def unregister(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  @doc "Look up a tool entry by name."
  @spec get(atom()) :: {:ok, {:module, module()} | {:script, String.t()}} | {:error, :not_found}
  def get(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  @doc "Run a registered tool by name."
  @spec run(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def run(name, context \\ %{}) when is_atom(name) do
    GenServer.call(__MODULE__, {:run, name, context})
  end

  @doc "Return all registered tool names and their entry types."
  @spec list() :: [{atom(), :module | :script}]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    scripts_dir = Keyword.get(opts, :scripts_dir) || configured_scripts_dir()
    File.mkdir_p!(scripts_dir)

    tools =
      @default_tools
      |> Enum.into(%{}, fn {name, mod} -> {name, {:module, mod}} end)
      |> Map.merge(load_scripts(scripts_dir))

    {:ok, %{tools: tools, scripts_dir: scripts_dir}}
  end

  @impl true
  def handle_call({:register, name, entry}, _from, state) do
    {:reply, :ok, put_in(state, [:tools, name], entry)}
  end

  def handle_call({:register_script, name, script}, _from, state) do
    with :ok <- validate_script(script),
         :ok <- write_script(state.scripts_dir, name, script) do
      {:reply, :ok, put_in(state, [:tools, name], {:script, script})}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    if match?({:script, _}, Map.get(state.tools, name)) do
      delete_script(state.scripts_dir, name)
    end

    {:reply, :ok, update_in(state, [:tools], &Map.delete(&1, name))}
  end

  def handle_call({:get, name}, _from, state) do
    case Map.get(state.tools, name) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry}, state}
    end
  end

  def handle_call({:run, name, context}, _from, state) do
    result =
      case Map.get(state.tools, name) do
        nil -> {:error, :not_found}
        {:module, mod} -> mod.run(context)
        {:script, script} -> LuaTool.run(script, context)
      end

    {:reply, result, state}
  end

  def handle_call(:list, _from, state) do
    entries =
      Enum.map(state.tools, fn
        {name, {:module, _}} -> {name, :module}
        {name, {:script, _}} -> {name, :script}
      end)

    {:reply, entries, state}
  end

  # --- Private ---

  defp configured_scripts_dir do
    cfg = Application.get_env(:vestaboard_agent, :tool_registry, [])
    cfg[:scripts_dir] || default_scripts_dir()
  end

  defp default_scripts_dir do
    Application.app_dir(:vestaboard_agent, "priv/lua_tools")
  end

  defp load_scripts(dir) do
    dir
    |> Path.join("*.lua")
    |> Path.wildcard()
    |> Enum.into(%{}, fn path ->
      name = path |> Path.basename(".lua") |> String.to_atom()
      {name, {:script, File.read!(path)}}
    end)
  end

  defp validate_script(script) do
    case LuaTool.run(script, %{now: "2024-01-01T00:00:00Z"}) do
      {:error, "Failed to compile Lua!" <> _} = err -> err
      _ -> :ok
    end
  end

  defp write_script(dir, name, script) do
    path = script_path(dir, name)
    File.write(path, script)
  end

  defp delete_script(dir, name) do
    dir |> script_path(name) |> File.rm()
  end

  defp script_path(dir, name), do: Path.join(dir, "#{name}.lua")
end
