defmodule VestaboardAgent.E2E.HttpChatTest do
  use VestaboardAgent.E2ECase

  alias VestaboardAgent.Dispatcher

  # These tests hit the live HTTP server (Bandit on port 4000) via Req.
  # The server is started by the application supervision tree.

  describe "POST /chat" do
    test "valid prompt returns ok:true and updates the board", context do
      body = e2e_http_post(context, %{"prompt" => "hello"})

      assert body["ok"] == true,
             "Expected ok:true, got: #{inspect(body)}"

      board = Dispatcher.last_board()
      assert board != nil, "Board was not updated after POST /chat"
      assert is_list(board.grid)
      assert is_binary(board.text)
    end

    test "missing prompt field returns 400", context do
      resp = Req.post!("#{context[:http_base]}/chat", json: %{"message" => "wrong key"})
      assert resp.status == 400
      assert resp.body["ok"] == false
    end

    test "non-JSON body returns 400", context do
      resp =
        Req.post!("#{context[:http_base]}/chat",
          headers: [{"content-type", "text/plain"}],
          body: "just a string"
        )

      assert resp.status in [400, 415]
    end

    test "prompt with special characters is handled gracefully", context do
      body = e2e_http_post(context, %{"prompt" => "show price $4.99/lb today"})

      assert body["ok"] == true,
             "Expected ok:true for special char prompt, got: #{inspect(body)}"
    end
  end

  describe "GET /board" do
    test "returns 404 when no board has been dispatched", context do
      :sys.replace_state(Dispatcher, fn state -> %{state | last_board: nil} end)
      {status, body} = e2e_http_get(context)
      assert status == 404
      assert body["ok"] == false
    end

    test "returns 200 with grid and text after a dispatch", context do
      e2e_http_post(context, %{"prompt" => "hello world"})
      {status, body} = e2e_http_get(context)

      assert status == 200
      assert body["ok"] == true

      assert is_list(body["grid"]),
             "Expected grid to be a list, got: #{inspect(body["grid"])}"

      assert is_binary(body["text"]),
             "Expected text to be a string, got: #{inspect(body["text"])}"

      assert length(body["grid"]) == 6,
             "Expected 6 grid rows, got: #{length(body["grid"])}"
    end

    test "grid rows each have 22 columns", context do
      e2e_http_post(context, %{"prompt" => "test grid shape"})
      {_status, body} = e2e_http_get(context)

      Enum.each(body["grid"], fn row ->
        assert length(row) == 22,
               "Expected 22 cols per row, got #{length(row)}: #{inspect(row)}"
      end)
    end

    test "text field matches what was sent to the board", context do
      e2e_http_post(context, %{"prompt" => "say VESTABOARD TEST"})
      Process.sleep(500)
      {_status, body} = e2e_http_get(context)
      assert is_binary(body["text"])
      assert body["text"] != ""
    end
  end

  describe "unknown routes" do
    test "returns 404 for unknown path", context do
      resp = Req.get!("#{context[:http_base]}/nonexistent")
      assert resp.status == 404
    end
  end
end
