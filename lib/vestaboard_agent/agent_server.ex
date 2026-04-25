defmodule VestaboardAgent.AgentServer do
  @moduledoc """
  Runs a single agent invocation as a supervised, cancellable process.

  State machine:
    :running  → the agent Task is in flight
    :done     → Task finished; result stored
    :cancelled → Task was shut down by cancel/1
    {:error, reason} → Task exited abnormally

  Pass `awaiter: pid` in opts to receive `{:agent_result, server_pid, result}`
  when the task completes (success or error). The awaiter also receives a
  `{:DOWN, ref, ...}` message via its monitor if the server is killed externally.

  Start via `VestaboardAgent.AgentSupervisor.run/3` rather than directly.
  """

  use GenServer

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Return the current `{status, result}` of the agent. Result is nil while running."
  @spec status(pid()) :: {:running | :done | :cancelled | {:error, term()}, term()}
  def status(pid), do: GenServer.call(pid, :status)

  @doc "Cancel a running agent. No-op if already done."
  @spec cancel(pid()) :: :ok
  def cancel(pid), do: GenServer.call(pid, :cancel)

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    prompt = Keyword.fetch!(opts, :prompt)
    context = Keyword.get(opts, :context, %{})
    awaiter = Keyword.get(opts, :awaiter)

    task = Task.async(fn -> agent.handle(prompt, context) end)

    {:ok, %{task: task, status: :running, result: nil, awaiter: awaiter}}
  end

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    notify_awaiter(state.awaiter, self(), result)
    {:noreply, %{state | task: nil, status: :done, result: result}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    notify_awaiter(state.awaiter, self(), {:error, {:agent_crash, reason}})
    {:noreply, %{state | task: nil, status: {:error, reason}}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {state.status, state.result}, state}
  end

  def handle_call(:cancel, _from, %{task: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:cancel, _from, %{task: task} = state) do
    Task.shutdown(task, :brutal_kill)
    {:reply, :ok, %{state | task: nil, status: :cancelled}}
  end

  # --- Private ---

  defp notify_awaiter(nil, _server, _result), do: :ok
  defp notify_awaiter(awaiter, server, result), do: send(awaiter, {:agent_result, server, result})
end
