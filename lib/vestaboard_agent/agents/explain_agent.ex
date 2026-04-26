defmodule VestaboardAgent.Agents.ExplainAgent do
  @moduledoc """
  Explains how the previous prompt was routed.

  Triggered by phrases like "explain that", "why did you", "how did you",
  "what just happened". Reads the last routing decision from the Registry
  and returns a plain-English description of which agent was chosen and why.
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.Agent.Registry
  alias VestaboardAgent.Dispatcher

  @impl true
  def name, do: "explain"

  @impl true
  def keywords,
    do: ["explain that", "why did you", "how did you", "what just happened", "what was that"]

  @impl true
  def description, do: "Explain how and why the previous prompt was routed"

  @impl true
  def handle(_prompt, context) do
    dispatch_fn = Map.get(context, :dispatch_fn, &Dispatcher.dispatch/1)
    text = build_explanation(Registry.last_routing())
    dispatch_fn.(text)
    {:ok, :done}
  end

  # --- Private ---

  defp build_explanation(nil) do
    "No prompts have been routed yet — nothing to explain."
  end

  defp build_explanation(%{prompt: prompt, agent: agent, method: :keyword}) do
    "Routed \"#{prompt}\" to the #{agent} agent via keyword match."
  end

  defp build_explanation(%{prompt: prompt, agent: agent, method: :llm, confidence: conf}) do
    pct = round(conf * 100)
    "Routed \"#{prompt}\" to the #{agent} agent — LLM picked it with #{pct}% confidence."
  end

  defp build_explanation(%{prompt: prompt, method: :fallback, confidence: nil}) do
    "Routed \"#{prompt}\" to dynamic — LLM was unavailable, fell back."
  end

  defp build_explanation(%{prompt: prompt, method: :fallback, confidence: conf}) do
    pct = round(conf * 100)

    "Routed \"#{prompt}\" to dynamic — LLM confidence was low (#{pct}%), fell back."
  end
end
