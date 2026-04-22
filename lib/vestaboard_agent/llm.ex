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
  Send a single prompt to the LLM and return the response text.

  Returns `{:ok, text}` or `{:error, reason}`.
  Pass `plug:` in opts to inject a test stub.
  """
  @spec complete(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(prompt, opts \\ []) do
    with {:ok, api_key} <- api_key() do
      call_api(api_key, model(), prompt, opts)
    end
  end

  @doc """
  Ask the LLM to write a Lua tool script for `task_description`.

  Returns `{:ok, script}` or `{:error, reason}`.
  Pass `plug:` in opts to inject a test stub (same pattern as the HTTP client).
  """
  @spec generate_tool_script(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_tool_script(task_description, opts \\ []) do
    with {:ok, script} <- complete(script_prompt(task_description), opts) do
      {:ok, strip_fences(script)}
    end
  end

  @doc """
  Parse a natural-language scheduling request into a tool name and interval.

  `tool_names` is a list of available tool name strings. Returns
  `{:ok, %{tool: String.t(), interval_seconds: pos_integer()}}` or `{:error, reason}`.
  """
  @spec parse_schedule(String.t(), [String.t()], keyword()) ::
          {:ok, %{tool: String.t(), interval_seconds: pos_integer()}} | {:error, term()}
  def parse_schedule(prompt, tool_names, opts \\ []) do
    with {:ok, raw} <- complete(schedule_prompt(prompt, tool_names), opts),
         {:ok, map} <- Jason.decode(strip_fences(raw)),
         %{"tool" => tool, "interval_seconds" => secs}
         when is_binary(tool) and is_integer(secs) and secs > 0 <- map do
      {:ok, %{tool: tool, interval_seconds: secs}}
    else
      %{} -> {:error, :invalid_schedule_response}
      {:error, _} = err -> err
    end
  end

  @doc """
  Ask the LLM which registered agent should handle `prompt`.

  `agents_meta` is a list of `{name_string, keywords_list}` tuples built from
  the registered agents. Returns `{:ok, agent_name_string}` or `{:error, reason}`.
  The returned name is always downcased and trimmed.

  Pass `history:` in opts (list of `%{prompt, text, render_opts}` maps, newest
  first) to help the LLM resolve follow-ups like "do that again".
  """
  @spec route_agent(String.t(), [{String.t(), [String.t()]}], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def route_agent(prompt, agents_meta, opts \\ []) do
    history = Keyword.get(opts, :history, [])

    with {:ok, name} <- complete(routing_prompt(prompt, agents_meta, history), opts) do
      {:ok, name |> String.trim() |> String.downcase()}
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
        script =
          body
          |> get_in(["content", Access.at(0), "text"])
          |> strip_fences()

        {:ok, script}

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

  defp strip_fences(text) do
    trimmed = String.trim(text)

    case Regex.run(~r/^```(?:\w+)?\n(.*?)\n?```$/s, trimmed) do
      [_, code] -> String.trim(code)
      nil -> trimmed
    end
  end

  defp routing_prompt(prompt, agents_meta, history) do
    agent_list =
      agents_meta
      |> Enum.map(fn
        {name, []} -> "- #{name}"
        {name, kws} -> "- #{name}: #{Enum.join(kws, ", ")}"
      end)
      |> Enum.join("\n")

    history_section =
      if history == [] do
        ""
      else
        lines =
          history
          |> Enum.with_index(1)
          |> Enum.map(fn {%{prompt: p}, i} -> "#{i}. \"#{p}\"" end)
          |> Enum.join("\n")

        "\nRecent prompts (most recent first):\n#{lines}\n"
      end

    """
    Route this user request to the correct handler for a Vestaboard display.
    #{history_section}
    User prompt: "#{prompt}"

    Available handlers:
    #{agent_list}

    Routing rules:
    - If the prompt is a follow-up (e.g. "do that again", "same but different color"),
      route to the same handler as the most recent prompt above.
    - If the prompt asks a knowledge or conversational question (e.g. "Who is God?",
      "What is the meaning of life?", "Tell me about Einstein"), reply with "conversational".
    - If the prompt needs live data or computation not covered by a specific handler
      (e.g. "show BTC price", "display a countdown to Friday"), reply with "dynamic".

    Reply with ONLY the handler name that best matches.
    """
  end

  defp script_prompt(task_description) do
    """
    You are generating a Lua script for a Vestaboard LED display (6 rows × 22 columns).

    Script contract:
    - Receives a global `context` table:
        context.now  — ISO-8601 UTC timestamp string (e.g. "2024-06-15T12:00:00Z")
    - Must return a single string; newlines split it into rows
    - Each line should be 22 characters or fewer
    - Total content should fit within 6 rows
    - No require(), no file I/O, no os.*

    Available built-in functions (always present, no require needed):

      vestaboard.http_get(url)
        Makes an HTTP GET request.
        Returns: body (string), status (integer)
        Example:
          local body, status = vestaboard.http_get("https://api.example.com/data")
          if status ~= 200 then return "unavailable" end

      vestaboard.http_post(url, body)
        Makes an HTTP POST request with a string body.
        Returns: body (string), status (integer)

      vestaboard.json_decode(str)
        Parses a JSON string into a Lua table.
        Returns: table (or nil on parse error)
        Example:
          local data = vestaboard.json_decode(body)
          return data.temperature .. "F"

      vestaboard.truncate(str, len)
        Truncates a string to at most len characters.

      vestaboard.log(msg)
        Logs a debug message (no effect on display).

    Task: #{task_description}

    Return ONLY the Lua script. No explanation, no markdown fences.
    """
  end

  defp schedule_prompt(prompt, tool_names) do
    """
    Parse this scheduling request for a Vestaboard display.

    User request: "#{prompt}"

    Available tools: #{Enum.join(tool_names, ", ")}

    Respond with a JSON object only, no explanation, no markdown:
    {"tool": "<tool name from the list>", "interval_seconds": <positive integer>}

    Examples:
    "show clock every 15 seconds" -> {"tool": "clock", "interval_seconds": 15}
    "show weather every 5 minutes" -> {"tool": "weather", "interval_seconds": 300}
    "display a quote every hour" -> {"tool": "quote", "interval_seconds": 3600}

    If no tool matches, pick the closest one.
    """
  end
end
