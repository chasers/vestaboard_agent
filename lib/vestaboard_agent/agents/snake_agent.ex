defmodule VestaboardAgent.Agents.SnakeAgent do
  @moduledoc """
  LLM-driven Snake game on the Vestaboard.

  Triggered by prompts containing "snake". The LLM decides each move
  by reading an ASCII representation of the board. The game runs until
  the snake dies, then displays a GAME OVER frame with the final score.

  After each successful write, the agent polls the board until it reads
  back the frame it just sent. This ensures the board has rendered each
  frame before the next one is dispatched.
  """

  require Logger

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.{Client, Dispatcher, LLM, Snake.Game}

  @lock_key :snake_running

  @frame_poll_interval_ms 100
  @frame_poll_max_attempts 20
  # Default minimum wall-clock time between frames. The board physically takes
  # ~1-2s to render even when the API acknowledges quickly. Override via
  # context: %{min_frame_ms: 0} in tests to skip the delay.
  @default_min_frame_ms 2_000

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
        read_fn = Map.get(context, :read_fn, &Client.read/0)
        max_moves = Map.get(context, :max_moves, :infinity)
        min_frame_ms = Map.get(context, :min_frame_ms, @default_min_frame_ms)
        game = Game.new()
        play(game, llm_opts, dispatch_fn, read_fn, max_moves, min_frame_ms)
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

  defp play(game, _llm_opts, dispatch_fn, _read_fn, 0, _min_frame_ms) do
    Logger.info("[snake] max_moves reached — ending game (score #{game.score})")
    game_over(game, dispatch_fn)
  end

  defp play(game, llm_opts, dispatch_fn, read_fn, moves_left, min_frame_ms) do
    frame_start = System.monotonic_time(:millisecond)
    grid = Game.to_grid(game)

    case dispatch_fn.(grid) do
      {:error, reason} ->
        Logger.error("[snake] frame skipped (#{inspect(reason)})")
      _ ->
        await_frame_applied(read_fn, grid)
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

      # Enforce minimum frame time so the display can finish rendering before
      # the next frame is sent.
      frame_elapsed = System.monotonic_time(:millisecond) - frame_start
      if frame_elapsed < min_frame_ms do
        Process.sleep(min_frame_ms - frame_elapsed)
      end

      next_left = if moves_left == :infinity, do: :infinity, else: moves_left - 1

      case Game.move(game, direction) do
        {:ok, new_game} -> play(new_game, llm_opts, dispatch_fn, read_fn, next_left, min_frame_ms)
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

  # Poll until the board reflects the frame we just sent, or until we exhaust
  # retries. This confirms the display has moved on to the new frame before we
  # compute the next move.
  defp await_frame_applied(read_fn, expected_grid, attempt \\ 0) do
    case read_fn.() do
      {:ok, ^expected_grid} ->
        :ok

      {:ok, _other} when attempt < @frame_poll_max_attempts ->
        Process.sleep(@frame_poll_interval_ms)
        await_frame_applied(read_fn, expected_grid, attempt + 1)

      {:ok, _other} ->
        Logger.warning("[snake] board did not reflect sent frame after #{@frame_poll_max_attempts} attempts")

      {:error, reason} ->
        Logger.warning("[snake] board read failed: #{inspect(reason)}")
    end
  end
end
