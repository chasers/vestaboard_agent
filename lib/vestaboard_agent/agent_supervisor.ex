defmodule VestaboardAgent.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for long-running agent invocations.

  Each call to `run/3` spawns an `AgentServer` child that executes
  `agent.handle(prompt, context)` asynchronously. The supervisor keeps the
  process alive until it finishes naturally or is cancelled.

  ## Example

      {:ok, pid} = AgentSupervisor.run(Greeter, "say hello", %{})
      AgentSupervisor.status(pid)   # => {:running, nil} | {:done, result}
      AgentSupervisor.cancel(pid)   # => :ok
  """

  use DynamicSupervisor

  alias VestaboardAgent.AgentServer

  # --- Client API ---

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start an agent invocation. Returns `{:ok, pid}` immediately."
  @spec run(module(), String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def run(agent, prompt, context \\ %{}) do
    spec = {AgentServer, [agent: agent, prompt: prompt, context: context]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc "Check the status of a running agent."
  @spec status(pid()) :: {:running | :done | :cancelled | {:error, term()}, term()}
  def status(pid), do: AgentServer.status(pid)

  @doc "Cancel a running agent and remove it from the supervisor."
  @spec cancel(pid()) :: :ok
  def cancel(pid) do
    AgentServer.cancel(pid)
    DynamicSupervisor.terminate_child(__MODULE__, pid)
    :ok
  end

  @doc "List all active agent processes."
  @spec list() :: [{:undefined, pid(), :worker, [module()]}]
  def list, do: DynamicSupervisor.which_children(__MODULE__)

  # --- Supervisor callback ---

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
