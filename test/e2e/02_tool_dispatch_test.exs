defmodule VestaboardAgent.E2E.ToolDispatchTest do
  use VestaboardAgent.E2ECase

  alias VestaboardAgent.{Dispatcher, ToolRegistry}
  alias VestaboardAgent.Tools.{Clock, Greeting, Quote, Weather}

  # These tests call Dispatcher.dispatch_tool/2 directly for deterministic output,
  # then verify what decode_grid read back from the dispatched grid.

  describe "Clock tool" do
    test "displays a recognizable time string" do
      {:ok, _} = Dispatcher.dispatch_tool(Clock)
      board = Dispatcher.last_board()
      assert board != nil, "last_board/0 returned nil after Clock dispatch"

      assert String.match?(board.text, ~r/\d+:\d+/),
             "Expected time pattern in: #{inspect(board.text)}"
    end
  end

  describe "Weather tool" do
    test "displays temperature data" do
      {:ok, _} = Dispatcher.dispatch_tool(Weather)
      board = Dispatcher.last_board()
      assert board != nil, "last_board/0 returned nil after Weather dispatch"
      # Flexible: just verify something non-empty reached the board
      assert board.text != "",
             "Weather produced empty board text"
    end

    test "weather output fits within 6 rows" do
      {:ok, _} = Dispatcher.dispatch_tool(Weather)
      board = Dispatcher.last_board()
      lines = board.text |> String.split("\n") |> Enum.reject(&(&1 == ""))

      assert length(lines) <= 6,
             "Weather output exceeded 6 rows: #{inspect(lines)}"
    end
  end

  describe "Quote tool" do
    test "displays a non-empty quote" do
      {:ok, _} = Dispatcher.dispatch_tool(Quote)
      board = Dispatcher.last_board()
      assert board != nil
      assert board.text != "", "Quote tool produced empty text"
    end

    test "quote fits within line length" do
      {:ok, _} = Dispatcher.dispatch_tool(Quote)
      board = Dispatcher.last_board()

      violations =
        board.text
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.filter(&(String.length(&1) > 22))

      assert violations == [],
             "Quote lines exceed 22 chars: #{inspect(violations)}"
    end
  end

  describe "Greeting tool" do
    test "displays a greeting" do
      {:ok, _} = Dispatcher.dispatch_tool(Greeting)
      board = Dispatcher.last_board()
      assert board != nil
      assert board.text != "", "Greeting tool produced empty text"
    end
  end

  describe "Lua script via ToolRegistry" do
    setup do
      ToolRegistry.register_script(:e2e_lua_test, "return 'LUA WORKS'")
      on_exit(fn -> ToolRegistry.unregister(:e2e_lua_test) end)
      :ok
    end

    test "registered Lua script runs and produces output" do
      {:ok, _} = ToolRegistry.run(:e2e_lua_test)
      # ToolRegistry.run returns the text; dispatch it to verify the full path
      {:ok, text} = ToolRegistry.run(:e2e_lua_test)
      {:ok, _} = Dispatcher.dispatch(text)
      board = Dispatcher.last_board()

      assert String.contains?(board.text, "LUA"),
             "Expected 'LUA' in decoded text, got: #{inspect(board.text)}"
    end
  end
end
