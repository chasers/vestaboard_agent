import Config

base_url =
  case System.get_env("VESTABOARD_BASE_URL", "vestaboard.local") do
    "http://" <> _ = url -> url
    host -> "http://#{host}:7000"
  end

config :vestaboard_agent, :client,
  backend: VestaboardAgent.Client.Local,
  api_key: System.get_env("VESTABOARD_LOCAL_API_KEY"),
  base_url: base_url

config :vestaboard_agent, :weather,
  latitude: 33.5095,
  longitude: -112.0493
