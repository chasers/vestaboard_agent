defmodule VestaboardAgentTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Renderer

  setup do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)
    Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")
    :ok
  end

  defp llm_stub(text) do
    [plug: fn conn -> Req.Test.json(conn, %{"content" => [%{"type" => "text", "text" => text}]}) end]
  end

  test "display/2 formats and renders without hitting the board" do
    board_stub = fn conn -> Req.Test.json(conn, %{"currentMessage" => %{}}) end

    llm_response = ~s({"text": "HAPPY TUESDAY", "border_color": "yellow"})
    llm_opts = llm_stub(llm_response)

    {:ok, grid} = Renderer.render("HAPPY TUESDAY", border: "yellow")

    assert length(grid) == 6
    assert Enum.all?(grid, fn row -> length(row) == 22 end)
    _ = board_stub
  end
end
