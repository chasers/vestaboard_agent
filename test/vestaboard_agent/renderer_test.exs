defmodule VestaboardAgent.RendererTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Renderer

  @cols 22
  @rows 6
  @blank 0

  describe "render/2 grid shape" do
    test "always returns a 6x22 grid" do
      {:ok, grid} = Renderer.render("hello")
      assert length(grid) == @rows
      assert Enum.all?(grid, fn row -> length(row) == @cols end)
    end

    test "empty string produces a blank grid" do
      {:ok, grid} = Renderer.render("")
      assert Enum.all?(grid, fn row -> Enum.all?(row, &(&1 == @blank)) end)
    end

    test "unused rows are blank" do
      {:ok, grid} = Renderer.render("hi")
      assert Enum.drop(grid, 1) |> Enum.all?(fn row -> Enum.all?(row, &(&1 == @blank)) end)
    end
  end

  describe "render/2 character encoding" do
    test "encodes A-Z correctly" do
      {:ok, [[_ | _] = row | _]} = Renderer.render("ABCDEFGHIJKLMNOPQRSTUVWXYZ", align: :left)
      assert Enum.take(row, 22) == Enum.to_list(1..22)
    end

    test "lowercase is uppercased before encoding" do
      {:ok, grid_lower} = Renderer.render("hello")
      {:ok, grid_upper} = Renderer.render("HELLO")
      assert grid_lower == grid_upper
    end

    test "encodes digits 0-9 as 27-36" do
      {:ok, [row | _]} = Renderer.render("0123456789", align: :left)
      assert Enum.take(row, 10) == Enum.to_list(27..36)
    end

    test "encodes space as 0" do
      {:ok, [row | _]} = Renderer.render("A B", align: :left)
      assert Enum.at(row, 1) == 0
    end

    test "unknown characters render as blank" do
      {:ok, [row | _]} = Renderer.render("€", align: :left)
      assert hd(row) == @blank
    end
  end

  describe "render/2 alignment" do
    test "centers text by default" do
      {:ok, [row | _]} = Renderer.render("HI")
      encoded = [8, 9]
      text_start = div(@cols - 2, 2)
      assert Enum.slice(row, text_start, 2) == encoded
      assert Enum.take(row, text_start) |> Enum.all?(&(&1 == @blank))
    end

    test "left-aligns text with align: :left" do
      {:ok, [row | _]} = Renderer.render("HI", align: :left)
      assert Enum.take(row, 2) == [8, 9]
      assert Enum.drop(row, 2) |> Enum.all?(&(&1 == @blank))
    end
  end

  describe "render/2 word wrapping" do
    test "wraps long text across multiple rows" do
      {:ok, grid} = Renderer.render("the quick brown fox jumps over")
      filled_rows = Enum.count(grid, fn row -> Enum.any?(row, &(&1 != @blank)) end)
      assert filled_rows > 1
    end

    test "respects newlines" do
      {:ok, grid} = Renderer.render("line one\nline two")
      filled_rows = Enum.count(grid, fn row -> Enum.any?(row, &(&1 != @blank)) end)
      assert filled_rows == 2
    end

    test "truncates beyond 6 rows" do
      long = Enum.map_join(1..10, "\n", fn i -> "row #{i}" end)
      {:ok, grid} = Renderer.render(long)
      assert length(grid) == @rows
    end
  end

  describe "encode_char/1" do
    test "encodes known characters" do
      assert Renderer.encode_char("A") == 1
      assert Renderer.encode_char("Z") == 26
      assert Renderer.encode_char("0") == 27
      assert Renderer.encode_char("9") == 36
      assert Renderer.encode_char("!") == 37
      assert Renderer.encode_char(" ") == 0
    end

    test "returns 0 for unknown characters" do
      assert Renderer.encode_char("€") == 0
      assert Renderer.encode_char("😀") == 0
    end
  end
end
