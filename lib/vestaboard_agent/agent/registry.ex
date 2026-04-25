defmodule VestaboardAgent.Agent.Registry do
  @moduledoc """
  Routes prompts to agents via keyword matching with an LLM fallback.

  ## Routing order

  1. **Keyword match** — first registered agent whose keywords appear in the prompt wins.
  2. **LLM routing** — if no keyword match, the LLM picks an agent from the registered list.
     Requires `ANTHROPIC_API_KEY` (or config). If not configured, skips to step 3.
  3. **DynamicAgent** — LLM generates a Lua tool for the prompt on the fly.

  Pass `llm_opts:` in the context map to inject test stubs into LLM calls:

      Registry.handle("show btc price", %{llm_opts: [plug: {Req.Test, MyTest}]})
  """

  use GenServer

  alias VestaboardAgent.Agents.{
    ConversationalAgent,
    DisplayAgent,
    DynamicAgent,
    Greeter,
    ScheduleAgent,
    SnakeAgent,
    SportsAgent,
    WeatherAgent
  }

  alias VestaboardAgent.Clients.Anthropic, as: LLM

  @default_agents [
    DisplayAgent,
    Greeter,
    WeatherAgent,
    SportsAgent,
    ScheduleAgent,
    SnakeAgent,
    ConversationalAgent,
    DynamicAgent
  ]

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register an agent module with the registry."
  @spec register(module()) :: :ok
  def register(agent) do
    GenServer.call(__MODULE__, {:register, agent})
  end

  @doc "Return all registered agent modules."
  @spec agents() :: [module()]
  def agents do
    GenServer.call(__MODULE__, :agents)
  end

  @doc """
  Find the first agent whose keywords match the prompt (keyword-only, no LLM).

  Returns `{:ok, module}` or `{:error, :no_match}`.
  """
  @spec route(String.t()) :: {:ok, module()} | {:error, :no_match}
  def route(prompt) do
    GenServer.call(__MODULE__, {:route, prompt})
  end

  @doc """
  Resolve a prompt to an agent module without calling `handle/2`.

  Applies keyword matching then LLM routing. Returns `{:ok, module}` or
  `{:error, :no_match}` when no key is configured and no keyword matched.
  Use this when you want to start the agent via `AgentSupervisor.run/4`
  instead of calling `handle/2` inline.
  """
  @spec resolve(String.t(), map()) :: {:ok, module()} | {:error, :no_match}
  def resolve(prompt, context \\ %{}) do
    case route(prompt) do
      {:ok, agent} ->
        {:ok, agent}

      {:error, :no_match} ->
        llm_opts = Map.get(context, :llm_opts, [])
        history = Map.get(context, :history, [])
        agents_meta = Enum.map(agents(), fn a -> {a.name(), a.keywords()} end)
        routing_opts = Keyword.put(llm_opts, :history, history)

        case LLM.route_agent(prompt, agents_meta, routing_opts) do
          {:ok, name} ->
            case find_by_name(name) do
              {:ok, agent} -> {:ok, agent}
              :error -> {:ok, DynamicAgent}
            end

          {:error, :missing_api_key} ->
            {:error, :no_match}

          {:error, _} ->
            {:ok, DynamicAgent}
        end
    end
  end

  @doc """
  Route a prompt to an agent and call `handle/2`.

  Falls back to LLM routing when no keyword match is found, then to
  `DynamicAgent`. Returns `{:error, :no_match}` only when no API key
  is configured and keyword matching also fails.
  """
  @spec handle(String.t(), map()) ::
          {:ok, :done} | {:ok, :running, term()} | {:error, term()}
  def handle(prompt, context \\ %{}) do
    case resolve(prompt, context) do
      {:ok, agent} -> agent.handle(prompt, context)
      {:error, _} = err -> err
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    init_ets_table(:snake_locks)
    init_ets_table(:display_lock)
    {:ok, @default_agents}
  end

  @impl true
  def handle_call({:register, agent}, _from, agents) do
    {:reply, :ok, [agent | agents]}
  end

  @impl true
  def handle_call(:agents, _from, agents) do
    {:reply, agents, agents}
  end

  @impl true
  def handle_call({:route, prompt}, _from, agents) do
    normalized = String.downcase(prompt)

    result =
      Enum.find_value(agents, {:error, :no_match}, fn agent ->
        match? = Enum.any?(agent.keywords(), &String.contains?(normalized, String.downcase(&1)))
        if match?, do: {:ok, agent}
      end)

    {:reply, result, agents}
  end

  # --- Private ---

  defp init_ets_table(name) do
    :ets.new(name, [:set, :public, :named_table])
  rescue
    ArgumentError -> :ok
  end

  defp find_by_name(name) do
    case Enum.find(agents(), fn a -> a.name() == name end) do
      nil -> :error
      agent -> {:ok, agent}
    end
  end
end
