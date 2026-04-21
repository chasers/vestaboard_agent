defmodule VestaboardAgent.Sandbox.LuaTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Sandbox.Lua

  describe "run/2" do
    test "returns a string result" do
      assert {:ok, "hello"} = Lua.run(~s[return "hello"])
    end

    test "coerces a non-string return to string" do
      assert {:ok, "42"} = Lua.run("return 42")
    end

    test "returns error when script has no return value" do
      assert {:error, :no_return_value} = Lua.run("local x = 1")
    end

    test "returns error on Lua syntax error" do
      assert {:error, reason} = Lua.run("this is not valid lua !!!")
      assert is_binary(reason)
    end

    test "returns error on Lua runtime error" do
      assert {:error, reason} = Lua.run("return nil + 1")
      assert is_binary(reason)
    end

    test "injects context.now as a string" do
      assert {:ok, now} = Lua.run("return context.now", %{now: "2026-01-01T00:00:00Z"})
      assert now == "2026-01-01T00:00:00Z"
    end

    test "converts DateTime context.now to ISO-8601" do
      dt = ~U[2026-06-15 14:30:00Z]
      assert {:ok, now} = Lua.run("return context.now", %{now: dt})
      assert now == "2026-06-15T14:30:00Z"
    end

    test "injects context.board_id as a string" do
      assert {:ok, id} = Lua.run("return context.board_id", %{board_id: "board-123"})
      assert id == "board-123"
    end

    test "context defaults to empty strings when not provided" do
      assert {:ok, now} = Lua.run("return context.now")
      assert now == ""

      assert {:ok, id} = Lua.run("return context.board_id")
      assert id == ""
    end

    test "script can use context in logic" do
      script = """
      if context.board_id == "test" then
        return "matched"
      else
        return "no match"
      end
      """

      assert {:ok, "matched"} = Lua.run(script, %{board_id: "test"})
      assert {:ok, "no match"} = Lua.run(script, %{board_id: "other"})
    end
  end
end
