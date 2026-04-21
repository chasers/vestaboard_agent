defmodule VestaboardAgent.LuaAPI do
  @moduledoc """
  Elixir bindings exposed to every Lua tool script.

  Functions defined here with `deflua` are callable from Lua under the
  `vestaboard` namespace. The module is loaded into a Lua state via
  `Lua.load_api/2`.

  ## Available Lua functions

    * `vestaboard.log(msg)` — write a string to Logger
    * `vestaboard.truncate(str, len)` — truncate a string to `len` characters
    * `vestaboard.http_get(url)` — HTTP GET; returns `body, status`
    * `vestaboard.http_post(url, body)` — HTTP POST with string body; returns `body, status`
    * `vestaboard.json_decode(str)` — parse a JSON string into a Lua table

  ## HTTP return values

  Both HTTP functions return two values: the response body (string) and the
  HTTP status code (integer). On a network error the body is `nil` and the
  status is an error description string.

  ## Example Lua script

      local body, status = vestaboard.http_get("https://wttr.in/?format=3")
      if status == 200 then
        return body
      else
        return "weather unavailable"
      end

  ## Test injection

  In tests, inject a `Req.Test` plug via app config to avoid real network calls:

      Application.put_env(:vestaboard_agent, :lua_http, plug: {Req.Test, MyTest})
  """

  use Lua.API, scope: "vestaboard"

  require Logger

  deflua log(msg) do
    Logger.info("[lua tool] #{msg}")
    []
  end

  deflua truncate(str, len) do
    [String.slice(to_string(str), 0, trunc(len))]
  end

  deflua http_get(url) do
    req = build_req()

    case Req.get(req, url: to_string(url)) do
      {:ok, %{status: status, body: body}} -> [stringify_body(body), status]
      {:error, reason} -> [nil, inspect(reason)]
    end
  end

  deflua http_post(url, body) do
    req = build_req()

    case Req.post(req, url: to_string(url), body: to_string(body)) do
      {:ok, %{status: status, body: resp_body}} -> [stringify_body(resp_body), status]
      {:error, reason} -> [nil, inspect(reason)]
    end
  end

  deflua json_decode(str), lua do
    case Jason.decode(to_string(str)) do
      {:ok, data} ->
        {encoded, new_luerl_state} = :luerl.encode(data, lua.state)
        {[encoded], %{lua | state: new_luerl_state}}

      {:error, _} ->
        {[nil], lua}
    end
  end

  defp build_req do
    base = Req.new(retry: false)

    case Application.get_env(:vestaboard_agent, :lua_http, [])[:plug] do
      nil -> base
      plug -> Req.merge(base, plug: plug)
    end
  end

  defp stringify_body(body) when is_binary(body), do: body
  defp stringify_body(body), do: Jason.encode!(body)
end
