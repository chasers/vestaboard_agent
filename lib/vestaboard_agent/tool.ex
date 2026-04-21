defmodule VestaboardAgent.Tool do
  @moduledoc """
  Behaviour for all VestaboardAgent tools.

  A tool takes a context map and returns a board-ready string.
  Tools backed by Lua scripts use `VestaboardAgent.LuaTool.run/2` internally.
  """

  @doc "Human-readable name used in logs and the tool registry."
  @callback name() :: String.t()

  @doc "Produce a board message from the given context."
  @callback run(context :: map()) :: {:ok, String.t()} | {:error, term()}
end
