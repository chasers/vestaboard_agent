defmodule VestaboardAgent.Client.LocalTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Client.Local

  @grid List.duplicate(List.duplicate(0, 22), 6)

  setup do
    original = Application.get_env(:vestaboard_agent, :client, [])

    on_exit(fn -> Application.put_env(:vestaboard_agent, :client, original) end)

    Application.put_env(:vestaboard_agent, :client,
      backend: Local,
      api_key: "local-test-key",
      base_url: "http://vestaboard.local:7000",
      plug: {Req.Test, __MODULE__}
    )

    :ok
  end

  describe "read/0" do
    test "returns character grid" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, @grid)
      end)

      assert {:ok, @grid} = Local.read()
    end

    test "returns non-list body as-is" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"message" => "board state"})
      end)

      assert {:ok, %{"message" => "board state"}} = Local.read()
    end

    test "returns http error on non-200" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 403, "forbidden")
      end)

      assert {:error, {:http, 403}} = Local.read()
    end
  end

  describe "write_characters/1" do
    test "posts character grid and returns response" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"message" => "ok"})
      end)

      assert {:ok, %{"message" => "ok"}} = Local.write_characters(@grid)
    end

    test "returns http error on non-2xx" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:error, {:http, 503}} = Local.write_characters(@grid)
    end
  end

  describe "enable/1" do
    test "returns api key from response with apiKey field" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"message" => "enabled", "apiKey" => "new-key-123"})
      end)

      assert {:ok, "new-key-123"} = Local.enable("enablement-token")
    end

    test "returns api key from response with api_key field" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"api_key" => "new-key-456"})
      end)

      assert {:ok, "new-key-456"} = Local.enable("enablement-token")
    end

    test "returns http error on failure" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 401, "invalid enablement token")
      end)

      assert {:error, {:http, 401}} = Local.enable("bad-token")
    end
  end
end
