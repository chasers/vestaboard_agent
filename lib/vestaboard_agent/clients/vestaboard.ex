defmodule VestaboardAgent.Clients.Vestaboard do
  @moduledoc """
  Behaviour and dispatch module for the Vestaboard API.

  Supports two backends:

    * `VestaboardAgent.Clients.Vestaboard.Cloud` — Vestaboard cloud API
    * `VestaboardAgent.Clients.Vestaboard.Local` — local network API (direct board access)

  Configure the active backend in `config/runtime.exs`:

      config :vestaboard_agent, :client,
        backend: VestaboardAgent.Clients.Vestaboard.Cloud,
        token: System.get_env("VESTABOARD_TOKEN")

      # or for local:
      config :vestaboard_agent, :client,
        backend: VestaboardAgent.Clients.Vestaboard.Local,
        api_key: System.get_env("VESTABOARD_LOCAL_API_KEY"),
        base_url: "http://vestaboard.local:7000"

  Both backends share the callbacks below. Cloud-only features (text messages,
  transitions) live directly on `VestaboardAgent.Clients.Vestaboard.Cloud`.
  """

  @doc "Read the current message from the board. Returns a 6×22 character code grid."
  @callback read() :: {:ok, [[integer()]]} | {:error, term()}

  @doc "Write a 6×22 character code grid to the board."
  @callback write_characters([[integer()]]) :: {:ok, map()} | {:error, term()}

  @doc "Read the current board state via the configured backend."
  @spec read() :: {:ok, [[integer()]]} | {:error, term()}
  def read, do: backend().read()

  @doc "Write a character grid via the configured backend."
  @spec write_characters([[integer()]]) :: {:ok, map()} | {:error, term()}
  def write_characters(chars), do: backend().write_characters(chars)

  @doc "Return the configured backend module."
  @spec backend() :: module()
  def backend do
    config(:backend, VestaboardAgent.Clients.Vestaboard.Cloud)
  end

  @doc false
  @spec config(atom(), term()) :: term()
  def config(key, default \\ nil) do
    :vestaboard_agent
    |> Application.get_env(:client, [])
    |> Keyword.get(key, default)
  end
end
