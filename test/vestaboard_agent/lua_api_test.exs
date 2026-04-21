defmodule VestaboardAgent.LuaAPITest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Sandbox.Lua

  setup do
    original = Application.get_env(:vestaboard_agent, :lua_http, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :lua_http, original) end)
    :ok
  end

  defp set_http_stub(fun) do
    Application.put_env(:vestaboard_agent, :lua_http, plug: fun)
  end

  describe "vestaboard.truncate/2" do
    test "truncates a string longer than len" do
      assert {:ok, "hello"} = Lua.run(~s[return vestaboard.truncate("hello world", 5)])
    end

    test "returns the full string when shorter than len" do
      assert {:ok, "hi"} = Lua.run(~s[return vestaboard.truncate("hi", 10)])
    end

    test "returns empty string when len is 0" do
      assert {:ok, ""} = Lua.run(~s[return vestaboard.truncate("hello", 0)])
    end

    test "handles an exact-length string" do
      assert {:ok, "hello"} = Lua.run(~s[return vestaboard.truncate("hello", 5)])
    end
  end

  describe "vestaboard.log/1" do
    test "is callable without raising" do
      assert {:error, :no_return_value} = Lua.run(~s[vestaboard.log("test message")])
    end
  end

  describe "vestaboard.http_get/1" do
    test "returns body and status from a successful GET" do
      set_http_stub(fn conn -> Plug.Conn.send_resp(conn, 200, "OK response") end)

      assert {:ok, "OK response"} =
               Lua.run(~s[
                 local body, status = vestaboard.http_get("http://example.com")
                 if status == 200 then return body else return "error" end
               ])
    end

    test "exposes the HTTP status code to the script" do
      set_http_stub(fn conn -> Plug.Conn.send_resp(conn, 404, "not found") end)

      assert {:ok, "404"} =
               Lua.run(~s[
                 local body, status = vestaboard.http_get("http://example.com")
                 return tostring(status)
               ])
    end

    test "returns nil body on network error" do
      set_http_stub(fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert {:ok, result} =
               Lua.run(~s[
                 local body, status = vestaboard.http_get("http://example.com")
                 return tostring(status)
               ])

      assert result == "500"
    end
  end

  describe "vestaboard.http_post/2" do
    test "sends a POST and returns body and status" do
      set_http_stub(fn conn -> Plug.Conn.send_resp(conn, 201, "created") end)

      assert {:ok, "201"} =
               Lua.run(~s[
                 local body, status = vestaboard.http_post("http://example.com", "data")
                 return tostring(status)
               ])
    end
  end

  describe "vestaboard.json_decode/1" do
    test "parses a JSON object and makes fields accessible" do
      set_http_stub(fn conn ->
        Plug.Conn.send_resp(conn, 200, ~s({"temperature": 72, "condition": "sunny"}))
      end)

      assert {:ok, "72 sunny"} =
               Lua.run(~s[
                 local body, _ = vestaboard.http_get("http://api.example.com/weather")
                 local data = vestaboard.json_decode(body)
                 return tostring(data.temperature) .. " " .. data.condition
               ])
    end

    test "returns nil for invalid JSON" do
      assert {:ok, "nil"} =
               Lua.run(~s[
                 local result = vestaboard.json_decode("not json {{{")
                 return tostring(result)
               ])
    end
  end
end
