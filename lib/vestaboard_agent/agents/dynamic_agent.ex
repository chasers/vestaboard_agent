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

  @default_retry_budget_ms 30_000

  @impl true
  def handle(prompt, context) do
    tool_name = derive_tool_name(prompt)
    llm_opts = Map.get(context, :llm_opts, [])

    case ToolRegistry.get(tool_name) do
      {:ok, _} ->
        result = ToolRegistry.run(tool_name, context)
        if good_output?(prompt, result, llm_opts), do: result, else: generate_and_run(tool_name, prompt, context, llm_opts)

      {:error, :not_found} ->
        generate_and_run(tool_name, prompt, context, llm_opts)
    end
  end

  # --- Private ---

  defp generate_and_run(tool_name, prompt, context, llm_opts) do
    budget = Map.get(context, :retry_budget_ms, @default_retry_budget_ms)
    deadline = System.monotonic_time(:millisecond) + budget

    case LLM.generate_tool_script(prompt, llm_opts) do
      {:ok, script} -> retry_loop(tool_name, prompt, context, llm_opts, script, deadline)
      {:error, _} = err -> err
    end
  end

  # Run the script; if the result is bad and time remains, ask the LLM to rewrite.
  defp retry_loop(tool_name, prompt, context, llm_opts, script, deadline) do
    :ok = ToolRegistry.register_script(tool_name, script)
    result = ToolRegistry.run(tool_name, context)

    if deadline_passed?(deadline) or good_output?(prompt, result, llm_opts) do
      result
    else
      case LLM.regenerate_tool_script(prompt, script, result, llm_opts) do
        {:ok, new_script} -> retry_loop(tool_name, prompt, context, llm_opts, new_script, deadline)
        {:error, _} -> result
      end
    end
  end

  defp deadline_passed?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp good_output?(_prompt, {:error, _}, _llm_opts), do: false
  defp good_output?(_prompt, {:ok, text}, _llm_opts) when byte_size(text) == 0, do: false

  defp good_output?(prompt, {:ok, text}, llm_opts) do
    case LLM.evaluate_output(prompt, text, llm_opts) do
      {:ok, :good} -> true
      {:ok, :bad} -> false
      {:error, _} -> true  # can't evaluate — accept the output as-is
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
