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

  Returns `{:ok, [[integer()]]}`.
  """
  @spec render(String.t(), keyword()) :: {:ok, [[integer()]]}
  def render(text, opts \\ []) when is_binary(text) do
    align = Keyword.get(opts, :align, :center)

    grid =
      text
      |> String.upcase()
      |> word_wrap()
      |> Enum.take(@rows)
      |> Enum.map(&encode_line(&1, align))
      |> pad_rows()

    {:ok, grid}
  end

  @doc "Encode a single character to its Vestaboard code. Unknown characters become 0."
  @spec encode_char(String.t()) :: integer()
  def encode_char(char), do: Map.get(@char_map, char, @blank)

  # --- Private ---

  defp word_wrap(text) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line/1)
  end

  defp wrap_line(line) do
    words = String.split(line, " ", trim: true)
    wrap_words(words, [], [])
  end

  defp wrap_words([], [], acc), do: Enum.reverse(acc)
  defp wrap_words([], current, acc), do: Enum.reverse([Enum.join(Enum.reverse(current), " ") | acc])

  defp wrap_words([word | rest], [], acc) do
    # Word longer than @cols gets hard-truncated
    {head, tail} = split_long_word(word)
    if tail == "" do
      wrap_words(rest, [head], acc)
    else
      wrap_words([tail | rest], [], [head | acc])
    end
  end

  defp wrap_words([word | rest], current, acc) do
    candidate = Enum.join(Enum.reverse([word | current]), " ")

    if String.length(candidate) <= @cols do
      wrap_words(rest, [word | current], acc)
    else
      finished = Enum.join(Enum.reverse(current), " ")
      wrap_words([word | rest], [], [finished | acc])
    end
  end

  defp split_long_word(word) when byte_size(word) > @cols do
    {String.slice(word, 0, @cols), String.slice(word, @cols, String.length(word))}
  end
  defp split_long_word(word), do: {word, ""}

  defp encode_line(line, :center) do
    codes = line |> String.graphemes() |> Enum.map(&encode_char/1)
    len = length(codes)
    padding = @cols - len
    left = div(padding, 2)
    right = padding - left
    List.duplicate(@blank, left) ++ codes ++ List.duplicate(@blank, right)
  end

  defp encode_line(line, :left) do
    codes = line |> String.graphemes() |> Enum.map(&encode_char/1)
    len = length(codes)
    codes ++ List.duplicate(@blank, @cols - len)
  end

  defp pad_rows(rows) do
    empty = List.duplicate(@blank, @cols)
    rows ++ List.duplicate(empty, @rows - length(rows))
  end
end
