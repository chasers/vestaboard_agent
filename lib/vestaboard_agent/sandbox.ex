defmodule VestaboardAgent.Sandbox do
  @moduledoc """
  Behaviour for sandboxed script execution.

  Implement this to plug in a different scripting runtime (Lua, Wasm, etc.)
  without changing the rest of the system. The active sandbox is configured in
  `config/runtime.exs`:

      config :vestaboard_agent, :sandbox, VestaboardAgent.Sandbox.Lua

  Defaults to `VestaboardAgent.Sandbox.Lua` when not configured.
  """

  @doc """
  Execute `script` with the given `context` and return the board message string.
  """
  @callback run(script :: String.t(), context :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Run a script using the configured sandbox backend.
  """
  @spec run(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def run(script, context \\ %{}) do
    backend().run(script, context)
  end

  @spec backend() :: module()
  def backend do
    Application.get_env(:vestaboard_agent, :sandbox, VestaboardAgent.Sandbox.Lua)
  end
end
