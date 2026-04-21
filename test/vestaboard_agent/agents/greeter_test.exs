defmodule VestaboardAgent.Agents.GreeterTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agents.Greeter

  setup do
    original = Application.get_env(:vestaboard_agent, :client, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :client, original) end)

    Application.put_env(:vestaboard_agent, :client,
      backend: VestaboardAgent.Client.Local,
      api_key: "test-key",
      base_url: "http://vestaboard.local:7000",
      plug: {Req.Test, __MODULE__}
    )

    :ok
  end

  defp stub_req(fun) do
    Req.Test.stub(__MODULE__, fun)
    Req.Test.allow(__MODULE__, self(), Process.whereis(VestaboardAgent.Dispatcher))
  end

  test "name/0 returns a string" do
    assert is_binary(Greeter.name())
  end

  test "keywords/0 returns a non-empty list" do
    assert Greeter.keywords() != []
  end

  test "implements the Agent behaviour" do
    assert function_exported?(Greeter, :name, 0)
    assert function_exported?(Greeter, :keywords, 0)
    assert function_exported?(Greeter, :handle, 2)
  end

  test "handle/2 dispatches to the board and returns :done" do
    stub_req(fn conn -> Req.Test.json(conn, %{"id" => "msg-1"}) end)
    assert {:ok, :done} = Greeter.handle("say hello", %{})
  end

  test "handle/2 injects current time when context has no :now" do
    stub_req(fn conn -> Req.Test.json(conn, %{"id" => "msg-2"}) end)
    assert {:ok, :done} = Greeter.handle("greet me", %{})
  end

  test "handle/2 returns error when dispatch fails" do
    stub_req(fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
    assert {:error, _} = Greeter.handle("hello", %{})
  end
end
