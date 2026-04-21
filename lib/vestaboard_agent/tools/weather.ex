defmodule VestaboardAgent.Tools.Weather do
  @moduledoc """
  Fetches current weather from Open-Meteo (no API key required).

  Reads latitude/longitude from config:

      config :vestaboard_agent, :weather,
        latitude: 37.7749,
        longitude: -122.4194

  Both values can also be passed via context keys `:latitude` / `:longitude`.
  """

  @behaviour VestaboardAgent.Tool

  @base_url "https://api.open-meteo.com/v1/forecast"

  @impl true
  def name, do: "weather"

  @impl true
  def run(context \\ %{}) do
    with {:ok, lat, lon} <- location(context),
         {:ok, data} <- fetch(lat, lon, context) do
      {:ok, format(data)}
    end
  end

  defp location(context) do
    cfg = Application.get_env(:vestaboard_agent, :weather, [])
    lat = Map.get(context, :latitude) || cfg[:latitude]
    lon = Map.get(context, :longitude) || cfg[:longitude]

    if lat && lon do
      {:ok, lat, lon}
    else
      {:error, :location_required}
    end
  end

  defp fetch(lat, lon, context) do
    req = build_req(context)

    case Req.get(req,
           url: @base_url,
           params: [
             latitude: lat,
             longitude: lon,
             current: "temperature_2m,apparent_temperature,weathercode,windspeed_10m",
             temperature_unit: "fahrenheit",
             windspeed_unit: "mph",
             timezone: "auto"
           ]
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_req(context) do
    base = Req.new(retry: false)

    case Map.get(context, :plug) do
      nil -> base
      plug -> Req.merge(base, plug: plug)
    end
  end

  defp format(%{"current" => current}) do
    temp = round(current["temperature_2m"])
    feels = round(current["apparent_temperature"])
    wind = round(current["windspeed_10m"])
    condition = wmo_description(current["weathercode"])

    "#{temp}F FEELS #{feels}F\n#{condition}\nWIND #{wind} MPH"
  end

  defp wmo_description(code) when code in [0] do
    "CLEAR SKY"
  end

  defp wmo_description(code) when code in [1] do
    "MAINLY CLEAR"
  end

  defp wmo_description(code) when code in [2] do
    "PARTLY CLOUDY"
  end

  defp wmo_description(code) when code in [3] do
    "OVERCAST"
  end

  defp wmo_description(code) when code in [45, 48] do
    "FOGGY"
  end

  defp wmo_description(code) when code in [51, 53, 55] do
    "DRIZZLE"
  end

  defp wmo_description(code) when code in [61, 63, 65] do
    "RAIN"
  end

  defp wmo_description(code) when code in [71, 73, 75, 77] do
    "SNOW"
  end

  defp wmo_description(code) when code in [80, 81, 82] do
    "RAIN SHOWERS"
  end

  defp wmo_description(code) when code in [85, 86] do
    "SNOW SHOWERS"
  end

  defp wmo_description(code) when code in [95] do
    "THUNDERSTORM"
  end

  defp wmo_description(code) when code in [96, 99] do
    "THUNDERSTORM W/ HAIL"
  end

  defp wmo_description(_), do: "UNKNOWN"
end
