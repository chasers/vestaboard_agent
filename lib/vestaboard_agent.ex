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

  alias VestaboardAgent.{Agent.Registry, ConversationContext, Dispatcher, Formatter}

  @display_lock_key :active_display

  @doc """
  Route `prompt` to the right agent, format the result, and send it to the board.

  Any currently running long-running agent (e.g. snake game) is stopped before
  the new prompt is processed.

  Pass `llm_opts:` to inject HTTP stubs in tests.
  Returns `{:ok, map()}` on a successful board write, `{:ok, :done}` when an
  agent dispatched directly (scheduled agents), or `{:error, reason}`.
  """
  @spec display(String.t(), keyword()) :: {:ok, map()} | {:ok, :done} | {:error, term()}
  def display(prompt, opts \\ []) do
    preempt_running_display()
    :ets.insert(:display_lock, {@display_lock_key, self()})

    try do
      do_display(prompt, opts)
    after
      :ets.delete(:display_lock, @display_lock_key)
    end
  end

  defp do_display(prompt, opts) do
    llm_opts = Keyword.get(opts, :llm_opts, [])
    history = ConversationContext.history()
    context = %{llm_opts: llm_opts, history: history}

    case Registry.handle(prompt, context) do
      {:ok, text} when is_binary(text) ->
        format_opts = Keyword.merge(opts, history: history)
        {:ok, formatted, render_opts} = Formatter.format(text, format_opts)

        case Dispatcher.dispatch(formatted, render_opts) do
          {:ok, _} = result ->
            ConversationContext.push(prompt, formatted, render_opts)
            result

          {:error, _} = err ->
            err
        end

      {:ok, :done} ->
        {:ok, :done}

      {:ok, :running, _} = running ->
        running

      {:error, _} = err ->
        err
    end
  end

  defp preempt_running_display do
    case :ets.lookup(:display_lock, @display_lock_key) do
      [{@display_lock_key, pid}] when pid != self() ->
        if Process.alive?(pid) do
          require Logger
          Logger.info("[display] stopping running agent (#{inspect(pid)}) for new prompt")
          Process.exit(pid, :kill)
          ref = Process.monitor(pid)
          receive do
            {:DOWN, ^ref, :process, ^pid, _} -> :ok
          after
            3_000 -> :ok
          end
        end
        :ets.delete(:display_lock, @display_lock_key)

      _ ->
        :ok
    end
  end
end
