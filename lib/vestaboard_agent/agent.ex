defmodule VestaboardAgent.Agent do
  @moduledoc """
  Behaviour for all VestaboardAgent agents.

  An agent is a user-facing interaction started by a prompt. It selects tools,
  drives the board, and signals when it is done or still running.
  """

  @doc "Human-readable name used in logs and the registry."
  @callback name() :: String.t()

  @doc "Keywords that trigger this agent when found in a user prompt."
  @callback keywords() :: [String.t()]

  @doc "One-line description used in the LLM routing prompt."
  @callback description() :: String.t()

  @doc """
  Handle a user prompt.

  Returns:
    * `{:ok, text}` — agent produced content; the caller formats and dispatches it
    * `{:ok, :done}` — agent already wrote to the board (scheduled agents, etc.)
    * `{:ok, :running, state}` — long-running; supervisor keeps it alive
    * `{:error, reason}` — something went wrong
  """
  @callback handle(prompt :: String.t(), context :: map()) ::
              {:ok, String.t()}
              | {:ok, :done}
              | {:ok, :running, state :: term()}
              | {:error, term()}
end
