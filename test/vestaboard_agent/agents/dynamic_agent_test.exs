defmodule VestaboardAgent.Agents.DynamicAgentTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agents.DynamicAgent
  alias VestaboardAgent.ToolRegistry

  @generated_script "return 'generated output'"
  @llm_response %{"content" => [%{"type" => "text", "text" => @generated_script}]}

  defp llm_stub_opts do
    [plug: fn conn -> Req.Test.json(conn, @llm_response) end]
  end

  setup do
    original_llm = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original_llm) end)
    Application.put_env(:vestaboard_agent, :llm, api_key: "test-anthropic-key")
    :ok
  end

  test "name/0 returns dynamic" do
    assert DynamicAgent.name() == "dynamic"
  end

  test "keywords/0 returns empty list (matched as fallback)" do
    assert DynamicAgent.keywords() == []
  end

  test "implements the Agent behaviour" do
    assert function_exported?(DynamicAgent, :name, 0)
    assert function_exported?(DynamicAgent, :keywords, 0)
    assert function_exported?(DynamicAgent, :handle, 2)
  end

  describe "derive_tool_name/1" do
    test "lowercases and snake_cases first three words" do
      assert DynamicAgent.derive_tool_name("Show Bitcoin Price") == :show_bitcoin_price
    end

    test "strips punctuation" do
      assert DynamicAgent.derive_tool_name("what's the time?") == :whats_the_time
    end

    test "takes at most three words" do
      assert DynamicAgent.derive_tool_name("one two three four five") == :one_two_three
    end

    test "handles single word prompts" do
      assert DynamicAgent.derive_tool_name("hello") == :hello
    end
  end

  describe "handle/2 with existing tool" do
    test "returns {:ok, text} without calling the LLM when tool already registered" do
      name = :"existing_tool_#{System.unique_integer([:positive])}"
      ToolRegistry.register_script(name, "return 'cached result'")
      on_exit(fn -> ToolRegistry.unregister(name) end)

      prompt = Atom.to_string(name) |> String.replace("_", " ")
      assert {:ok, "cached result"} = DynamicAgent.handle(prompt, %{})
    end
  end

  describe "handle/2 with LLM generation" do
    test "generates a script and returns {:ok, text}" do
      unique_prompt = "unique task #{System.unique_integer([:positive])}"
      result = DynamicAgent.handle(unique_prompt, %{llm_opts: llm_stub_opts()})
      assert {:ok, "generated output"} = result
    end

    test "registers the generated script in ToolRegistry" do
      unique_prompt = "register test #{System.unique_integer([:positive])}"
      tool_name = DynamicAgent.derive_tool_name(unique_prompt)
      on_exit(fn -> ToolRegistry.unregister(tool_name) end)

      DynamicAgent.handle(unique_prompt, %{llm_opts: llm_stub_opts()})

      assert {:ok, {:script, @generated_script}} = ToolRegistry.get(tool_name)
    end

    test "returns error when LLM call fails" do
      failing_opts = [plug: fn conn -> Plug.Conn.send_resp(conn, 500, "error") end]
      unique_prompt = "failing llm #{System.unique_integer([:positive])}"

      assert {:error, _} = DynamicAgent.handle(unique_prompt, %{llm_opts: failing_opts})
    end
  end

  describe "retry loop" do
    test "retries when first script returns empty and second succeeds" do
      counter = :counters.new(1, [])

      plug = fn conn ->
        n = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        script = if n == 0, do: "return ''", else: "return 'retry succeeded'"
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => script}]})
      end

      unique_prompt = "retry test #{System.unique_integer([:positive])}"
      tool_name = DynamicAgent.derive_tool_name(unique_prompt)
      on_exit(fn -> ToolRegistry.unregister(tool_name) end)

      assert {:ok, "retry succeeded"} = DynamicAgent.handle(unique_prompt, %{llm_opts: [plug: plug]})
      assert :counters.get(counter, 1) == 2
    end

    test "returns last result after all attempts exhausted" do
      plug = fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "return ''"}]})
      end

      unique_prompt = "exhaust test #{System.unique_integer([:positive])}"
      tool_name = DynamicAgent.derive_tool_name(unique_prompt)
      on_exit(fn -> ToolRegistry.unregister(tool_name) end)

      assert {:ok, ""} = DynamicAgent.handle(unique_prompt, %{llm_opts: [plug: plug]})
    end
  end
end
