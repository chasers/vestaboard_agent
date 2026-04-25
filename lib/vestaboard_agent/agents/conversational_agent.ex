defmodule VestaboardAgent.Agents.ConversationalAgent do
  @moduledoc """
  Handles open-ended knowledge and conversational prompts by asking the LLM
  for a concise answer formatted for the Vestaboard (6 rows × 22 columns).

  This agent is the fallback for questions like "Who is God?" or "What is
  the capital of France?" that don't require fetching live data or running
  a tool. DynamicAgent remains the fallback for computation/data tasks.

  Pass `llm_opts:` in context to inject a test stub.
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.Clients.Anthropic, as: LLM

  @impl true
  def name, do: "conversational"

  @impl true
  def keywords, do: []

  @impl true
  def handle(prompt, context) do
    llm_opts = Map.get(context, :llm_opts, [])

    case LLM.complete(answer_prompt(prompt), llm_opts) do
      {:ok, text} -> {:ok, text}
      {:error, _} = err -> err
    end
  end

  defp answer_prompt(prompt) do
    """
    You are providing content for a Vestaboard LED display (6 rows × 22 columns).

    Answer the following question or request concisely so it fits on the board:
    - Maximum 6 lines
    - Each line must be 22 characters or fewer
    - Plain text only — no markdown, no bullet symbols, no special formatting
    - Be direct; omit preamble like "Sure!" or "Great question!"

    Question: #{prompt}
    """
  end
end
