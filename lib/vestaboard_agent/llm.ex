defmodule VestaboardAgent.LLM do
  @moduledoc """
  Generates Lua tool scripts via the Anthropic Messages API.

  Reads `ANTHROPIC_API_KEY` from the environment by default.
  The model and key can be overridden via config:

      config :vestaboard_agent, :llm,
        api_key: "sk-ant-...",
        model: "claude-haiku-4-5-20251001"

  ## Generated script contract

  The prompt instructs the model to write a Lua script that:
  - Receives a `context` table (`context.now` is an ISO-8601 timestamp)
  - Returns a single string to be rendered on the board
  - Keeps each line under 22 characters (the board is 22 columns wide)
  - Uses no HTTP or I/O — only Lua standard library computation
  """

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @default_model "claude-haiku-4-5-20251001"

  @doc """
  Ask the LLM to write a Lua tool script for `task_description`.

  Returns `{:ok, script}` or `{:error, reason}`.
  Pass `plug:` in opts to inject a test stub (same pattern as the HTTP client).
  """
  @spec generate_tool_script(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_tool_script(task_description, opts \\ []) do
    with {:ok, api_key} <- api_key() do
      call_api(api_key, model(), script_prompt(task_description), opts)
    end
  end

  # --- Private ---

  defp api_key do
    cfg = Application.get_env(:vestaboard_agent, :llm, [])

    case cfg[:api_key] || System.get_env("ANTHROPIC_API_KEY") do
      nil -> {:error, :missing_api_key}
      key -> {:ok, key}
    end
  end

  defp model do
    cfg = Application.get_env(:vestaboard_agent, :llm, [])
    cfg[:model] || @default_model
  end

  defp call_api(api_key, model, prompt, opts) do
    req = build_req(opts)

    case Req.post(req,
           url: @anthropic_url,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           json: %{
             model: model,
             max_tokens: 1024,
             messages: [%{role: "user", content: prompt}]
           }
         ) do
      {:ok, %{status: 200, body: body}} ->
        script = get_in(body, ["content", Access.at(0), "text"])
        {:ok, String.trim(script)}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_req(opts) do
    base = Req.new(retry: false)

    case opts[:plug] do
      nil -> base
      plug -> Req.merge(base, plug: plug)
    end
  end

  defp script_prompt(task_description) do
    """
    You are generating a Lua script for a Vestaboard LED display (6 rows × 22 columns).

    Script contract:
    - Receives a global `context` table with context.now (ISO-8601 UTC timestamp string)
    - Must return a single string; newlines split it into rows
    - Each line should be 22 characters or fewer
    - Total content should fit within 6 rows
    - No HTTP calls, file I/O, or require() — only Lua standard library computation

    Task: #{task_description}

    Return ONLY the Lua script. No explanation, no markdown fences.
    """
  end
end
