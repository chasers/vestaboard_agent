defmodule VestaboardAgent.Renderer do
  @moduledoc """
  Converts text into a Vestaboard 6×22 character code grid.

  Character codes confirmed from board output:
    0       = blank
    1–26    = A–Z
    27–36   = 0–9  (27=0, 28=1, … 36=9)
    37      = !
    38      = @
    39      = #
    40      = $
    44      = -
    46      = &
    47      = =
    52      = ?
    53      = /
    54      = .
    55      = ,
    56      = :
    59      = "
    60      = '
    62      = +
    63      = °
    65      = ♥
    68      = filled (■)

  Unknown characters are rendered as blank (0).
  """

  @rows 6
  @cols 22
  @blank 0

  @color_codes %{
    "red" => 63, "orange" => 64, "yellow" => 65,
    "green" => 66, "blue" => 67, "violet" => 68, "white" => 69
  }
  @color_names Map.keys(@color_codes)

  @doc "Map of color name strings to Vestaboard tile codes."
  def color_codes, do: @color_codes

  @char_map %{
    " " => 0,
    "A" => 1,  "B" => 2,  "C" => 3,  "D" => 4,  "E" => 5,
    "F" => 6,  "G" => 7,  "H" => 8,  "I" => 9,  "J" => 10,
    "K" => 11, "L" => 12, "M" => 13, "N" => 14, "O" => 15,
    "P" => 16, "Q" => 17, "R" => 18, "S" => 19, "T" => 20,
    "U" => 21, "V" => 22, "W" => 23, "X" => 24, "Y" => 25,
    "Z" => 26,
    "0" => 27, "1" => 28, "2" => 29, "3" => 30, "4" => 31,
    "5" => 32, "6" => 33, "7" => 34, "8" => 35, "9" => 36,
    "!" => 37, "@" => 38, "#" => 39, "$" => 40,
    "-" => 44, "&" => 46, "=" => 47,
    "?" => 52, "/" => 53, "." => 54, "," => 55, ":" => 56,
    "\"" => 59, "'" => 60, "+" => 62, "°" => 63, "♥" => 65,
    "■" => 68
  }

  @doc """
  Render `text` into a 6×22 Vestaboard character grid.

  Options:
    * `:align` — `:center` (default) or `:left`
    * `:border` — a color name string (`"red"`, `"blue"`, etc.) or a raw integer tile
      code. When set, the outer ring of tiles is filled with that color and content
      is rendered in a 4×20 inner area.

  Returns `{:ok, [[integer()]]}`.
  """
  @spec render(String.t(), keyword()) :: {:ok, [[integer()]]}
  def render(text, opts \\ []) when is_binary(text) do
    align = Keyword.get(opts, :align, :center)

    case Keyword.get(opts, :border) do
      nil ->
        grid =
          text
          |> String.upcase()
          |> word_wrap()
          |> Enum.take(@rows)
          |> Enum.map(&encode_line(&1, align, @cols))
          |> pad_rows(@rows, @cols)

        {:ok, grid}

      border_spec ->
        color = resolve_color(border_spec)
        inner_cols = @cols - 2
        inner_rows = @rows - 2

        border_row = List.duplicate(color, @cols)

        content_rows =
          text
          |> String.upcase()
          |> word_wrap_width(inner_cols)
          |> Enum.take(inner_rows)
          |> Enum.map(&encode_line(&1, align, inner_cols))
          |> pad_rows(inner_rows, inner_cols)
          |> Enum.map(fn row -> [color] ++ row ++ [color] end)

        {:ok, [border_row] ++ content_rows ++ [border_row]}
    end
  end

  @doc "Encode a single character to its Vestaboard code. Unknown characters become 0."
  @spec encode_char(String.t()) :: integer()
  def encode_char(char), do: Map.get(@char_map, char, @blank)

  # --- Private ---

  defp resolve_color(name) when name in @color_names, do: Map.fetch!(@color_codes, name)
  defp resolve_color(code) when is_integer(code), do: code

  defp word_wrap(text), do: word_wrap_width(text, @cols)

  defp word_wrap_width(text, width) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, width))
  end

  defp wrap_line(line, width) do
    words = String.split(line, " ", trim: true)
    wrap_words(words, [], [], width)
  end

  defp wrap_words([], [], acc, _width), do: Enum.reverse(acc)
  defp wrap_words([], current, acc, _width), do: Enum.reverse([Enum.join(Enum.reverse(current), " ") | acc])

  defp wrap_words([word | rest], [], acc, width) do
    {head, tail} = split_long_word(word, width)
    if tail == "" do
      wrap_words(rest, [head], acc, width)
    else
      wrap_words([tail | rest], [], [head | acc], width)
    end
  end

  defp wrap_words([word | rest], current, acc, width) do
    candidate = Enum.join(Enum.reverse([word | current]), " ")

    if String.length(candidate) <= width do
      wrap_words(rest, [word | current], acc, width)
    else
      finished = Enum.join(Enum.reverse(current), " ")
      wrap_words([word | rest], [], [finished | acc], width)
    end
  end

  defp split_long_word(word, width) when byte_size(word) > width do
    {String.slice(word, 0, width), String.slice(word, width, String.length(word))}
  end
  defp split_long_word(word, _width), do: {word, ""}

  defp encode_line(line, :center, width) do
    codes = line |> String.graphemes() |> Enum.map(&encode_char/1)
    len = length(codes)
    padding = width - len
    left = div(padding, 2)
    right = padding - left
    List.duplicate(@blank, left) ++ codes ++ List.duplicate(@blank, right)
  end

  defp encode_line(line, :left, width) do
    codes = line |> String.graphemes() |> Enum.map(&encode_char/1)
    len = length(codes)
    codes ++ List.duplicate(@blank, width - len)
  end

  defp pad_rows(rows, num_rows, width) do
    empty = List.duplicate(@blank, width)
    total_padding = num_rows - length(rows)
    top = div(total_padding, 2)
    bottom = total_padding - top
    List.duplicate(empty, top) ++ rows ++ List.duplicate(empty, bottom)
  end
end
