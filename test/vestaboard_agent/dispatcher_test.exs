defmodule VestaboardAgent.DispatcherTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Dispatcher

  @grid List.duplicate(List.duplicate(0, 22), 6)

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

  # Req.Test stubs are process-local. Because Dispatcher is a GenServer, the
  # HTTP call runs in its process, not the test process. Call allow/3 after
  # every stub so the Dispatcher can see the current test's stub.
  defp stub_req(fun) do
    Req.Test.stub(__MODULE__, fun)
    Req.Test.allow(__MODULE__, self(), Process.whereis(Dispatcher))
  end

  describe "dispatch/2 with a grid" do
    test "sends the grid directly to the client" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "msg-1"}) end)
      assert {:ok, %{"id" => "msg-1"}} = Dispatcher.dispatch(@grid)
    end

    test "returns http error on failure" do
      stub_req(fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
      assert {:error, {:http, 503}} = Dispatcher.dispatch(@grid)
    end
  end

  describe "dispatch/2 with text" do
    test "renders text then sends to the client" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "msg-2"}) end)
      assert {:ok, _} = Dispatcher.dispatch("Hello World")
    end

    test "passes align option to renderer" do
      stub_req(fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        content_row = Enum.find(decoded, fn row -> Enum.any?(row, &(&1 != 0)) end)
        # content row should start with H=8 when left-aligned
        assert hd(content_row) == 8
        Req.Test.json(conn, %{"id" => "msg-3"})
      end)

      assert {:ok, _} = Dispatcher.dispatch("Hello", align: :left)
    end
  end

  describe "last_board/0" do
    test "returns nil before any dispatch" do
      :sys.replace_state(Dispatcher, fn _ -> %{last_board: nil} end)
      assert Dispatcher.last_board() == nil
    end

    test "returns grid and decoded text after a successful dispatch" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "lb-1"}) end)
      Dispatcher.dispatch("HELLO")

      board = Dispatcher.last_board()
      assert %{grid: grid, text: text} = board
      assert is_list(grid) and length(grid) == 6
      assert String.contains?(text, "HELLO")
    end

    test "is updated by dispatch_tool as well" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "lb-2"}) end)
      # Use the fully-qualified name since StubTool is defined later in this file
      Dispatcher.dispatch_tool(VestaboardAgent.DispatcherTest.StubTool)

      assert %{text: text} = Dispatcher.last_board()
      assert String.contains?(text, "STUB OUTPUT")
    end
  end

  describe "dispatch_tool/2" do
    defmodule StubTool do
      @behaviour VestaboardAgent.Tool
      @impl true
      def name, do: "stub"
      @impl true
      def run(_context), do: {:ok, "stub output"}
    end

    defmodule FailingTool do
      @behaviour VestaboardAgent.Tool
      @impl true
      def name, do: "failing"
      @impl true
      def run(_context), do: {:error, :tool_failed}
    end

    test "runs a tool then dispatches the result" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "msg-4"}) end)
      assert {:ok, _} = Dispatcher.dispatch_tool(StubTool)
    end

    test "returns error when the tool fails" do
      assert {:error, :tool_failed} = Dispatcher.dispatch_tool(FailingTool)
    end
  end

  describe "dispatch_async/2" do
    test "returns :ok immediately without waiting for the write" do
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "async-1"}) end)
      assert :ok = Dispatcher.dispatch_async("hello")
      # issue a sync call to flush the cast through the GenServer before the test exits
      stub_req(fn conn -> Req.Test.json(conn, %{"id" => "flush"}) end)
      Dispatcher.dispatch("", [])
    end

    test "drops the message when TTL has already expired" do
      parent = self()
      stub_req(fn conn ->
        send(parent, :http_called)
        Req.Test.json(conn, %{"id" => "should-not-happen"})
      end)

      Dispatcher.dispatch_async("stale message", ttl: -1)
      # sync flush so the cast is processed before we assert
      stub_req(fn conn -> Req.Test.json(conn, %{}) end)
      Dispatcher.dispatch("", [])

      refute_received :http_called
    end
  end
end
