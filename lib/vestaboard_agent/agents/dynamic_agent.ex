defmodule VestaboardAgent.Agents.DynamicAgent do
  @moduledoc """
  Falls back to LLM-generated Lua scripts when no registered tool matches.

  ## Flow

  1. Derive a stable tool name from the prompt (first three words, snake_case).
  2. Check `ToolRegistry` — if the tool already exists, run and dispatch it.
  3. If missing, call `LLM.generate_tool_script/2` to write a new Lua script.
  4. Register the script in `ToolRegistry` (persisted to disk for future runs).
  5. Run and dispatch the result.

  Pass `llm_opts:` in context to inject a test stub:

      DynamicAgent.handle("show date", %{llm_opts: [plug: {Req.Test, MyTest}]})
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.{LLM, ToolRegistry}

  @impl true
  def name, do: "dynamic"

  @impl true
  def keywords, do: []

  @impl true
  def handle(prompt, context) do
    tool_name = derive_tool_name(prompt)

    case ToolRegistry.get(tool_name) do
      {:ok, _} -> ToolRegistry.run(tool_name, context)
      {:error, :not_found} -> generate_and_run(tool_name, prompt, context)
    end
  end

  # --- Private ---

  defp generate_and_run(tool_name, prompt, context) do
    llm_opts = Map.get(context, :llm_opts, [])

    with {:ok, script} <- LLM.generate_tool_script(prompt, llm_opts),
         :ok <- ToolRegistry.register_script(tool_name, script) do
      ToolRegistry.run(tool_name, context)
    end
  end

  @doc "Derive a stable atom tool name from the first three words of a prompt."
  def derive_tool_name(prompt) do
    name =
      prompt
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take(3)
      |> Enum.join("_")

    String.to_atom(name)
  end
end
