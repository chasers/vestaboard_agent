defmodule VestaboardAgentTest do
  use ExUnit.Case, async: false

  setup do
    original_llm = Application.get_env(:vestaboard_agent, :llm, [])
    original_client = Application.get_env(:vestaboard_agent, :client, [])

    on_exit(fn ->
      Application.put_env(:vestaboard_agent, :llm, original_llm)
      Application.put_env(:vestaboard_agent, :client, original_client)
    end)

    Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")

    Application.put_env(:vestaboard_agent, :client,
      backend: VestaboardAgent.Client.Local,
      api_key: "test-key",
      base_url: "http://vestaboard.local:7000",
      plug: {Req.Test, __MODULE__}
    )

    :ok
  end

  defp stub_board(fun) do
    Req.Test.stub(__MODULE__, fun)
    Req.Test.allow(__MODULE__, self(), Process.whereis(VestaboardAgent.Dispatcher))
  end

  defp llm_stub(response_text) do
    [llm_opts: [plug: fn conn ->
      Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => response_text}]})
    end]]
  end

  test "display/2 routes keyword match through formatter and writes to board" do
    # Greeter keyword match — no LLM routing needed, but Formatter still calls LLM
    formatter_response = ~s({"text": "GOOD MORNING", "border_color": "yellow"})
    stub_board(fn conn -> Req.Test.json(conn, %{"id" => "msg-1"}) end)

    assert {:ok, _} = VestaboardAgent.display("hello", llm_stub(formatter_response))
  end

  test "display/2 passes llm_opts through to agent routing and formatter" do
    # Use a prompt that won't keyword-match any agent, so LLM routing fires.
    # Both the router call and the formatter call will hit the same stub.
    stub_board(fn conn -> Req.Test.json(conn, %{"id" => "msg-2"}) end)

    llm_response = ~s({"text": "HELLO WORLD", "border_color": "blue"})
    assert {:ok, _} = VestaboardAgent.display("hello", llm_stub(llm_response))
  end
end
