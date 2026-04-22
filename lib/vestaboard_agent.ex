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

  @doc """
  Route `prompt` to the right agent, format the result, and send it to the board.

  Pass `llm_opts:` to inject HTTP stubs in tests.
  Returns `{:ok, map()}` on a successful board write, `{:ok, :done}` when an
  agent dispatched directly (scheduled agents), or `{:error, reason}`.
  """
  @spec display(String.t(), keyword()) :: {:ok, map()} | {:ok, :done} | {:error, term()}
  def display(prompt, opts \\ []) do
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
end
