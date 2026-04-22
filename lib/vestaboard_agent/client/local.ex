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

  require Logger

  @behaviour VestaboardAgent.Client

  @default_base_url "http://vestaboard.local:7000"
  @path "/local-api/message"
  @max_retries 3
  @base_backoff_ms 1_000

  @impl true
  def read do
    case Req.get(request(), url: @path) do
      {:ok, %{status: 200, body: body}} -> parse_read_body(body)
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_read_body(body) when is_list(body), do: {:ok, body}
  defp parse_read_body(%{"message" => grid}) when is_list(grid), do: {:ok, grid}
  defp parse_read_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, grid} when is_list(grid) -> {:ok, grid}
      {:ok, %{"message" => grid}} when is_list(grid) -> {:ok, grid}
      _ -> {:ok, body}
    end
  end
  defp parse_read_body(body), do: {:ok, body}

  @impl true
  def write_characters(chars) when is_list(chars) do
    do_write(chars, 0)
  end

  defp do_write(chars, attempt) do
    case Req.post(request(), url: @path, json: chars) do
      {:ok, %{status: s, body: body}} when s in 200..299 ->
        {:ok, body}

      {:ok, %{status: 429}} when attempt < @max_retries ->
        wait = backoff_ms(attempt)
        Logger.warning("Vestaboard 429 rate-limited — retry #{attempt + 1}/#{@max_retries} in #{wait}ms")
        Process.sleep(wait)
        do_write(chars, attempt + 1)

      {:ok, %{status: 429}} ->
        Logger.error("Vestaboard 429 rate-limited — all #{@max_retries} retries exhausted")
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp backoff_ms(attempt) do
    base = VestaboardAgent.Client.config(:backoff_base_ms, @base_backoff_ms)
    jitter = :rand.uniform(200) - 100
    (base * :math.pow(2, attempt)) |> round() |> Kernel.+(jitter) |> max(0)
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
