defmodule VestaboardAgent.Agents.SnakeAgentTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agents.SnakeAgent

  defp stub_dispatch do
    fn _grid -> :ok end
  end

  describe "name/0 and keywords/0" do
    test "name is 'snake'" do
      assert SnakeAgent.name() == "snake"
    end

    test "keywords contains 'snake'" do
      assert "snake" in SnakeAgent.keywords()
    end
  end

  describe "handle/2" do
    setup do
      Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")
      on_exit(fn -> Application.delete_env(:vestaboard_agent, :llm) end)
      :ok
    end

    test "returns {:ok, :done} when max_moves is reached" do
      plug = fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "RIGHT"}]})
      end

      assert {:ok, :done} =
               SnakeAgent.handle("play snake", %{
                 llm_opts: [plug: plug],
                 dispatch_fn: stub_dispatch(),
                 max_moves: 3,
                 min_frame_ms: 0
               })
    end

    test "returns {:ok, :done} after LLM drives snake into a wall" do
      plug = fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "UP"}]})
      end

      assert {:ok, :done} =
               SnakeAgent.handle("play snake", %{
                 llm_opts: [plug: plug],
                 dispatch_fn: stub_dispatch(),
                 max_moves: 5,
                 min_frame_ms: 0
               })
    end

    test "dispatches a grid on each move and a final game-over grid" do
      grids = :ets.new(:grids, [:bag, :public])

      dispatch_fn = fn grid ->
        :ets.insert(grids, {:grid, grid})
        :ok
      end

      plug = fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "RIGHT"}]})
      end

      SnakeAgent.handle("play snake", %{
        llm_opts: [plug: plug],
        dispatch_fn: dispatch_fn,
        max_moves: 3,
        min_frame_ms: 0
      })

      # 3 move frames + 1 game-over frame = 4 dispatches
      assert :ets.info(grids, :size) == 4
    end
  end
end
