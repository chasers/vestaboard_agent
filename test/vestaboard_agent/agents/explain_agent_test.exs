defmodule VestaboardAgent.Agents.ExplainAgentTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agent.Registry
  alias VestaboardAgent.Agents.ExplainAgent

  setup do
    # Clear routing info before each test
    :ets.delete_all_objects(:routing_info)
    :ok
  end

  describe "name/0 and keywords/0" do
    test "has the right name" do
      assert ExplainAgent.name() == "explain"
    end

    test "triggers on explain-style phrases" do
      assert "explain that" in ExplainAgent.keywords()
      assert "why did you" in ExplainAgent.keywords()
      assert "how did you" in ExplainAgent.keywords()
    end
  end

  defp capture_dispatch do
    parent = self()
    fn text -> send(parent, {:dispatched, text}) end
  end

  describe "handle/2 — no prior routing" do
    test "dispatches a message and returns :done when no prompt has been routed yet" do
      assert {:ok, :done} =
               ExplainAgent.handle("explain that", %{dispatch_fn: capture_dispatch()})

      assert_receive {:dispatched, text}
      assert String.contains?(text, "No prompts")
    end
  end

  describe "handle/2 — keyword routing" do
    test "explains a keyword-routed decision" do
      :ets.insert(
        :routing_info,
        {:last, %{prompt: "Lakers score", agent: "sports", method: :keyword, confidence: nil}}
      )

      assert {:ok, :done} =
               ExplainAgent.handle("explain that", %{dispatch_fn: capture_dispatch()})

      assert_receive {:dispatched, text}
      assert String.contains?(text, "Lakers score")
      assert String.contains?(text, "sports")
      assert String.contains?(text, "keyword")
    end
  end

  describe "handle/2 — LLM routing" do
    test "explains a high-confidence LLM decision with percentage" do
      :ets.insert(
        :routing_info,
        {:last,
         %{
           prompt: "who invented the phone?",
           agent: "conversational",
           method: :llm,
           confidence: 0.87
         }}
      )

      assert {:ok, :done} =
               ExplainAgent.handle("why did you do that", %{dispatch_fn: capture_dispatch()})

      assert_receive {:dispatched, text}
      assert String.contains?(text, "conversational")
      assert String.contains?(text, "87%")
    end
  end

  describe "handle/2 — fallback routing" do
    test "explains a low-confidence fallback with percentage" do
      :ets.insert(
        :routing_info,
        {:last,
         %{prompt: "show a random gif", agent: "dynamic", method: :fallback, confidence: 0.3}}
      )

      assert {:ok, :done} =
               ExplainAgent.handle("what just happened", %{dispatch_fn: capture_dispatch()})

      assert_receive {:dispatched, text}
      assert String.contains?(text, "dynamic")
      assert String.contains?(text, "30%")
    end

    test "explains a nil-confidence fallback (LLM unavailable)" do
      :ets.insert(
        :routing_info,
        {:last, %{prompt: "do something", agent: "dynamic", method: :fallback, confidence: nil}}
      )

      assert {:ok, :done} =
               ExplainAgent.handle("explain that", %{dispatch_fn: capture_dispatch()})

      assert_receive {:dispatched, text}
      assert String.contains?(text, "dynamic")
      assert String.contains?(text, "unavailable")
    end
  end

  describe "registry integration" do
    test "ExplainAgent is registered by default" do
      assert ExplainAgent in Registry.agents()
    end

    test "last_routing/0 returns nil before any resolve" do
      :ets.delete_all_objects(:routing_info)
      assert Registry.last_routing() == nil
    end

    test "last_routing/0 reflects the most recent resolve" do
      Application.put_env(:vestaboard_agent, :llm, api_key: nil)
      Registry.resolve("Lakers score")
      routing = Registry.last_routing()
      assert routing.agent == "sports"
      assert routing.method == :keyword
    end

    test "resolving ExplainAgent does not overwrite the previous routing" do
      Application.put_env(:vestaboard_agent, :llm, api_key: nil)
      Registry.resolve("Lakers score")
      Registry.resolve("explain that")
      routing = Registry.last_routing()
      # should still reflect the sports routing, not the explain routing
      assert routing.agent == "sports"
    end
  end
end
