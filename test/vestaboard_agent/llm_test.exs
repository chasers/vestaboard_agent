defmodule VestaboardAgent.LLMTest do
  use ExUnit.Case, async: true

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

  test "returns http error on non-200 response" do
    opts = [plug: fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end]
    assert {:error, {:http, 401}} = LLM.generate_tool_script("task", opts)
  end

  test "returns missing_api_key error when no key is configured" do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)

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
end
