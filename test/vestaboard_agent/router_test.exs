defmodule VestaboardAgent.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias VestaboardAgent.{Dispatcher, Router}

  @opts Router.init([])

  setup do
    original = Application.get_env(:vestaboard_agent, :client, [])

    on_exit(fn -> Application.put_env(:vestaboard_agent, :client, original) end)

    Application.put_env(:vestaboard_agent, :client,
      backend: VestaboardAgent.Clients.Vestaboard.Local,
      api_key: "test-key",
      base_url: "http://vestaboard.local:7000",
      plug: {Req.Test, __MODULE__}
    )

    :ok
  end

  defp stub_req(fun) do
    Req.Test.stub(__MODULE__, fun)
    Req.Test.allow(__MODULE__, self(), Process.whereis(Dispatcher))
  end

  defp post_chat(prompt) do
    conn(:post, "/chat", Jason.encode!(%{prompt: prompt}))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  defp get_board do
    conn(:get, "/board")
    |> Router.call(@opts)
  end

  describe "POST /chat" do
    test "returns 400 when prompt is missing" do
      conn =
        conn(:post, "/chat", Jason.encode!(%{foo: "bar"}))
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      assert conn.status == 400
      assert %{"ok" => false} = Jason.decode!(conn.resp_body)
    end

    test "returns 200 and ok:true on a successful dispatch" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "r-1"}) end)

      conn = post_chat("hello world")

      assert conn.status == 200
      assert %{"ok" => true} = Jason.decode!(conn.resp_body)
    end
  end

  describe "GET /board" do
    test "returns 404 when no board has been dispatched" do
      # Restart dispatcher in a fresh state so last_board is nil
      pid = Process.whereis(Dispatcher)
      :sys.replace_state(pid, fn _ -> %{last_board: nil} end)

      conn = get_board()
      assert conn.status == 404
    end

    test "returns 200 with grid and decoded text after a dispatch" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "r-2"}) end)
      Req.Test.allow(__MODULE__, self(), Process.whereis(Dispatcher))
      Dispatcher.dispatch("HELLO WORLD")

      conn = get_board()
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
      assert is_list(body["grid"])
      assert String.contains?(body["text"], "HELLO WORLD")
    end
  end

  describe "unknown routes" do
    test "returns 404" do
      conn = conn(:get, "/unknown") |> Router.call(@opts)
      assert conn.status == 404
    end
  end
end
