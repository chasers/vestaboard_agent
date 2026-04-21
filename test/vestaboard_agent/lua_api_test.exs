defmodule VestaboardAgent.LuaAPITest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Sandbox.Lua

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
end
