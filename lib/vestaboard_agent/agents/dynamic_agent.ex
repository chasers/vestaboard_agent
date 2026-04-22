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

  @max_attempts 5

  @impl true
  def handle(prompt, context) do
    tool_name = derive_tool_name(prompt)
    llm_opts = Map.get(context, :llm_opts, [])

    case ToolRegistry.get(tool_name) do
      {:ok, _} ->
        result = ToolRegistry.run(tool_name, context)
        if good?(result), do: result, else: generate_and_run(tool_name, prompt, context, llm_opts)

      {:error, :not_found} ->
        generate_and_run(tool_name, prompt, context, llm_opts)
    end
  end

  # --- Private ---

  defp generate_and_run(tool_name, prompt, context, llm_opts) do
    case LLM.generate_tool_script(prompt, llm_opts) do
      {:ok, script} -> retry_loop(tool_name, prompt, context, llm_opts, script, @max_attempts - 1)
      {:error, _} = err -> err
    end
  end

  # Run the script; if the result is bad and attempts remain, ask the LLM to rewrite.
  defp retry_loop(tool_name, prompt, context, llm_opts, script, remaining) when remaining > 0 do
    :ok = ToolRegistry.register_script(tool_name, script)
    result = ToolRegistry.run(tool_name, context)

    if good?(result) do
      result
    else
      case LLM.regenerate_tool_script(prompt, script, result, llm_opts) do
        {:ok, new_script} -> retry_loop(tool_name, prompt, context, llm_opts, new_script, remaining - 1)
        {:error, _} -> result
      end
    end
  end

  # No attempts remaining — run the current script and return whatever it produces.
  defp retry_loop(tool_name, _prompt, context, _llm_opts, script, _remaining) do
    :ok = ToolRegistry.register_script(tool_name, script)
    ToolRegistry.run(tool_name, context)
  end

  defp good?({:ok, text}) when is_binary(text), do: String.trim(text) != ""
  defp good?(_), do: false

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
