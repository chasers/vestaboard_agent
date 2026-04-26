defmodule VestaboardAgent.Clients.AnthropicTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Clients.Anthropic

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
    assert {:ok, @stub_script} = Anthropic.generate_tool_script("show a greeting", opts)
  end

  test "trims whitespace from the returned script" do
    response = %{"content" => [%{"type" => "text", "text" => "  return 'hi'  \n"}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, "return 'hi'"} = Anthropic.generate_tool_script("show something", opts)
  end

  test "strips ```lua ... ``` fences from the response" do
    fenced = "```lua\nreturn 'hello'\n```"
    response = %{"content" => [%{"type" => "text", "text" => fenced}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, "return 'hello'"} = Anthropic.generate_tool_script("task", opts)
  end

  test "strips plain ``` fences from the response" do
    fenced = "```\nreturn 'hello'\n```"
    response = %{"content" => [%{"type" => "text", "text" => fenced}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, "return 'hello'"} = Anthropic.generate_tool_script("task", opts)
  end

  test "leaves scripts without fences unchanged" do
    plain = "return 'hello world'"
    response = %{"content" => [%{"type" => "text", "text" => plain}]}
    opts = opts_with_stub(fn -> response end)
    assert {:ok, ^plain} = Anthropic.generate_tool_script("task", opts)
  end

  test "returns http error on non-200 response" do
    opts = [plug: fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end]
    assert {:error, {:http, 401}} = Anthropic.generate_tool_script("task", opts)
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

    assert {:error, :missing_api_key} = Anthropic.generate_tool_script("task")
  end

  test "reads api_key from app config" do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)

    Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")

    opts = opts_with_stub(fn -> stub_response() end)
    assert {:ok, _} = Anthropic.generate_tool_script("task", opts)
  end

  describe "route_agent/3" do
    @agents_meta [
      {"greeter", "Show a greeting", ["hello", "greet"]},
      {"clock", "Show the current time", ["time", "clock"]}
    ]

    test "returns the agent name and confidence from the LLM response" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "greeter:0.9"}]}
        end)

      assert {:ok, "greeter", 0.9} = Anthropic.route_agent("say hi", @agents_meta, opts)
    end

    test "downcases and trims the returned name" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "  Greeter:0.8  "}]}
        end)

      assert {:ok, "greeter", 0.8} = Anthropic.route_agent("say hi", @agents_meta, opts)
    end

    test "defaults confidence to 1.0 when not present in response" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "greeter"}]}
        end)

      assert {:ok, "greeter", 1.0} = Anthropic.route_agent("say hi", @agents_meta, opts)
    end

    test "returns dynamic when the LLM says dynamic" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "dynamic:0.7"}]}
        end)

      assert {:ok, "dynamic", 0.7} = Anthropic.route_agent("do something odd", @agents_meta, opts)
    end

    test "clamps confidence to 0.0–1.0 range" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "greeter:1.5"}]}
        end)

      assert {:ok, "greeter", 1.0} = Anthropic.route_agent("say hi", @agents_meta, opts)
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

      assert {:error, :missing_api_key} = Anthropic.route_agent("test", @agents_meta)
    end

    test "handles agents with no keywords" do
      agents_meta = [{"dynamic", "Fetch live data or run custom tools", []}, {"greeter", "Show a greeting", ["hello"]}]

      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "greeter:0.85"}]}
        end)

      assert {:ok, "greeter", 0.85} = Anthropic.route_agent("say hello", agents_meta, opts)
    end

    test "includes history in routing prompt when provided" do
      parent = self()
      agents_meta = [{"clock", "Show the current time", ["time"]}, {"weather", "Show current weather", ["weather"]}]

      opts = [
        history: [%{prompt: "show the clock", text: "12:34 PM", render_opts: []}],
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          prompt_text = get_in(decoded, ["messages", Access.at(0), "content"])
          send(parent, {:prompt, prompt_text})
          Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "clock:0.9"}]})
        end
      ]

      assert {:ok, "clock", _} = Anthropic.route_agent("do that again", agents_meta, opts)

      assert_receive {:prompt, prompt_text}
      assert String.contains?(prompt_text, "show the clock")
    end
  end

  describe "parse_schedule/3" do
    @tool_names ["clock", "weather", "quote"]

    test "parses a valid schedule response" do
      opts =
        opts_with_stub(fn ->
          %{
            "content" => [
              %{"type" => "text", "text" => ~s({"tool":"clock","interval_seconds":15})}
            ]
          }
        end)

      assert {:ok, %{tool: "clock", interval_seconds: 15}} =
               Anthropic.parse_schedule("show clock every 15 seconds", @tool_names, opts)
    end

    test "parses minute-level interval" do
      opts =
        opts_with_stub(fn ->
          %{
            "content" => [
              %{"type" => "text", "text" => ~s({"tool":"weather","interval_seconds":300})}
            ]
          }
        end)

      assert {:ok, %{tool: "weather", interval_seconds: 300}} =
               Anthropic.parse_schedule("show weather every 5 minutes", @tool_names, opts)
    end

    test "returns error for invalid JSON response" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => "not json"}]}
        end)

      assert {:error, _} = Anthropic.parse_schedule("schedule something", @tool_names, opts)
    end

    test "returns error when interval_seconds is missing" do
      opts =
        opts_with_stub(fn ->
          %{"content" => [%{"type" => "text", "text" => ~s({"tool":"clock"})}]}
        end)

      assert {:error, :invalid_schedule_response} =
               Anthropic.parse_schedule("schedule clock", @tool_names, opts)
    end

    test "returns error when interval_seconds is zero or negative" do
      opts =
        opts_with_stub(fn ->
          %{
            "content" => [
              %{"type" => "text", "text" => ~s({"tool":"clock","interval_seconds":0})}
            ]
          }
        end)

      assert {:error, :invalid_schedule_response} =
               Anthropic.parse_schedule("schedule clock", @tool_names, opts)
    end
  end
end
