defmodule VestaboardAgent.E2E.EdgeCasesTest do
  use VestaboardAgent.E2ECase

  alias VestaboardAgent.Dispatcher

  describe "prompt edge cases" do
    test "very long prompt wraps without crashing" do
      long = String.duplicate("ABCDEFGHIJ ", 20) |> String.trim()
      result = e2e_display(long)

      assert result.display_result != nil
      board = Dispatcher.last_board()

      if board do
        violations =
          board.text
          |> String.split("\n")
          |> Enum.reject(&(&1 == ""))
          |> Enum.filter(&(String.length(&1) > 22))

        assert violations == [],
               "Lines exceed 22 chars after long prompt: #{inspect(violations)}"
      end
    end

    test "unicode characters don't crash the pipeline" do
      result = e2e_display("show 日本語 text ñoño 🎉")
      assert result.display_result != nil
      refute match?({:error, %RuntimeError{}}, result.display_result)
    end

    test "prompt with only special chars dispatches without crashing" do
      # Bypass LLM routing — test Renderer handles special chars directly
      assert {:ok, _} = Dispatcher.dispatch("!!! ??? $$$")
      board = Dispatcher.last_board()
      assert board != nil
      assert String.contains?(board.text, "!")
      assert String.contains?(board.text, "?")
      assert String.contains?(board.text, "$")
    end

    test "repeated identical prompts each update the board" do
      result1 = e2e_display("hello")
      Process.sleep(300)
      result2 = e2e_display("hello")

      assert result1.display_result != nil
      assert result2.display_result != nil
    end
  end

  describe "concurrent display calls" do
    test "two concurrent display/1 calls complete without crashing" do
      # Use keyword-matching prompts so LLM routing is not required
      tasks =
        Task.async_stream(
          ["hello concurrent A", "hello concurrent B"],
          fn prompt -> VestaboardAgent.display(prompt) end,
          timeout: 30_000,
          max_concurrency: 2
        )
        |> Enum.to_list()

      Enum.each(tasks, fn {:ok, result} ->
        assert result != nil, "Concurrent display returned nil"

        refute match?({:error, _}, result),
               "Concurrent display errored: #{inspect(result)}"
      end)

      board = Dispatcher.last_board()
      assert board != nil, "Board was not updated after concurrent dispatches"
    end
  end

  describe "LLM formatter fallback" do
    setup do
      original_cfg = Application.get_env(:vestaboard_agent, :llm, [])
      original_key = System.get_env("ANTHROPIC_API_KEY")

      on_exit(fn ->
        Application.put_env(:vestaboard_agent, :llm, original_cfg)
        if original_key, do: System.put_env("ANTHROPIC_API_KEY", original_key)
      end)

      :ok
    end

    test "board still renders when LLM API key is missing" do
      Application.put_env(:vestaboard_agent, :llm, api_key: nil)
      System.delete_env("ANTHROPIC_API_KEY")

      # Use a keyword-matching prompt so agent routing doesn't need the LLM
      result = e2e_display("hello fallback test")

      assert match?({:ok, _}, result.display_result),
             "Expected {:ok, _} with fallback formatter, got: #{inspect(result.display_result)}"

      board = Dispatcher.last_board()
      assert board != nil
      assert board.text != ""
    end
  end

  describe "direct dispatch edge cases" do
    test "blank grid writes without error" do
      blank = List.duplicate(List.duplicate(0, 22), 6)
      assert {:ok, _} = Dispatcher.dispatch(blank)
      board = Dispatcher.last_board()
      assert board != nil
      assert board.text == ""
    end

    test "empty string dispatches without crashing" do
      assert {:ok, _} = Dispatcher.dispatch("")
    end

    test "exactly 22-character line renders without truncation" do
      line = "ABCDEFGHIJKLMNOPQRSTUV"
      assert String.length(line) == 22
      {:ok, _} = Dispatcher.dispatch(line)
      board = Dispatcher.last_board()

      assert String.contains?(board.text, "ABCDEFGHIJKLMNOPQRSTUV"),
             "22-char line was truncated. Got: #{inspect(board.text)}"
    end

    test "exactly 6 lines render without truncation" do
      text = Enum.join(1..6 |> Enum.map(&"ROW #{&1}"), "\n")
      {:ok, _} = Dispatcher.dispatch(text)
      board = Dispatcher.last_board()

      for i <- 1..6 do
        assert String.contains?(board.text, "ROW #{i}"),
               "ROW #{i} missing from 6-line message. Got: #{inspect(board.text)}"
      end
    end
  end
end
