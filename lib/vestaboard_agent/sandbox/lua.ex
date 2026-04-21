defmodule VestaboardAgent.Sandbox.Lua do
  @moduledoc """
  Lua sandbox backend via the `lua` / Luerl library.

  Scripts run inside a Luerl VM on the BEAM. External I/O is only possible
  through bindings explicitly added to `VestaboardAgent.LuaAPI`.
  """

  @behaviour VestaboardAgent.Sandbox

  alias VestaboardAgent.LuaAPI

  @impl true
  def run(script, context \\ %{}) when is_binary(script) do
    lua =
      Lua.new()
      |> Lua.load_api(LuaAPI)
      |> inject_context(context)

    case Lua.eval!(lua, script) do
      {[result | _], _state} when is_binary(result) -> {:ok, result}
      {[result | _], _state} -> {:ok, to_string(result)}
      {[], _state} -> {:error, :no_return_value}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp inject_context(lua, context) do
    now =
      case Map.get(context, :now) do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        other -> to_string(other || "")
      end

    board_id = to_string(Map.get(context, :board_id, ""))

    Lua.set!(lua, [:context], %{"now" => now, "board_id" => board_id})
  end
end
