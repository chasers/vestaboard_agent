defmodule VestaboardAgent.LuaAPI do
  @moduledoc """
  Elixir bindings exposed to every Lua tool script.

  Functions defined here with `deflua` are callable from Lua.
  The module is loaded into a Lua state via `Lua.load_api/2`.

  ## Available Lua functions

    * `vestaboard.log(msg)` — write a string to Logger
    * `vestaboard.truncate(str, len)` — truncate a string to `len` characters
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
end
