defmodule VestaboardAgent.Client.Local do
  @moduledoc """
  Vestaboard local network API client.

  Communicates directly with a board on the local network.
  Auth header: `X-Vestaboard-Local-Api-Key`

  Configure via:

      config :vestaboard_agent, :client,
        backend: VestaboardAgent.Client.Local,
        api_key: System.get_env("VESTABOARD_LOCAL_API_KEY"),
        base_url: "http://vestaboard.local:7000"  # or use the board's IP

  ## One-time enablement

  Before using the local API, you must enable it once with an enablement token
  obtained from Vestaboard:

      VestaboardAgent.Client.Local.enable("your-enablement-token")

  This returns an API key which you then store in config.
  """

  @behaviour VestaboardAgent.Client

  @default_base_url "http://vestaboard.local:7000"
  @path "/local-api/message"

  @impl true
  def read do
    case Req.get(request(), url: @path) do
      {:ok, %{status: 200, body: body}} when is_list(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write_characters(chars) when is_list(chars) do
    case Req.post(request(), url: @path, json: chars) do
      {:ok, %{status: s, body: body}} when s in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  One-time enablement of the local API.

  Pass the enablement token from Vestaboard. On success returns `{:ok, api_key}`
  where `api_key` should be stored in config as `:api_key`.
  """
  @spec enable(String.t()) :: {:ok, String.t()} | {:error, term()}
  def enable(enablement_token) when is_binary(enablement_token) do
    req =
      Req.new(
        base_url: base_url(),
        headers: [{"x-vestaboard-local-api-enablement-token", enablement_token}]
      )
      |> merge_test_plug()

    case Req.post(req, url: "/local-api/enablement") do
      {:ok, %{status: s, body: %{"apiKey" => key}}} when s in 200..299 -> {:ok, key}
      {:ok, %{status: s, body: %{"api_key" => key}}} when s in 200..299 -> {:ok, key}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request do
    Req.new(base_url: base_url(), headers: [{"x-vestaboard-local-api-key", api_key()}])
    |> merge_test_plug()
  end

  defp merge_test_plug(req) do
    case VestaboardAgent.Client.config(:plug) do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end

  defp base_url, do: VestaboardAgent.Client.config(:base_url, @default_base_url)
  defp api_key, do: VestaboardAgent.Client.config(:api_key, "")
end
