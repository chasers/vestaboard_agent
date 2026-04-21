defmodule VestaboardAgent.Tools.Greeting do
  @moduledoc """
  Returns a time-appropriate greeting by running a Lua script.

  This is the canonical example of a Lua-backed tool: the logic lives in the
  Lua script, Elixir supplies the context, and the result is a display string.
  """

  @behaviour VestaboardAgent.Tool

  # Parses the hour out of the ISO-8601 `context.now` string and picks a greeting.
  @script """
  local hour_str = string.sub(context.now, 12, 13)
  local hour = tonumber(hour_str) or 12

  if hour < 12 then
    return "Good morning!"
  elseif hour < 18 then
    return "Good afternoon!"
  else
    return "Good evening!"
  end
  """

  @impl true
  def name, do: "greeting"

  @impl true
  def run(context \\ %{}) do
    VestaboardAgent.LuaTool.run(@script, context)
  end
end
