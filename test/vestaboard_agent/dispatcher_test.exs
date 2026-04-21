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

  describe "dispatch/2 with a grid" do
    test "sends the grid directly to the client" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-1"})
      end)

      assert {:ok, %{"id" => "msg-1"}} = Dispatcher.dispatch(@grid)
    end

    test "returns http error on failure" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:error, {:http, 503}} = Dispatcher.dispatch(@grid)
    end
  end

  describe "dispatch/2 with text" do
    test "renders text then sends to the client" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-2"})
      end)

      assert {:ok, _} = Dispatcher.dispatch("Hello World")
    end

    test "passes align option to renderer" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        # first row should start with H=8 when left-aligned
        assert hd(hd(decoded)) == 8
        Req.Test.json(conn, %{"id" => "msg-3"})
      end)

      assert {:ok, _} = Dispatcher.dispatch("Hello", align: :left)
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
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-4"})
      end)

      assert {:ok, _} = Dispatcher.dispatch_tool(StubTool)
    end

    test "returns error when the tool fails" do
      assert {:error, :tool_failed} = Dispatcher.dispatch_tool(FailingTool)
    end
  end
end
