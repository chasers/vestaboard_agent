defmodule VestaboardAgent.Clients.Vestaboard.Cloud do
  @moduledoc """
  Vestaboard cloud API client.

  Base URL: `https://cloud.vestaboard.com`
  Auth header: `X-Vestaboard-Token`

  Configure via:

      config :vestaboard_agent, :client,
        backend: VestaboardAgent.Clients.Vestaboard.Cloud,
        token: System.get_env("VESTABOARD_TOKEN")
  """

  @behaviour VestaboardAgent.Clients.Vestaboard

  @base_url "https://cloud.vestaboard.com"
  @vbml_url "https://vbml.vestaboard.com"

  @impl true
  def read do
    case Req.get(request(), url: "/") do
      {:ok, %{status: 200, body: body}} -> {:ok, extract_characters(body)}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def write_characters(chars) when is_list(chars) do
    case Req.post(request(), url: "/", json: %{characters: chars}) do
      {:ok, %{status: s, body: body}} when s in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Write a plain-text message. The cloud API handles encoding."
  @spec write_text(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write_text(text, opts \\ []) when is_binary(text) do
    body = if Keyword.get(opts, :forced, false), do: %{text: text, forced: true}, else: %{text: text}

    case Req.post(request(), url: "/", json: body) do
      {:ok, %{status: s, body: resp}} when s in 200..299 -> {:ok, resp}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetch the current transition settings."
  @spec get_transition() :: {:ok, map()} | {:error, term()}
  def get_transition do
    case Req.get(request(), url: "/transition") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Set the board transition.

  `type` must be one of: `"classic"`, `"wave"`, `"drift"`, `"curtain"`.
  `speed` must be one of: `"gentle"`, `"fast"`.
  """
  @spec set_transition(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_transition(type, speed)
      when type in ["classic", "wave", "drift", "curtain"] and speed in ["gentle", "fast"] do
    case Req.put(request(), url: "/transition", json: %{transition: type, transitionSpeed: speed}) do
      {:ok, %{status: s, body: body}} when s in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Convert a text string to a Vestaboard character code grid using the VBML API."
  @spec format_text(String.t()) :: {:ok, [[integer()]]} | {:error, term()}
  def format_text(text) when is_binary(text) do
    vbml_req = Req.new(base_url: @vbml_url) |> merge_test_plug()

    case Req.post(vbml_req, url: "/format", json: %{message: text}) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request do
    Req.new(base_url: @base_url, headers: [{"x-vestaboard-token", token()}])
    |> merge_test_plug()
  end

  defp merge_test_plug(req) do
    case VestaboardAgent.Clients.Vestaboard.config(:plug) do
      nil -> req
      plug -> Req.merge(req, plug: plug)
    end
  end

  defp token do
    VestaboardAgent.Clients.Vestaboard.config(:token, "")
  end

  defp extract_characters(%{"currentMessage" => %{"text" => chars}}), do: chars
  defp extract_characters(body) when is_list(body), do: body
  defp extract_characters(body), do: body
end
