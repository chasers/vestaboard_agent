defmodule VestaboardAgent.Agents.DynamicAgentTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agents.DynamicAgent
  alias VestaboardAgent.ToolRegistry

  @generated_script "return 'generated output'"
  @llm_response %{"content" => [%{"type" => "text", "text" => @generated_script}]}

  defp llm_stub_opts do
    [plug: fn conn -> Req.Test.json(conn, @llm_response) end]
  end

  defp dispatcher_stub(fun) do
    Req.Test.stub(VestaboardAgent.DispatcherTest, fun)
    Req.Test.allow(
      VestaboardAgent.DispatcherTest,
      self(),
      Process.whereis(VestaboardAgent.Dispatcher)
    )
  end

  setup do
    original_client = Application.get_env(:vestaboard_agent, :client, [])
    original_llm = Application.get_env(:vestaboard_agent, :llm, [])

    on_exit(fn ->
      Application.put_env(:vestaboard_agent, :client, original_client)
      Application.put_env(:vestaboard_agent, :llm, original_llm)
    end)

    Application.put_env(:vestaboard_agent, :client,
      backend: VestaboardAgent.Client.Local,
      api_key: "test-key",
      base_url: "http://vestaboard.local:7000",
      plug: {Req.Test, VestaboardAgent.DispatcherTest}
    )

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
    test "dispatches without calling the LLM when tool already registered" do
      name = :"existing_tool_#{System.unique_integer([:positive])}"
      ToolRegistry.register_script(name, "return 'cached result'")
      on_exit(fn -> ToolRegistry.unregister(name) end)

      dispatcher_stub(fn conn -> Req.Test.json(conn, %{"id" => "msg-1"}) end)

      prompt = Atom.to_string(name) |> String.replace("_", " ")
      assert {:ok, :done} = DynamicAgent.handle(prompt, %{})
    end
  end

  describe "handle/2 with LLM generation" do
    test "generates a script and dispatches when tool is unknown" do
      dispatcher_stub(fn conn -> Req.Test.json(conn, %{"id" => "msg-2"}) end)

      unique_prompt = "unique task #{System.unique_integer([:positive])}"
      result = DynamicAgent.handle(unique_prompt, %{llm_opts: llm_stub_opts()})

      assert {:ok, :done} = result
    end

    test "registers the generated script in ToolRegistry" do
      dispatcher_stub(fn conn -> Req.Test.json(conn, %{"id" => "msg-3"}) end)

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
end
