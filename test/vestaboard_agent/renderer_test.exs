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
      blank_rows = Enum.filter(grid, fn row -> Enum.all?(row, &(&1 == @blank)) end)
      assert length(blank_rows) == @rows - 1
    end

    test "single line of text is vertically centered" do
      {:ok, grid} = Renderer.render("hi")
      filled_index = Enum.find_index(grid, fn row -> Enum.any?(row, &(&1 != @blank)) end)
      assert filled_index == div(@rows - 1, 2)
    end
  end

  describe "render/2 character encoding" do
    defp content_row(grid) do
      Enum.find(grid, fn row -> Enum.any?(row, &(&1 != 0)) end)
    end

    test "encodes A-Z correctly" do
      {:ok, grid} = Renderer.render("ABCDEFGHIJKLMNOPQRSTUVWXYZ", align: :left)
      assert Enum.take(content_row(grid), 22) == Enum.to_list(1..22)
    end

    test "lowercase is uppercased before encoding" do
      {:ok, grid_lower} = Renderer.render("hello")
      {:ok, grid_upper} = Renderer.render("HELLO")
      assert grid_lower == grid_upper
    end

    test "encodes digits 1-9 as 27-35, 0 as 36" do
      {:ok, grid} = Renderer.render("1234567890", align: :left)
      assert Enum.take(content_row(grid), 10) == Enum.to_list(27..36)
    end

    test "encodes space as 0" do
      {:ok, grid} = Renderer.render("A B", align: :left)
      assert Enum.at(content_row(grid), 1) == 0
    end

    test "unknown characters render as blank" do
      {:ok, grid} = Renderer.render("€", align: :left)
      assert Enum.all?(grid, fn row -> Enum.all?(row, &(&1 == @blank)) end)
    end
  end

  describe "render/2 alignment" do
    test "centers text by default" do
      {:ok, grid} = Renderer.render("HI")
      row = content_row(grid)
      encoded = [8, 9]
      text_start = div(@cols - 2, 2)
      assert Enum.slice(row, text_start, 2) == encoded
      assert Enum.take(row, text_start) |> Enum.all?(&(&1 == @blank))
    end

    test "left-aligns text with align: :left" do
      {:ok, grid} = Renderer.render("HI", align: :left)
      row = content_row(grid)
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

  describe "render/2 with border" do
    test "returns a 6x22 grid" do
      {:ok, grid} = Renderer.render("hi", border: "blue")
      assert length(grid) == @rows
      assert Enum.all?(grid, fn row -> length(row) == @cols end)
    end

    test "first and last rows are all border color" do
      color = 67
      {:ok, [top | rest]} = Renderer.render("hi", border: "blue")
      bottom = List.last(rest)
      assert Enum.all?(top, &(&1 == color))
      assert Enum.all?(bottom, &(&1 == color))
    end

    test "content rows have border color in first and last cell" do
      color = 67
      {:ok, [_top | rest]} = Renderer.render("hi", border: "blue")
      content_rows = Enum.drop(rest, -1)

      assert Enum.all?(content_rows, fn row ->
               hd(row) == color and List.last(row) == color
             end)
    end

    test "accepts raw integer color codes" do
      {:ok, grid} = Renderer.render("hi", border: 65)
      assert hd(hd(grid)) == 65
    end

    test "color_codes/0 returns all color mappings" do
      codes = Renderer.color_codes()
      assert codes["red"] == 63
      assert codes["orange"] == 64
      assert codes["yellow"] == 65
      assert codes["green"] == 66
      assert codes["blue"] == 67
      assert codes["violet"] == 68
      assert codes["white"] == 69
      assert codes["black"] == 70
      assert map_size(codes) == 8
    end
  end

  # Exhaustive per https://docs.vestaboard.com/docs/charactercodes/
  describe "encode_char/1 — official character codes" do
    test "blank / space = 0" do
      assert Renderer.encode_char(" ") == 0
    end

    test "A–Z = 1–26" do
      for {letter, code} <- Enum.zip(?A..?Z, 1..26) do
        assert Renderer.encode_char(<<letter>>) == code,
               "expected #{<<letter>>} = #{code}"
      end
    end

    test "1–9 = 27–35, 0 = 36" do
      for {digit, code} <- Enum.zip(?1..?9, 27..35) do
        assert Renderer.encode_char(<<digit>>) == code,
               "expected #{<<digit>>} = #{code}"
      end

      assert Renderer.encode_char("0") == 36
    end

    test "! = 37" do
      assert Renderer.encode_char("!") == 37
    end

    test "@ = 38" do
      assert Renderer.encode_char("@") == 38
    end

    test "# = 39" do
      assert Renderer.encode_char("#") == 39
    end

    test "$ = 40" do
      assert Renderer.encode_char("$") == 40
    end

    test "( = 41" do
      assert Renderer.encode_char("(") == 41
    end

    test ") = 42" do
      assert Renderer.encode_char(")") == 42
    end

    test "- = 44" do
      assert Renderer.encode_char("-") == 44
    end

    test "+ = 46" do
      assert Renderer.encode_char("+") == 46
    end

    test "& = 47" do
      assert Renderer.encode_char("&") == 47
    end

    test "= = 48" do
      assert Renderer.encode_char("=") == 48
    end

    test "; = 49" do
      assert Renderer.encode_char(";") == 49
    end

    test ": = 50" do
      assert Renderer.encode_char(":") == 50
    end

    test "' = 52" do
      assert Renderer.encode_char("'") == 52
    end

    test ~s(" = 53) do
      assert Renderer.encode_char("\"") == 53
    end

    test "% = 54" do
      assert Renderer.encode_char("%") == 54
    end

    test ", = 55" do
      assert Renderer.encode_char(",") == 55
    end

    test ". = 56" do
      assert Renderer.encode_char(".") == 56
    end

    test "/ = 59" do
      assert Renderer.encode_char("/") == 59
    end

    test "? = 60" do
      assert Renderer.encode_char("?") == 60
    end

    test "° = 62" do
      assert Renderer.encode_char("°") == 62
    end

    test "■ (filled) = 71" do
      assert Renderer.encode_char("■") == 71
    end

    test "returns 0 for unknown characters" do
      assert Renderer.encode_char("€") == 0
      assert Renderer.encode_char("😀") == 0
    end

    test "° and ■ do not collide with color tile codes (63–70)" do
      # ° must be 62, not 63 (Red); ■ must be 71 (Filled), not 68 (Violet)
      refute Renderer.encode_char("°") in 63..70
      refute Renderer.encode_char("■") in 63..70
    end
  end

  describe "decode_grid/1" do
    test "round-trips a simple text message" do
      {:ok, grid} = Renderer.render("HELLO")
      assert Renderer.decode_grid(grid) == "HELLO"
    end

    test "round-trips multi-line text" do
      {:ok, grid} = Renderer.render("HELLO\nWORLD")
      decoded = Renderer.decode_grid(grid)
      assert decoded == "HELLO\nWORLD"
    end

    test "strips the border and decodes inner content" do
      {:ok, grid} = Renderer.render("HOT TODAY", border: "red")
      decoded = Renderer.decode_grid(grid)
      assert decoded == "HOT TODAY"
    end

    test "returns empty string for a blank grid" do
      blank_grid = List.duplicate(List.duplicate(0, 22), 6)
      assert Renderer.decode_grid(blank_grid) == ""
    end

    test "decodes numbers" do
      {:ok, grid} = Renderer.render("42")
      assert Renderer.decode_grid(grid) == "42"
    end

    test "round-trips special characters" do
      {:ok, grid} = Renderer.render("12:34", align: :left)
      assert String.contains?(Renderer.decode_grid(grid), "12:34")
    end
  end
end
