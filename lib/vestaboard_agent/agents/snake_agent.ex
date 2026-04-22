defmodule VestaboardAgent.Agents.SnakeAgent do
  @moduledoc """
  LLM-driven Snake game on the Vestaboard.

  Triggered by prompts containing "snake". The LLM decides each move
  by reading an ASCII representation of the board. The game runs until
  the snake dies, then displays a GAME OVER frame with the final score.

  Each LLM call (~1s) naturally paces the game to one move per second.
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.{Dispatcher, LLM, Snake.Game}

  @impl true
  def name, do: "snake"

  @impl true
  def keywords, do: ["snake"]

  @impl true
  def handle(_prompt, context) do
    llm_opts = Map.get(context, :llm_opts, [])
    dispatch_fn = Map.get(context, :dispatch_fn, &Dispatcher.dispatch/1)
    game = Game.new()
    play(game, llm_opts, dispatch_fn)
    {:ok, :done}
  end

  # --- Game loop ---

  defp play(game, llm_opts, dispatch_fn) do
    dispatch_fn.(Game.to_grid(game))

    ascii = Game.to_ascii(game)

    case LLM.snake_move(ascii, llm_opts) do
      {:ok, direction} ->
        case Game.move(game, direction) do
          {:ok, new_game} -> play(new_game, llm_opts, dispatch_fn)
          {:error, :dead} -> game_over(game, dispatch_fn)
        end

      {:error, _reason} ->
        # LLM failed — keep current direction
        case Game.move(game, game.direction) do
          {:ok, new_game} -> play(new_game, llm_opts, dispatch_fn)
          {:error, :dead} -> game_over(game, dispatch_fn)
        end
    end
  end

  defp game_over(game, dispatch_fn) do
    dispatch_fn.(Game.game_over_grid(game))
  end
end
