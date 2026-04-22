defmodule VestaboardAgent.E2E.SnakeTest do
  use VestaboardAgent.E2ECase

  @moduletag timeout: 300_000

  alias VestaboardAgent.{Agents.SnakeAgent, Client, Dispatcher}

  # Color codes used in Game.to_grid/1
  @head_code 69
  @body_code 67

  describe "snake game" do
    test "each frame shows the snake head moving exactly one cell" do
      sent_frames = Agent.start_link(fn -> [] end) |> elem(1)
      read_frames = Agent.start_link(fn -> [] end) |> elem(1)
      err_count = :counters.new(1, [])

      dispatch_fn = fn grid ->
        result = Dispatcher.dispatch(grid)
        case result do
          {:ok, _} -> Agent.update(sent_frames, &[grid | &1])
          {:error, _} -> :counters.add(err_count, 1, 1)
        end
        result
      end

      read_fn = fn ->
        result = Client.read()
        case result do
          {:ok, grid} -> Agent.update(read_frames, &[grid | &1])
          _ -> :ok
        end
        result
      end

      {:ok, :done} = SnakeAgent.handle("play snake", %{
        dispatch_fn: dispatch_fn,
        read_fn: read_fn,
        max_moves: 6
      })

      sent = Agent.get(sent_frames, & &1) |> Enum.reverse()
      reads = Agent.get(read_frames, & &1) |> Enum.reverse()
      skipped = :counters.get(err_count, 1)

      # Drop the game-over frame (last sent); only inspect game frames
      game_frames = Enum.drop(sent, -1)
      heads = Enum.map(game_frames, &head_position/1)

      body_lengths = Enum.map(game_frames, fn f -> length(body_positions(f)) end)

      IO.puts("\n  [snake e2e] sent=#{length(sent)} reads=#{length(reads)} skipped=#{skipped}")
      IO.puts("  [snake e2e] head positions: #{inspect(heads)}")
      IO.puts("  [snake e2e] body lengths:   #{inspect(body_lengths)}")

      # --- No dispatch errors ---
      assert skipped == 0,
        "#{skipped} frame(s) were skipped due to dispatch errors"

      # --- Head found in every game frame ---
      Enum.each(Enum.with_index(heads), fn {pos, i} ->
        assert pos != nil,
          "No head (value #{@head_code}) found in frame #{i}.\nFrame: #{inspect(Enum.at(game_frames, i))}"
      end)

      # --- Consecutive frames: head moves exactly 1 cell, no duplicates ---
      game_frames
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.each(fn {[frame_a, frame_b], i} ->
        {ra, ca} = head_position(frame_a)
        {rb, cb} = head_position(frame_b)
        dist = abs(ra - rb) + abs(ca - cb)

        assert dist != 0,
          "Frame #{i}→#{i + 1}: snake head did not move (stuck at {#{ra}, #{ca}})"

        assert dist == 1,
          "Frame #{i}→#{i + 1}: head jumped #{dist} cells from {#{ra},#{ca}} to {#{rb},#{cb}} — expected adjacent step"
      end)

      # --- Body in frame N+1 starts where head was in frame N (snake continuity) ---
      game_frames
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.each(fn {[frame_a, frame_b], i} ->
        prev_head = head_position(frame_a)
        next_body = body_positions(frame_b)

        assert prev_head in next_body,
          "Frame #{i}→#{i + 1}: previous head #{inspect(prev_head)} not found in next body #{inspect(next_body)}"
      end)

      # --- Body length never shrinks between frames (same size or +1 when food eaten) ---
      game_frames
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index()
      |> Enum.each(fn {[frame_a, frame_b], i} ->
        len_a = length(body_positions(frame_a))
        len_b = length(body_positions(frame_b))
        delta = len_b - len_a

        assert delta >= 0,
          "Frame #{i}→#{i + 1}: body shrunk from #{len_a} to #{len_b} cells"

        assert delta <= 1,
          "Frame #{i}→#{i + 1}: body grew by #{delta} cells (expected 0 or 1)"
      end)

      # --- Each snake cell has at least one adjacent snake neighbor (no gaps) ---
      # Uses a set-membership check rather than ordered traversal because
      # body_positions/1 returns cells in row-major order, not snake order.
      game_frames
      |> Enum.with_index()
      |> Enum.each(fn {frame, i} ->
        head = head_position(frame)
        body = body_positions(frame)
        snake = [head | body]

        if length(snake) > 1 do
          snake_set = MapSet.new(snake)

          Enum.each(snake, fn {r, c} ->
            neighbors = [{r - 1, c}, {r + 1, c}, {r, c - 1}, {r, c + 1}]
            adjacent = Enum.count(neighbors, &MapSet.member?(snake_set, &1))

            assert adjacent >= 1,
              "Frame #{i}: snake cell #{inspect({r, c})} has no adjacent snake neighbors — gap detected.\nSnake: #{inspect(snake)}"
          end)
        end
      end)

      # --- Board read-backs match sent frames (no stale display) ---
      # For each sent frame, there should be a matching read within the read sequence.
      game_frames
      |> Enum.with_index()
      |> Enum.each(fn {sent_grid, i} ->
        assert sent_grid in reads,
          "Frame #{i}: sent grid was never confirmed by board read-back.\n" <>
          "Sent head: #{inspect(head_position(sent_grid))}\n" <>
          "Read heads: #{reads |> Enum.map(&head_position/1) |> inspect()}"
      end)
    end
  end

  # --- Helpers ---

  defp head_position(grid) do
    Enum.find_value(Enum.with_index(grid), fn {row, r} ->
      case Enum.find_index(row, &(&1 == @head_code)) do
        nil -> nil
        c -> {r, c}
      end
    end)
  end

  defp body_positions(grid) do
    for {row, r} <- Enum.with_index(grid),
        {val, c} <- Enum.with_index(row),
        val == @body_code,
        do: {r, c}
  end
end
