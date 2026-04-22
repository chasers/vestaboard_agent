defmodule VestaboardAgent.Router do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/chat" do
    with %{"prompt" => prompt} when is_binary(prompt) <- conn.body_params,
         result <- VestaboardAgent.display(prompt) do
      case result do
        {:ok, map} when is_map(map) ->
          send_json(conn, 200, Map.put(map, :ok, true))

        {:ok, :done} ->
          send_json(conn, 200, %{ok: true, status: "scheduled"})

        {:ok, :running, _} ->
          send_json(conn, 200, %{ok: true, status: "running"})

        {:error, reason} ->
          send_json(conn, 500, %{ok: false, error: inspect(reason)})
      end
    else
      _ ->
        send_json(conn, 400, %{ok: false, error: "missing or invalid 'prompt' field"})
    end
  end

  get "/board" do
    case VestaboardAgent.Dispatcher.last_board() do
      nil ->
        send_json(conn, 404, %{ok: false, error: "no board state yet"})

      board ->
        send_json(conn, 200, Map.put(board, :ok, true))
    end
  end

  match _ do
    send_json(conn, 404, %{ok: false, error: "not found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
