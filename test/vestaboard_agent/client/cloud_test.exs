defmodule VestaboardAgent.Client.CloudTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Client.Cloud

  @grid List.duplicate(List.duplicate(0, 22), 6)

  setup do
    original = Application.get_env(:vestaboard_agent, :client, [])

    on_exit(fn -> Application.put_env(:vestaboard_agent, :client, original) end)

    Application.put_env(:vestaboard_agent, :client,
      backend: Cloud,
      token: "test-token",
      plug: {Req.Test, __MODULE__}
    )

    :ok
  end

  describe "read/0" do
    test "returns character grid from currentMessage wrapper" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"currentMessage" => %{"id" => "abc", "text" => @grid}})
      end)

      assert {:ok, @grid} = Cloud.read()
    end

    test "returns bare list body when no wrapper" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, @grid)
      end)

      assert {:ok, @grid} = Cloud.read()
    end

    test "returns raw body when not a list or currentMessage map" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "format"})
      end)

      assert {:ok, %{"unexpected" => "format"}} = Cloud.read()
    end

    test "returns http error on non-200" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 401, "unauthorized")
      end)

      assert {:error, {:http, 401}} = Cloud.read()
    end
  end

  describe "write_characters/1" do
    test "posts character grid and returns response body" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-1", "created" => 1_000_000})
      end)

      assert {:ok, %{"id" => "msg-1"}} = Cloud.write_characters(@grid)
    end

    test "returns http error on non-2xx" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 429, "rate limited")
      end)

      assert {:error, {:http, 429}} = Cloud.write_characters(@grid)
    end
  end

  describe "write_text/1" do
    test "posts text and returns response body" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-2"})
      end)

      assert {:ok, %{"id" => "msg-2"}} = Cloud.write_text("Hello!")
    end

    test "includes forced: true when option is set" do
      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["forced"] == true
        Req.Test.json(conn, %{"id" => "msg-3"})
      end)

      assert {:ok, _} = Cloud.write_text("Hello!", forced: true)
    end

    test "returns http error on non-2xx" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:error, {:http, 503}} = Cloud.write_text("Hello!")
    end
  end

  describe "get_transition/0" do
    test "returns transition settings" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"transition" => "wave", "transitionSpeed" => "gentle"})
      end)

      assert {:ok, %{"transition" => "wave"}} = Cloud.get_transition()
    end

    test "returns http error on non-200" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 404, "not found")
      end)

      assert {:error, {:http, 404}} = Cloud.get_transition()
    end
  end

  describe "set_transition/2" do
    test "sets transition type and speed" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"transition" => "drift", "transitionSpeed" => "fast"})
      end)

      assert {:ok, _} = Cloud.set_transition("drift", "fast")
    end

    test "returns http error on non-2xx" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 503, "unavailable")
      end)

      assert {:error, {:http, 503}} = Cloud.set_transition("wave", "gentle")
    end

    test "rejects invalid transition type at compile/call time" do
      assert_raise FunctionClauseError, fn ->
        Cloud.set_transition("spin", "fast")
      end
    end

    test "rejects invalid speed" do
      assert_raise FunctionClauseError, fn ->
        Cloud.set_transition("wave", "turbo")
      end
    end
  end

  describe "format_text/1" do
    test "returns character grid from VBML API" do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, @grid)
      end)

      assert {:ok, @grid} = Cloud.format_text("Hello!")
    end

    test "returns http error on non-200" do
      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 422, "unprocessable")
      end)

      assert {:error, {:http, 422}} = Cloud.format_text("Hello!")
    end
  end
end
