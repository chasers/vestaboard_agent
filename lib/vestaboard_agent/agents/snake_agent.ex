defmodule VestaboardAgent.Agents.SnakeAgent do
  @moduledoc """
  LLM-driven Snake game on the Vestaboard.

  Triggered by prompts containing "snake". The LLM decides each move
  by reading an ASCII representation of the board. The game runs until
  the snake dies, then displays a GAME OVER frame with the final score.

  Pacing is driven by board backpressure: if the board returns 429
  the Client.Local retry loop provides natural delay (~1-7s). If all
  retries are exhausted the frame is skipped silently and the game
  continues. No fixed sleep is used.
  """

  require Logger

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
    max_moves = Map.get(context, :max_moves, :infinity)
    game = Game.new()
    play(game, llm_opts, dispatch_fn, max_moves)
    {:ok, :done}
  end

  # --- Game loop ---

  defp play(game, _llm_opts, dispatch_fn, 0) do
    Logger.info("[snake] max_moves reached — ending game (score #{game.score})")
    game_over(game, dispatch_fn)
  end

  defp play(game, llm_opts, dispatch_fn, moves_left) do
    case dispatch_fn.(Game.to_grid(game)) do
      {:error, reason} ->
        Logger.warning("[snake] frame skipped (#{inspect(reason)})")
      _ ->
        :ok
    end

    safe = Game.safe_moves(game)

    if safe == [] do
      Logger.info("[snake] no safe moves — game over (score #{game.score})")
      game_over(game, dispatch_fn)
    else
      t0 = System.monotonic_time(:millisecond)
      direction = pick_direction(game, safe, llm_opts)
      elapsed = System.monotonic_time(:millisecond) - t0

      Logger.info("[snake] move=#{direction} safe=#{inspect(safe)} score=#{game.score} head=#{inspect(hd(game.snake))} llm=#{elapsed}ms")

      next_left = if moves_left == :infinity, do: :infinity, else: moves_left - 1

      case Game.move(game, direction) do
        {:ok, new_game} -> play(new_game, llm_opts, dispatch_fn, next_left)
        {:error, :dead} ->
          Logger.info("[snake] died on #{direction} — game over (score #{game.score})")
          game_over(game, dispatch_fn)
      end
    end
  end

  defp pick_direction(game, safe, llm_opts) do
    ascii = Game.to_ascii(game)

    case LLM.snake_move(ascii, llm_opts) do
      {:ok, dir} ->
        if dir in safe do
          dir
        else
          Logger.info("[snake] LLM chose unsafe #{dir}, overriding with #{hd(safe)}")
          hd(safe)
        end

      {:error, reason} ->
        Logger.warning("[snake] LLM error #{inspect(reason)}, using #{hd(safe)}")
        hd(safe)
    end
  end

  defp game_over(game, dispatch_fn) do
    dispatch_fn.(Game.game_over_grid(game))
  end
end
