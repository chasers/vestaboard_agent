defmodule VestaboardAgent.E2E.DirectRenderTest do
  use VestaboardAgent.E2ECase

  alias VestaboardAgent.{Dispatcher, Renderer}

  # These tests call Dispatcher.dispatch/2 directly, bypassing LLM routing and
  # formatting. They verify the Renderer → Dispatcher → Client → decode_grid
  # pipeline deterministically without depending on LLM responses.

  describe "plain text round-trip" do
    test "short message renders and decodes back" do
      {:ok, _} = Dispatcher.dispatch("HELLO WORLD")
      board = Dispatcher.last_board()
      assert board != nil
      assert String.contains?(board.text, "HELLO")
      assert String.contains?(board.text, "WORLD")
    end

    test "multi-line text preserves line breaks through decode" do
      {:ok, _} = Dispatcher.dispatch("LINE ONE\nLINE TWO")
      board = Dispatcher.last_board()
      assert String.contains?(board.text, "LINE ONE")
      assert String.contains?(board.text, "LINE TWO")
    end

    test "each decoded line is at most 22 characters" do
      long = "THIS IS A FAIRLY LONG MESSAGE THAT SHOULD WRAP NICELY ON THE BOARD"
      {:ok, _} = Dispatcher.dispatch(long)
      board = Dispatcher.last_board()

      violations =
        board.text
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.filter(&(String.length(&1) > 22))

      assert violations == [],
             "Lines exceed 22 chars: #{inspect(violations)}\nFull text: #{inspect(board.text)}"
    end

    test "grid is always 6 rows of 22 columns" do
      {:ok, _} = Dispatcher.dispatch("TEST")
      board = Dispatcher.last_board()
      assert length(board.grid) == 6
      assert Enum.all?(board.grid, &(length(&1) == 22))
    end
  end

  describe "border rendering" do
    test "border row is uniform color code" do
      {:ok, _} = Dispatcher.dispatch("BORDER TEST", border: "blue")
      board = Dispatcher.last_board()
      first_row = hd(board.grid)
      color_code = hd(first_row)
      assert color_code in Map.values(Renderer.color_codes()),
             "Expected first row to be a border color, got: #{inspect(first_row)}"
      assert Enum.all?(first_row, &(&1 == color_code)),
             "Expected uniform border row, got: #{inspect(first_row)}"
    end

    test "inner content is still readable with border" do
      {:ok, _} = Dispatcher.dispatch("BORDERED", border: "red")
      board = Dispatcher.last_board()
      assert String.contains?(board.text, "BORDERED"),
             "Expected 'BORDERED' in decoded text, got: #{inspect(board.text)}"
    end

    test "each border color renders without error" do
      Renderer.color_codes()
      |> Map.keys()
      |> Enum.each(fn color ->
        result = Dispatcher.dispatch("#{String.upcase(color)}", border: color)
        assert {:ok, _} = result, "Border color #{color} failed: #{inspect(result)}"
        Process.sleep(200)
      end)
    end
  end

  describe "special character encoding" do
    test "dollar sign renders and decodes" do
      {:ok, _} = Dispatcher.dispatch("PRICE $4.99")
      board = Dispatcher.last_board()
      assert String.contains?(board.text, "$"), "Missing $ in: #{inspect(board.text)}"
    end

    test "slash and period render and decode" do
      {:ok, _} = Dispatcher.dispatch("4.99/LB")
      board = Dispatcher.last_board()
      assert String.contains?(board.text, "/"), "Missing / in: #{inspect(board.text)}"
      assert String.contains?(board.text, "."), "Missing . in: #{inspect(board.text)}"
    end

    test "question mark and exclamation render" do
      {:ok, _} = Dispatcher.dispatch("READY? YES!")
      board = Dispatcher.last_board()
      assert String.contains?(board.text, "?"), "Missing ? in: #{inspect(board.text)}"
      assert String.contains?(board.text, "!"), "Missing ! in: #{inspect(board.text)}"
    end

    test "unknown characters become blanks without crashing" do
      {:ok, _} = Dispatcher.dispatch("PRICE €5 ☃")
      board = Dispatcher.last_board()
      assert is_binary(board.text)
      assert String.contains?(board.text, "PRICE")
    end
  end

  describe "alignment" do
    test "left-aligned text starts at column 0 in first non-blank row" do
      {:ok, _} = Dispatcher.dispatch("HELLO", align: :left)
      board = Dispatcher.last_board()
      content_rows = Enum.reject(board.grid, &Enum.all?(&1, fn c -> c == 0 end))
      first_content_row = hd(content_rows)
      assert hd(first_content_row) != 0,
             "Expected left-aligned row to start non-blank, got: #{inspect(first_content_row)}"
    end
  end
end
