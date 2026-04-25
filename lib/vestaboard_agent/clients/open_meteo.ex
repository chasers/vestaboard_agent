defmodule VestaboardAgent.Clients.OpenMeteo do
  @moduledoc """
  HTTP client for the Open-Meteo weather API (no API key required).

  Pass `plug:` in opts to inject a test stub:

      OpenMeteo.fetch(lat, lon, plug: {Req.Test, MyTest})
  """

  @base_url "https://api.open-meteo.com/v1/forecast"

  @spec fetch(float(), float(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch(lat, lon, opts \\ []) do
    req = build_req(opts)

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

  defp build_req(opts) do
    base = Req.new(retry: false)

    case opts[:plug] do
      nil -> base
      plug -> Req.merge(base, plug: plug)
    end
  end
end
