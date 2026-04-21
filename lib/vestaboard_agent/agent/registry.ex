defmodule VestaboardAgent.Agent.Registry do
  @moduledoc """
  GenServer that holds registered agents and routes prompts to them.

  Agents are matched by keyword: the first registered agent whose keywords
  list contains any word from the prompt wins.

  Built-in agents are registered at startup. Additional agents can be
  registered at runtime via `register/1`.
  """

  use GenServer

  alias VestaboardAgent.Agents.Greeter

  @default_agents [Greeter]

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
  Find the first agent whose keywords match the prompt.

  Returns `{:ok, module}` or `{:error, :no_match}`.
  """
  @spec route(String.t()) :: {:ok, module()} | {:error, :no_match}
  def route(prompt) do
    GenServer.call(__MODULE__, {:route, prompt})
  end

  @doc """
  Route a prompt to an agent and call `handle/2` with the given context.
  """
  @spec handle(String.t(), map()) ::
          {:ok, :done} | {:ok, :running, term()} | {:error, term()}
  def handle(prompt, context \\ %{}) do
    with {:ok, agent} <- route(prompt) do
      agent.handle(prompt, context)
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    {:ok, @default_agents}
  end

  @impl true
  def handle_call({:register, agent}, _from, agents) do
    {:reply, :ok, [agent | agents]}
  end

  def handle_call(:agents, _from, agents) do
    {:reply, agents, agents}
  end

  def handle_call({:route, prompt}, _from, agents) do
    normalized = String.downcase(prompt)

    result =
      Enum.find_value(agents, {:error, :no_match}, fn agent ->
        match? =
          agent.keywords()
          |> Enum.any?(&String.contains?(normalized, String.downcase(&1)))

        if match?, do: {:ok, agent}
      end)

    {:reply, result, agents}
  end
end
