defmodule VestaboardAgent do
  @moduledoc """
  Top-level convenience API for the Vestaboard agent.

  ## Quick start

      VestaboardAgent.display("happy Tuesday")
      VestaboardAgent.display("show weather")
      VestaboardAgent.display("show the time")

  Prompts are routed through the agent registry (keyword match → LLM routing →
  dynamic Lua tool generation). The agent's output is then formatted by the LLM
  (layout + border color) and sent to the board.

  Conversation history (last 5 board states) is automatically passed to the LLM
  on each call, enabling follow-up prompts like "make it bigger" or "do that again".
  """

  alias VestaboardAgent.{
    Agent.Registry,
    AgentSupervisor,
    ConversationContext,
    Dispatcher,
    Formatter
  }

  require Logger

  @display_lock_key :active_display

  @doc """
  Route `prompt` to the right agent, format the result, and send it to the board.

  Each invocation runs the agent as a supervised child of `AgentSupervisor`.
  Any currently running long-running agent (e.g. snake game) is cancelled before
  the new prompt is processed.

  Pass `llm_opts:` to inject HTTP stubs in tests.
  Returns `{:ok, map()}` on a successful board write, `{:ok, :done}` when an
  agent dispatched directly (scheduled agents), or `{:error, reason}`.
  """
  @spec display(String.t(), keyword()) :: {:ok, map()} | {:ok, :done} | {:error, term()}
  def display(prompt, opts \\ []) do
    preempt_running_display()

    llm_opts = Keyword.get(opts, :llm_opts, [])
    history = ConversationContext.history()
    context = %{llm_opts: llm_opts, history: history}

    case Registry.resolve(prompt, context) do
      {:error, _} = err ->
        err

      {:ok, agent} ->
        {:ok, server_pid} = AgentSupervisor.run(agent, prompt, context, awaiter: self())
        ref = Process.monitor(server_pid)
        :ets.insert(:display_lock, {@display_lock_key, server_pid})

        agent_result =
          receive do
            {:agent_result, ^server_pid, result} ->
              Process.demonitor(ref, [:flush])
              result

            {:DOWN, ^ref, :process, ^server_pid, _reason} ->
              {:error, :cancelled}
          end

        :ets.delete(:display_lock, @display_lock_key)
        if Process.alive?(server_pid), do: AgentSupervisor.cancel(server_pid)

        handle_agent_result(agent_result, prompt, opts, history)
    end
  end

  defp handle_agent_result({:ok, text}, prompt, opts, history) when is_binary(text) do
    format_opts = Keyword.merge(opts, history: history)
    {:ok, formatted, render_opts} = Formatter.format(text, format_opts)

    case Dispatcher.dispatch(formatted, render_opts) do
      {:ok, _} = result ->
        ConversationContext.push(prompt, formatted, render_opts)
        result

      {:error, _} = err ->
        err
    end
  end

  defp handle_agent_result({:ok, :done}, _prompt, _opts, _history), do: {:ok, :done}
  defp handle_agent_result({:ok, :running, _} = r, _prompt, _opts, _history), do: r
  defp handle_agent_result({:error, _} = err, _prompt, _opts, _history), do: err

  defp preempt_running_display do
    case :ets.lookup(:display_lock, @display_lock_key) do
      [{@display_lock_key, server_pid}] ->
        if Process.alive?(server_pid) do
          Logger.info(
            "[display] cancelling running agent (#{inspect(server_pid)}) for new prompt"
          )

          AgentSupervisor.cancel(server_pid)
        end

        :ets.delete(:display_lock, @display_lock_key)

      _ ->
        :ok
    end
  end
end
