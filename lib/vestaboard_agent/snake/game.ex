defmodule VestaboardAgent.Snake.Game do
  @moduledoc """
  Pure functional Snake game state for a 6×22 Vestaboard grid.

  State:
    - snake: list of {row, col} positions, head first
    - food:  {row, col}
    - direction: :up | :down | :left | :right
    - score: integer (food eaten)

  Row 0 is the top row; col 0 is the leftmost column.
  """

  @rows 6
  @cols 22

  @type pos :: {non_neg_integer(), non_neg_integer()}
  @type direction :: :up | :down | :left | :right
  @type t :: %{
    snake: [pos()],
    food: pos(),
    direction: direction(),
    score: non_neg_integer()
  }

  @doc "Start a new game with a 3-cell snake in the centre heading right."
  @spec new() :: t()
  def new do
    snake = [{2, 4}, {2, 3}, {2, 2}]
    state = %{snake: snake, food: nil, direction: :right, score: 0}
    place_food(state)
  end

  @doc "Apply a direction and advance one step. Returns `{:ok, new_state}` or `{:error, :dead}`."
  @spec move(t(), direction()) :: {:ok, t()} | {:error, :dead}
  def move(%{snake: [head | _] = snake, food: food, score: score} = state, direction) do
    new_head = step(head, direction)

    cond do
      out_of_bounds?(new_head) -> {:error, :dead}
      new_head in snake -> {:error, :dead}
      true ->
        if new_head == food do
          new_state = %{state | snake: [new_head | snake], direction: direction, score: score + 1}
          {:ok, place_food(new_state)}
        else
          new_snake = [new_head | Enum.drop(snake, -1)]
          {:ok, %{state | snake: new_snake, direction: direction}}
        end
    end
  end

  @doc "Render the game state as an ASCII map for the LLM (H=head, B=body, F=food, .=empty)."
  @spec to_ascii(t()) :: String.t()
  def to_ascii(%{snake: [head | body], food: food}) do
    grid =
      for r <- 0..(@rows - 1) do
        for c <- 0..(@cols - 1) do
          pos = {r, c}
          cond do
            pos == head -> "H"
            pos in body -> "B"
            pos == food -> "F"
            true -> "."
          end
        end
        |> Enum.join()
      end

    Enum.join(grid, "\n")
  end

  @doc "Render the game state as a 6×22 color-code grid for direct Vestaboard dispatch."
  @spec to_grid(t()) :: [[non_neg_integer()]]
  def to_grid(%{snake: [head | body], food: food}) do
    for r <- 0..(@rows - 1) do
      for c <- 0..(@cols - 1) do
        pos = {r, c}
        cond do
          pos == head -> 69  # white
          pos in body -> 67  # green
          pos == food -> 63  # red
          true -> 0
        end
      end
    end
  end

  @doc "Render a 6×22 grid with 'GAME OVER' text on a red background."
  @spec game_over_grid(t()) :: [[non_neg_integer()]]
  def game_over_grid(%{score: score}) do
    text = "GAME OVER\nSCORE: #{score}"
    {:ok, grid} = VestaboardAgent.Renderer.render(text, border: "red")
    grid
  end

  # --- Private ---

  defp step({r, c}, :up),    do: {r - 1, c}
  defp step({r, c}, :down),  do: {r + 1, c}
  defp step({r, c}, :left),  do: {r, c - 1}
  defp step({r, c}, :right), do: {r, c + 1}

  defp out_of_bounds?({r, c}), do: r < 0 or r >= @rows or c < 0 or c >= @cols

  defp place_food(%{snake: snake} = state) do
    all_positions = for r <- 0..(@rows - 1), c <- 0..(@cols - 1), do: {r, c}
    free = all_positions -- snake
    food = Enum.random(free)
    %{state | food: food}
  end
end
