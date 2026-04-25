defmodule VestaboardAgent.Agents.WeatherAgent do
  @moduledoc """
  Displays current weather conditions on the board.

  Triggered by prompts containing: weather, forecast, temperature, temp,
  outside, how hot, how cold.
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.Tools.Weather

  @impl true
  def name, do: "weather"

  @impl true
  def keywords,
    do: ["weather", "forecast", "temperature", "temp", "outside", "how hot", "how cold"]

  @impl true
  def handle(_prompt, context) do
    Weather.run(context)
  end
end
