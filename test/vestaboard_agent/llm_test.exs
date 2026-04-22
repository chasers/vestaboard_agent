defmodule VestaboardAgent.LLMTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.LLM

  @stub_script "return 'hello world'"

  setup do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)
    Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")
    :ok
  end

  defp stub_response do
    %{"content" => [%{"type" => "text", "text" => @stub_script}]}
  end

  defp opts_with_stub(fun) do
    [plug: fn conn -> Req.Test.json(conn, fun.()) end]
  end

  test "returns {:ok, script} on success" do
    opts = opts_with_stub(fn -> stub_response() end)
    assert {:ok, @stub_script} = LLM.generate_tool_script("show a greeting", opts)
  end

  test "trims whitespace from the returned script" do
    response = %{"content" => [%{"type" => "text", "text" => "  return 'hi'  \n"}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, "return 'hi'"} = LLM.generate_tool_script("show something", opts)
  end

  test "strips ```lua ... ``` fences from the response" do
    fenced = "```lua\nreturn 'hello'\n```"
    response = %{"content" => [%{"type" => "text", "text" => fenced}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, "return 'hello'"} = LLM.generate_tool_script("task", opts)
  end

  test "strips plain ``` fences from the response" do
    fenced = "```\nreturn 'hello'\n```"
    response = %{"content" => [%{"type" => "text", "text" => fenced}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, "return 'hello'"} = LLM.generate_tool_script("task", opts)
  end

  test "leaves scripts without fences unchanged" do
    plain = "return 'hello world'"
    response = %{"content" => [%{"type" => "text", "text" => plain}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, ^plain} = LLM.generate_tool_script("task", opts)
  end

  test "returns http error on non-200 response" do
    opts = [plug: fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end]
    assert {:error, {:http, 401}} = LLM.generate_tool_script("task", opts)
  end

  test "returns missing_api_key error when no key is configured" do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    original_env = System.get_env("ANTHROPIC_API_KEY")

    on_exit(fn ->
      Application.put_env(:vestaboard_agent, :llm, original)
      if original_env, do: System.put_env("ANTHROPIC_API_KEY", original_env)
    end)

    Application.put_env(:vestaboard_agent, :llm, api_key: nil)
    System.delete_env("ANTHROPIC_API_KEY")

    assert {:error, :missing_api_key} = LLM.generate_tool_script("task")
  end

  test "reads api_key from app config" do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)

    Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")

    opts = opts_with_stub(fn -> stub_response() end)
    assert {:ok, _} = LLM.generate_tool_script("task", opts)
  end

  describe "route_agent/3" do
    @agents_meta [{"greeter", ["hello", "greet"]}, {"clock", ["time", "clock"]}]

    test "returns the agent name from the LLM response" do
      opts = opts_with_stub(fn ->
        %{"content" => [%{"type" => "text", "text" => "greeter"}]}
      end)

      assert {:ok, "greeter"} = LLM.route_agent("say hi", @agents_meta, opts)
    end

    test "downcases and trims the returned name" do
      opts = opts_with_stub(fn ->
        %{"content" => [%{"type" => "text", "text" => "  Greeter  "}]}
      end)

      assert {:ok, "greeter"} = LLM.route_agent("say hi", @agents_meta, opts)
    end

    test "returns dynamic when the LLM says dynamic" do
      opts = opts_with_stub(fn ->
        %{"content" => [%{"type" => "text", "text" => "dynamic"}]}
      end)

      assert {:ok, "dynamic"} = LLM.route_agent("do something odd", @agents_meta, opts)
    end

    test "returns missing_api_key when no key configured" do
      original = Application.get_env(:vestaboard_agent, :llm, [])
      original_env = System.get_env("ANTHROPIC_API_KEY")

      on_exit(fn ->
        Application.put_env(:vestaboard_agent, :llm, original)
        if original_env, do: System.put_env("ANTHROPIC_API_KEY", original_env)
      end)

      Application.put_env(:vestaboard_agent, :llm, api_key: nil)
      System.delete_env("ANTHROPIC_API_KEY")

      assert {:error, :missing_api_key} = LLM.route_agent("test", @agents_meta)
    end

    test "handles agents with no keywords" do
      agents_meta = [{"dynamic", []}, {"greeter", ["hello"]}]
      opts = opts_with_stub(fn ->
        %{"content" => [%{"type" => "text", "text" => "greeter"}]}
      end)

      assert {:ok, "greeter"} = LLM.route_agent("say hello", agents_meta, opts)
    end
  end
end
