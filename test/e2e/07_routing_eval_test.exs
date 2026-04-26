defmodule VestaboardAgent.E2E.RoutingEvalTest do
  use ExUnit.Case, async: false

  @moduletag :e2e
  @moduletag timeout: 120_000

  alias VestaboardAgent.Agent.Registry

  # Prompts split by which tier is expected to handle them.
  # Keyword-routed: should resolve without an LLM call.
  # LLM-routed: no keywords match; the LLM + confidence threshold decides.
  @dataset [
    # --- keyword-routed ---
    {"say hello", "greeter"},
    {"good morning", "greeter"},
    {"what's the weather today?", "weather"},
    {"how cold is it outside?", "weather"},
    {"show the forecast", "weather"},
    {"Lakers score", "sports"},
    {"show me NBA standings", "sports"},
    {"nfl scores from last night", "sports"},
    {"play snake", "snake"},
    {"show the clock every 30 seconds", "schedule"},
    {"remind me every hour", "schedule"},
    # --- LLM-routed ---
    {"who invented the telephone?", "conversational"},
    {"what is the speed of light?", "conversational"},
    {"what's the capital of France?", "conversational"},
    {"tell me about black holes", "conversational"},
    {"show the bitcoin price", "dynamic"},
    {"show a countdown to Friday", "dynamic"},
    {"show me today's top news headline", "dynamic"},
    {"did the Celtics win last night?", "sports"},
    {"is it going to rain tomorrow?", "weather"}
  ]

  @pass_threshold 0.85

  setup_all do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        raise """
        Routing eval requires ANTHROPIC_API_KEY.
        Run: export ANTHROPIC_API_KEY=... && mix test.e2e test/e2e/07_routing_eval_test.exs
        """

      _ ->
        :ok
    end
  end

  test "routing accuracy meets #{trunc(@pass_threshold * 100)}% threshold" do
    pace = System.get_env("E2E_PACE_MS", "300") |> String.to_integer()

    results =
      Enum.map(@dataset, fn {prompt, expected} ->
        if pace > 0, do: Process.sleep(pace)

        {:ok, agent} = Registry.resolve(prompt, %{})
        got = agent.name()
        {prompt, expected, got, expected == got}
      end)

    correct = Enum.count(results, fn {_, _, _, pass} -> pass end)
    accuracy = correct / length(results)

    failures =
      results
      |> Enum.reject(fn {_, _, _, pass} -> pass end)
      |> Enum.map(fn {prompt, expected, got, _} ->
        "  \"#{prompt}\"\n    expected: #{expected}\n    got:      #{got}"
      end)

    unless failures == [] do
      IO.puts("\nRouting misses (#{length(failures)}/#{length(results)}):")
      Enum.each(failures, &IO.puts/1)
    end

    assert accuracy >= @pass_threshold,
           "Routing accuracy #{Float.round(accuracy * 100, 1)}% is below #{trunc(@pass_threshold * 100)}% " <>
             "(#{correct}/#{length(results)} correct)"
  end
end
