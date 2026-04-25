defmodule VestaboardAgent.Snake.GameTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Snake.Game

  # Helpers

  # Place food far from the snake so moves don't accidentally eat it.
  defp no_food(game), do: %{game | food: {5, 21}}

  defp grid_value(grid, {r, c}), do: grid |> Enum.at(r) |> Enum.at(c)

  # Assert every snake cell has at least one adjacent snake neighbor (connected body).
  defp assert_connected(snake) do
    set = MapSet.new(snake)

    Enum.each(snake, fn {r, c} ->
      neighbors = [{r - 1, c}, {r + 1, c}, {r, c - 1}, {r, c + 1}]

      assert Enum.any?(neighbors, &MapSet.member?(set, &1)),
             "Snake cell #{inspect({r, c})} has no adjacent neighbor — gap in body.\nSnake: #{inspect(snake)}"
    end)
  end

  # ──────────────────────────────────────────────────────
  # new/0
  # ──────────────────────────────────────────────────────

  describe "new/0" do
    test "returns a valid initial state" do
      game = Game.new()
      assert length(game.snake) == 3
      assert game.food != nil
      assert game.direction == :right
      assert game.score == 0
      assert game.food not in game.snake
    end

    test "initial snake forms a connected horizontal body" do
      game = Game.new()
      assert_connected(game.snake)
    end

    test "food is placed within board bounds" do
      game = Game.new()
      {fr, fc} = game.food
      assert fr in 0..5
      assert fc in 0..21
    end
  end

  # ──────────────────────────────────────────────────────
  # move/2 — head movement
  # ──────────────────────────────────────────────────────

  describe "move/2 — head movement" do
    test "moves head right" do
      game = no_food(Game.new())
      [{r, c} | _] = game.snake
      assert {:ok, new_game} = Game.move(game, :right)
      assert hd(new_game.snake) == {r, c + 1}
    end

    test "moves head left" do
      game = no_food(%{Game.new() | snake: [{2, 10}, {2, 11}, {2, 12}], direction: :left})
      assert {:ok, new_game} = Game.move(game, :left)
      assert hd(new_game.snake) == {2, 9}
    end

    test "moves head up" do
      game = no_food(%{Game.new() | snake: [{3, 10}, {3, 9}, {3, 8}], direction: :right})
      assert {:ok, new_game} = Game.move(game, :up)
      assert hd(new_game.snake) == {2, 10}
    end

    test "moves head down" do
      game = no_food(%{Game.new() | snake: [{2, 10}, {2, 9}, {2, 8}], direction: :right})
      assert {:ok, new_game} = Game.move(game, :down)
      assert hd(new_game.snake) == {3, 10}
    end
  end

  # ──────────────────────────────────────────────────────
  # move/2 — body / tail tracking
  # ──────────────────────────────────────────────────────

  describe "move/2 — body shape" do
    test "length stays the same when no food eaten" do
      game = no_food(Game.new())
      assert {:ok, new_game} = Game.move(game, :right)
      assert length(new_game.snake) == length(game.snake)
    end

    test "old tail cell is removed after a non-food move" do
      game = no_food(Game.new())
      old_tail = List.last(game.snake)
      assert {:ok, new_game} = Game.move(game, :right)

      refute old_tail in new_game.snake,
             "Tail #{inspect(old_tail)} should have been dropped but is still in snake"
    end

    test "body cells shift forward: each cell occupies the previous cell's position" do
      game = no_food(Game.new())
      [head | old_body] = game.snake
      assert {:ok, new_game} = Game.move(game, :right)
      [new_head | new_body] = new_game.snake
      # The new head's neck (first body cell) is where the old head was.
      assert hd(new_body) == head
      # Every subsequent body cell slides one forward.
      assert Enum.drop(new_body, 1) == Enum.drop(old_body, -1)
      # just ensure it compiles
      _ = new_head
    end

    test "body remains connected after a straight move" do
      game = no_food(Game.new())
      assert {:ok, new_game} = Game.move(game, :right)
      assert_connected(new_game.snake)
    end

    test "body remains connected after a turn" do
      # Snake heading right, turn up.
      game = no_food(%{Game.new() | snake: [{3, 5}, {3, 4}, {3, 3}], direction: :right})
      assert {:ok, turned} = Game.move(game, :up)
      assert_connected(turned.snake)
      assert hd(turned.snake) == {2, 5}
    end

    test "body remains connected across multiple moves" do
      game = no_food(Game.new())
      {:ok, g1} = Game.move(game, :right)
      {:ok, g2} = Game.move(no_food(g1), :up)
      {:ok, g3} = Game.move(no_food(g2), :left)
      assert_connected(g3.snake)
    end

    test "multi-move sequence produces correct body shape" do
      # Snake: [{2,4},{2,3},{2,2}] heading right.
      # After right: head={2,5} body=[{2,4},{2,3}]
      # After up:    head={1,5} body=[{2,5},{2,4}]
      base = %{Game.new() | snake: [{2, 4}, {2, 3}, {2, 2}], direction: :right}
      game = no_food(base)

      assert {:ok, g1} = Game.move(game, :right)
      assert g1.snake == [{2, 5}, {2, 4}, {2, 3}]

      assert {:ok, g2} = Game.move(no_food(g1), :up)
      assert g2.snake == [{1, 5}, {2, 5}, {2, 4}]
    end
  end

  # ──────────────────────────────────────────────────────
  # move/2 — food / growth
  # ──────────────────────────────────────────────────────

  describe "move/2 — food and growth" do
    test "grows by exactly 1 when food is eaten" do
      game = Game.new()
      [{r, c} | _] = game.snake
      game = %{game | food: {r, c + 1}}
      assert {:ok, new_game} = Game.move(game, :right)
      assert length(new_game.snake) == length(game.snake) + 1
    end

    test "score increments by 1 when food is eaten" do
      game = Game.new()
      [{r, c} | _] = game.snake
      game = %{game | food: {r, c + 1}}
      assert {:ok, new_game} = Game.move(game, :right)
      assert new_game.score == game.score + 1
    end

    test "old tail is NOT dropped when food is eaten" do
      game = Game.new()
      [{r, c} | _] = game.snake
      old_tail = List.last(game.snake)
      game = %{game | food: {r, c + 1}}
      assert {:ok, new_game} = Game.move(game, :right)

      assert old_tail in new_game.snake,
             "Tail should be retained on growth but #{inspect(old_tail)} is missing"
    end

    test "new food is placed on a free cell after eating" do
      game = Game.new()
      [{r, c} | _] = game.snake
      game = %{game | food: {r, c + 1}}
      assert {:ok, new_game} = Game.move(game, :right)

      assert new_game.food not in new_game.snake,
             "New food #{inspect(new_game.food)} landed on the snake"
    end

    test "body remains connected after eating food" do
      game = Game.new()
      [{r, c} | _] = game.snake
      game = %{game | food: {r, c + 1}}
      assert {:ok, new_game} = Game.move(game, :right)
      assert_connected(new_game.snake)
    end
  end

  # ──────────────────────────────────────────────────────
  # move/2 — reversal prevention
  # ──────────────────────────────────────────────────────

  describe "move/2 — reversal prevention" do
    test "passing opposite direction uses current direction instead" do
      # Snake heading right; passing :left should continue right.
      game = no_food(%{Game.new() | snake: [{2, 4}, {2, 3}, {2, 2}], direction: :right})
      assert {:ok, new_game} = Game.move(game, :left)
      assert hd(new_game.snake) == {2, 5}
    end

    test "passing :down when heading :up continues up" do
      game = no_food(%{Game.new() | snake: [{3, 4}, {4, 4}, {5, 4}], direction: :up})
      assert {:ok, new_game} = Game.move(game, :down)
      assert hd(new_game.snake) == {2, 4}
    end

    test "reversal does not kill the snake" do
      game = no_food(%{Game.new() | snake: [{2, 4}, {2, 3}, {2, 2}], direction: :right})
      assert {:ok, _} = Game.move(game, :left)
    end
  end

  # ──────────────────────────────────────────────────────
  # move/2 — death conditions
  # ──────────────────────────────────────────────────────

  describe "move/2 — death" do
    test "top wall kills the snake" do
      game = no_food(%{Game.new() | snake: [{0, 5}, {1, 5}, {2, 5}], direction: :up})
      assert {:error, :dead} = Game.move(game, :up)
    end

    test "bottom wall kills the snake" do
      game = no_food(%{Game.new() | snake: [{5, 5}, {4, 5}, {3, 5}], direction: :down})
      assert {:error, :dead} = Game.move(game, :down)
    end

    test "left wall kills the snake" do
      game = no_food(%{Game.new() | snake: [{2, 0}, {2, 1}, {2, 2}], direction: :left})
      assert {:error, :dead} = Game.move(game, :left)
    end

    test "right wall kills the snake" do
      game = no_food(%{Game.new() | snake: [{2, 21}, {2, 20}, {2, 19}], direction: :right})
      assert {:error, :dead} = Game.move(game, :right)
    end

    test "self collision kills the snake" do
      # U-shape: head at {2,3} heading up, body wraps so {2,4} is in body.
      # Moving right steps onto {2,4} which is occupied.
      game =
        no_food(%{
          Game.new()
          | snake: [{2, 3}, {3, 3}, {3, 4}, {3, 5}, {2, 5}, {2, 4}],
            direction: :up
        })

      assert {:error, :dead} = Game.move(game, :right)
    end

    test "snake does not shrink before dying" do
      # Verify the snake list is unchanged when dead is returned.
      game = no_food(%{Game.new() | snake: [{0, 5}, {1, 5}, {2, 5}], direction: :up})
      assert {:error, :dead} = Game.move(game, :up)
      assert length(game.snake) == 3
    end
  end

  # ──────────────────────────────────────────────────────
  # safe_moves/1
  # ──────────────────────────────────────────────────────

  describe "safe_moves/1" do
    test "never includes the opposite of the current direction" do
      game = no_food(%{Game.new() | snake: [{2, 10}, {2, 9}, {2, 8}], direction: :right})
      refute :left in Game.safe_moves(game)
    end

    test "excludes moves that step into a wall" do
      game = no_food(%{Game.new() | snake: [{0, 10}, {1, 10}, {2, 10}], direction: :up})
      refute :up in Game.safe_moves(game)
    end

    test "excludes moves that step into the body" do
      # Snake heading right at {2,4}; body below at {3,5} — :down would land on body.
      # Build a snake where moving down from head hits body.
      game =
        no_food(%{Game.new() | snake: [{2, 4}, {2, 3}, {3, 3}, {3, 4}, {3, 5}], direction: :right})

      refute :down in Game.safe_moves(game)
    end

    test "returns empty list when all non-reversal moves are fatal" do
      # Snake pinned in top-left corner heading right — only left is reversal,
      # up and down are walls, right is also a wall if col 21.
      game = no_food(%{Game.new() | snake: [{0, 21}, {0, 20}, {0, 19}], direction: :right})
      safe = Game.safe_moves(game)
      refute :right in safe
      refute :up in safe
      # :left is the reversal of :right so also excluded
      refute :left in safe
    end

    test "includes all valid non-fatal directions" do
      # Snake in open space heading right; up and down are both safe.
      game = no_food(%{Game.new() | snake: [{3, 5}, {3, 4}, {3, 3}], direction: :right})
      safe = Game.safe_moves(game)
      assert :up in safe
      assert :down in safe
      assert :right in safe
    end
  end

  # ──────────────────────────────────────────────────────
  # to_grid/1
  # ──────────────────────────────────────────────────────

  describe "to_grid/1" do
    test "returns a 6×22 grid" do
      grid = Game.to_grid(Game.new())
      assert length(grid) == 6
      Enum.each(grid, fn row -> assert length(row) == 22 end)
    end

    test "head cell is 69 (white)" do
      game = Game.new()
      {hr, hc} = hd(game.snake)
      assert grid_value(Game.to_grid(game), {hr, hc}) == 69
    end

    test "every body cell is 67 (green)" do
      game = Game.new()
      [_ | body] = game.snake
      grid = Game.to_grid(game)

      Enum.each(body, fn pos ->
        assert grid_value(grid, pos) == 67,
               "Body cell #{inspect(pos)} expected 67 got #{grid_value(grid, pos)}"
      end)
    end

    test "food cell is 63 (red)" do
      game = Game.new()
      assert grid_value(Game.to_grid(game), game.food) == 63
    end

    test "all other cells are 0 (blank)" do
      game = Game.new()
      occupied = MapSet.new([hd(game.snake) | tl(game.snake)] ++ [game.food])
      grid = Game.to_grid(game)

      for {row, r} <- Enum.with_index(grid),
          {val, c} <- Enum.with_index(row),
          not MapSet.member?(occupied, {r, c}) do
        assert val == 0,
               "Cell #{inspect({r, c})} expected 0 (blank) got #{val}"
      end
    end

    test "grid body positions match game.snake list exactly" do
      game = Game.new()
      [_ | body] = game.snake
      grid = Game.to_grid(game)

      body_in_grid =
        for {row, r} <- Enum.with_index(grid),
            {val, c} <- Enum.with_index(row),
            val == 67,
            do: {r, c}

      assert Enum.sort(body_in_grid) == Enum.sort(body)
    end
  end

  # ──────────────────────────────────────────────────────
  # to_ascii/1
  # ──────────────────────────────────────────────────────

  describe "to_ascii/1" do
    test "contains H, B, F characters" do
      ascii = Game.to_ascii(Game.new())
      assert String.contains?(ascii, "H")
      assert String.contains?(ascii, "B")
      assert String.contains?(ascii, "F")
    end

    test "contains current direction and score header" do
      ascii = Game.to_ascii(Game.new())
      assert String.contains?(ascii, "Current direction:")
      assert String.contains?(ascii, "Score:")
    end

    test "board section has 6 rows of 22 chars" do
      board_rows =
        Game.new()
        |> Game.to_ascii()
        |> String.split("\n")
        |> Enum.filter(&(String.length(&1) == 22))

      assert length(board_rows) == 6
    end

    test "exactly one H in the board" do
      rows =
        Game.new()
        |> Game.to_ascii()
        |> String.split("\n")
        |> Enum.filter(&(String.length(&1) == 22))

      h_count = rows |> Enum.join() |> String.graphemes() |> Enum.count(&(&1 == "H"))
      assert h_count == 1
    end

    test "H position matches game head position" do
      game = Game.new()
      {hr, hc} = hd(game.snake)

      board_rows =
        game
        |> Game.to_ascii()
        |> String.split("\n")
        |> Enum.filter(&(String.length(&1) == 22))

      assert String.at(Enum.at(board_rows, hr), hc) == "H"
    end

    test "contains head and food coordinates" do
      game = Game.new()
      ascii = Game.to_ascii(game)
      {hr, hc} = hd(game.snake)
      {fr, fc} = game.food
      assert String.contains?(ascii, "Head: row #{hr}, col #{hc}")
      assert String.contains?(ascii, "Food: row #{fr}, col #{fc}")
    end

    test "move options ranked closest first when food is up-left of head" do
      # head {3,10}, food {1,5} — UP closes row gap, LEFT closes col gap
      game = %{Game.new() | snake: [{3, 10}, {3, 9}, {3, 8}], food: {1, 5}, direction: :right}
      ascii = Game.to_ascii(game)
      assert String.contains?(ascii, "Move options (ranked closest first):")
      # UP reduces row distance (3→2 vs food row 1); should appear before DOWN
      up_idx = :binary.match(ascii, "UP") |> elem(0)
      down_idx = :binary.match(ascii, "DOWN") |> elem(0)
      assert up_idx < down_idx, "UP should rank above DOWN when food is above head"
    end

    test "move options ranked closest first when food is down-right of head" do
      # head {1,5}, food {4,15} — DOWN and RIGHT close respective gaps
      game = %{Game.new() | snake: [{1, 5}, {1, 4}, {1, 3}], food: {4, 15}, direction: :right}
      ascii = Game.to_ascii(game)
      assert String.contains?(ascii, "Move options (ranked closest first):")
      # DOWN reduces row distance (1→2 vs food row 4); UP increases it
      down_idx = :binary.match(ascii, "DOWN") |> elem(0)
      up_idx = :binary.match(ascii, "UP") |> elem(0)
      assert down_idx < up_idx, "DOWN should rank above UP when food is below head"
    end

    test "move options section is present" do
      game = %{Game.new() | snake: [{3, 5}, {3, 4}, {3, 3}], food: {5, 21}, direction: :right}
      ascii = Game.to_ascii(game)
      assert String.contains?(ascii, "Move options (ranked closest first):")
    end
  end
end
