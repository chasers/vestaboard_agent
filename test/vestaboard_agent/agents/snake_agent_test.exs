defmodule VestaboardAgent.Agents.SnakeAgentTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Agents.SnakeAgent

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

    test "returns {:ok, :done} when snake immediately hits a wall" do
      plug = fn conn ->
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => "LEFT"}]})
      end

      assert {:ok, :done} = SnakeAgent.handle("play snake", %{
        llm_opts: [plug: plug],
        dispatch_fn: fn _grid -> :ok end
      })
    end

    test "returns {:ok, :done} after a few moves then death" do
      counter = :counters.new(1, [])

      plug = fn conn ->
        n = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        dir = case n do
          0 -> "RIGHT"
          1 -> "RIGHT"
          _ -> "UP"
        end
        Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => dir}]})
      end

      assert {:ok, :done} = SnakeAgent.handle("play snake", %{
        llm_opts: [plug: plug],
        dispatch_fn: fn _grid -> :ok end
      })
    end
  end
end
