defmodule VestaboardAgent.Agents.SnakeAgent do
  @moduledoc """
  LLM-driven Snake game on the Vestaboard.

  Triggered by prompts containing "snake". The LLM decides each move
  by reading an ASCII representation of the board. The game runs until
  the snake dies, then displays a GAME OVER frame with the final score.

  Each frame is held for a fixed interval before the next is dispatched.
  """

  require Logger

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.Clients.Anthropic, as: LLM
  alias VestaboardAgent.{Dispatcher, Snake.Game}

  @lock_key :snake_running

  # Default time to display each frame. Override via context min_frame_ms
  # (pass 0 in tests to skip the delay).
  @default_min_frame_ms 20_000

  @impl true
  def name, do: "snake"

  @impl true
  def keywords, do: ["snake"]

  @impl true
  def handle(_prompt, context) do
    if acquire_lock() do
      try do
        llm_opts = Map.get(context, :llm_opts, [])
        dispatch_fn = Map.get(context, :dispatch_fn, &Dispatcher.dispatch/1)
        max_moves = Map.get(context, :max_moves, :infinity)
        min_frame_ms = Map.get(context, :min_frame_ms, @default_min_frame_ms)
        game = Game.new()
        play(game, llm_opts, dispatch_fn, max_moves, min_frame_ms)
        {:ok, :done}
      after
        release_lock()
      end
    else
      Logger.warning("[snake] game already in progress — ignoring duplicate start")
      {:ok, :done}
    end
  end

  defp acquire_lock do
    case :ets.lookup(:snake_locks, @lock_key) do
      [{@lock_key, pid}] when pid != self() ->
        if Process.alive?(pid) do
          Logger.info("[snake] stopping previous game (pid #{inspect(pid)}) to start new one")
          Process.exit(pid, :kill)
          ref = Process.monitor(pid)
          receive do
            {:DOWN, ^ref, :process, ^pid, _} -> :ok
          after
            3_000 -> :ok
          end
        end
        :ets.delete(:snake_locks, @lock_key)
      _ ->
        :ok
    end
    :ets.insert_new(:snake_locks, {@lock_key, self()})
  end

  defp release_lock do
    :ets.delete(:snake_locks, @lock_key)
  end

  @doc "Return true if a snake game is currently running."
  def running? do
    case :ets.lookup(:snake_locks, @lock_key) do
      [{@lock_key, pid}] -> Process.alive?(pid)
      [] -> false
    end
  end

  # --- Game loop ---

  defp play(game, _llm_opts, dispatch_fn, 0, _min_frame_ms) do
    Logger.info("[snake] max_moves reached — ending game (score #{game.score})")
    game_over(game, dispatch_fn)
  end

  defp play(game, llm_opts, dispatch_fn, moves_left, min_frame_ms) do
    case dispatch_fn.(Game.to_grid(game)) do
      {:error, reason} -> Logger.error("[snake] frame skipped (#{inspect(reason)})")
      _ -> :ok
    end

    Process.sleep(min_frame_ms)

    safe = Game.safe_moves(game)

    if safe == [] do
      Logger.info("[snake] no safe moves — game over (score #{game.score})")
      game_over(game, dispatch_fn)
    else
      t0 = System.monotonic_time(:millisecond)
      direction = pick_direction(game, safe, llm_opts)
      elapsed = System.monotonic_time(:millisecond) - t0

      {hr, hc} = hd(game.snake)
      {fr, fc} = game.food
      dist = abs(fr - hr) + abs(fc - hc)
      Logger.info("[snake] move=#{direction} safe=#{inspect(safe)} score=#{game.score} head={#{hr},#{hc}} food={#{fr},#{fc}} dist=#{dist} llm=#{elapsed}ms")

      next_left = if moves_left == :infinity, do: :infinity, else: moves_left - 1

      case Game.move(game, direction) do
        {:ok, new_game} -> play(new_game, llm_opts, dispatch_fn, next_left, min_frame_ms)
        {:error, :dead} ->
          Logger.info("[snake] died on #{direction} — game over (score #{game.score})")
          game_over(game, dispatch_fn)
      end
    end
  end

  defp pick_direction(game, safe, llm_opts) do
    {head, food} = {hd(game.snake), game.food}
    {fr, fc} = food

    current_dist = manhattan(head, food)

    closer = Enum.filter(safe, fn dir ->
      {nr, nc} = Game.step_public(head, dir)
      abs(fr - nr) + abs(fc - nc) < current_dist
    end)

    if closer != [] do
      # At least one safe move reduces distance — pick the closest, skip LLM.
      best = Enum.min_by(closer, fn dir ->
        {nr, nc} = Game.step_public(head, dir)
        abs(fr - nr) + abs(fc - nc)
      end)
      Logger.info("[snake] greedy move=#{best} (#{length(closer)} closer option(s))")
      best
    else
      # All safe moves increase distance — use LLM to navigate around obstacle.
      Logger.info("[snake] no closer moves, asking LLM")
      fallback = Enum.min_by(safe, fn dir ->
        {nr, nc} = Game.step_public(head, dir)
        abs(fr - nr) + abs(fc - nc)
      end)

      case LLM.snake_move(Game.to_ascii(game), llm_opts) do
        {:ok, dir} when is_atom(dir) ->
          if dir in safe, do: dir, else: (Logger.info("[snake] LLM chose unsafe #{dir}, using fallback #{fallback}"); fallback)
        {:ok, dir} ->
          Logger.info("[snake] LLM chose unsafe #{dir}, using fallback #{fallback}")
          fallback
        {:error, reason} ->
          Logger.warning("[snake] LLM error #{inspect(reason)}, using fallback #{fallback}")
          fallback
      end
    end
  end

  defp manhattan({r1, c1}, {r2, c2}), do: abs(r1 - r2) + abs(c1 - c2)

  defp game_over(game, dispatch_fn) do
    dispatch_fn.(Game.game_over_grid(game))
  end
end
