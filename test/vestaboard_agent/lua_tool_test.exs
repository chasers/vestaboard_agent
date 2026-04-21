defmodule VestaboardAgent.LuaToolTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.LuaTool

  test "runs a script and returns a string" do
    assert {:ok, "hello"} = LuaTool.run(~s[return "hello"])
  end

  test "passes context to the script" do
    assert {:ok, "board-42"} =
             LuaTool.run("return context.board_id", %{board_id: "board-42"})
  end

  test "returns error for invalid script" do
    assert {:error, _reason} = LuaTool.run("not valid lua !!!")
  end
end
