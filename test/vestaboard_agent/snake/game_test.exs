defmodule VestaboardAgent.Snake.GameTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Snake.Game

  describe "new/0" do
    test "returns a valid initial state" do
      game = Game.new()
      assert length(game.snake) == 3
      assert game.food != nil
      assert game.direction == :right
      assert game.score == 0
      assert game.food not in game.snake
    end
  end

  describe "move/2" do
    test "moves the head in the given direction" do
      game = Game.new()
      [{r, c} | _] = game.snake
      assert {:ok, new_game} = Game.move(game, :right)
      assert hd(new_game.snake) == {r, c + 1}
    end

    test "snake length stays the same when no food eaten" do
      game = %{Game.new() | food: {5, 21}}
      len = length(game.snake)
      assert {:ok, new_game} = Game.move(game, :right)
      assert length(new_game.snake) == len
    end

    test "snake grows when food is eaten" do
      game = Game.new()
      [{r, c} | _] = game.snake
      food_pos = {r, c + 1}
      game = %{game | food: food_pos}
      assert {:ok, new_game} = Game.move(game, :right)
      assert length(new_game.snake) == length(game.snake) + 1
      assert new_game.score == 1
    end

    test "returns {:error, :dead} on wall collision" do
      game = %{Game.new() | snake: [{0, 0}, {0, 1}, {0, 2}]}
      assert {:error, :dead} = Game.move(game, :up)
      assert {:error, :dead} = Game.move(game, :left)
    end

    test "returns {:error, :dead} on self collision" do
      # U-shaped snake: head at {2,5}, body curves down and back; moving left hits {2,4}
      game = %{Game.new() | snake: [{2, 5}, {3, 5}, {3, 4}, {3, 3}, {2, 3}, {2, 4}]}
      assert {:error, :dead} = Game.move(game, :left)
    end
  end

  describe "to_ascii/1" do
    test "contains H, B, F characters" do
      game = Game.new()
      ascii = Game.to_ascii(game)
      assert String.contains?(ascii, "H")
      assert String.contains?(ascii, "B")
      assert String.contains?(ascii, "F")
    end

    test "has 6 rows" do
      game = Game.new()
      rows = game |> Game.to_ascii() |> String.split("\n")
      assert length(rows) == 6
    end

    test "each row is 22 chars wide" do
      game = Game.new()
      game
      |> Game.to_ascii()
      |> String.split("\n")
      |> Enum.each(fn row -> assert String.length(row) == 22 end)
    end
  end

  describe "to_grid/1" do
    test "returns a 6×22 grid" do
      game = Game.new()
      grid = Game.to_grid(game)
      assert length(grid) == 6
      Enum.each(grid, fn row -> assert length(row) == 22 end)
    end

    test "head is white (69), body is green (67), food is red (63)" do
      game = Game.new()
      [{hr, hc} | body] = game.snake
      {fr, fc} = game.food
      grid = Game.to_grid(game)

      assert Enum.at(Enum.at(grid, hr), hc) == 69
      Enum.each(body, fn {r, c} ->
        assert Enum.at(Enum.at(grid, r), c) == 67
      end)
      assert Enum.at(Enum.at(grid, fr), fc) == 63
    end
  end
end
