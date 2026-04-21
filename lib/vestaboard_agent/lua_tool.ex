defmodule VestaboardAgent.LuaTool do
  @moduledoc """
  Executes a script as a VestaboardAgent tool using the configured sandbox.

  An agent can write a script at runtime (e.g. via an LLM) and run it as a
  first-class tool without recompiling the project.

  ## Script contract

  Scripts receive a `context` table/object with:
    * `context.now`      — ISO-8601 UTC timestamp string
    * `context.board_id` — board identifier string

  Scripts must return a single string — the message to display.

  ## Example

      script = \"\"\"
      function run(context)
        return "Hello at " .. context.now
      end

      return run(context)
      \"\"\"

      {:ok, message} = VestaboardAgent.LuaTool.run(script, context)
  """

  @doc """
  Run `script` via the configured `VestaboardAgent.Sandbox` backend.
  """
  @spec run(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  defdelegate run(script, context \\ %{}), to: VestaboardAgent.Sandbox
end
