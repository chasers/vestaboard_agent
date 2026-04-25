defmodule VestaboardAgent.Formatter do
  @moduledoc """
  Uses the LLM to reformat a raw text message and choose a border color for the
  Vestaboard display.

  The LLM is asked to return a JSON object:
      {"text": "...", "border_color": "blue"}

  `border_color` must be one of: red, orange, yellow, green, blue, violet, white.

  On any error (missing API key, parse failure, network error) the original text
  is returned unchanged with no border options — the board still renders.

  Pass `history:` in opts (list of `%{prompt, text, render_opts}` maps, newest
  first) to give the LLM context for follow-up prompts like "make it bigger".
  """

  alias VestaboardAgent.Clients.Anthropic, as: LLM
  alias VestaboardAgent.Renderer

  @valid_colors Map.keys(Renderer.color_codes())

  @doc """
  Format `text` for the Vestaboard using the LLM.

  Returns `{:ok, formatted_text, render_opts}` where `render_opts` may include
  `border: color_name`. On LLM failure falls back to `{:ok, text, []}`.
  Pass `llm_opts:` in `opts` to inject a test stub.
  Pass `history:` in `opts` (list of prior board state maps) for follow-up support.
  """
  @spec format(String.t(), keyword()) :: {:ok, String.t(), keyword()}
  def format(text, opts \\ []) do
    llm_opts = Keyword.get(opts, :llm_opts, [])
    history = Keyword.get(opts, :history, [])

    case LLM.complete(format_prompt(text, history), llm_opts) do
      {:ok, raw} ->
        raw
        |> strip_json_fences()
        |> Jason.decode()
        |> case do
          {:ok, %{"text" => t, "border_color" => c}} when c in @valid_colors ->
            {:ok, t, [border: c]}

          {:ok, %{"text" => t}} ->
            {:ok, t, []}

          _ ->
            {:ok, text, []}
        end

      {:error, _} ->
        {:ok, text, []}
    end
  end

  defp strip_json_fences(raw) do
    trimmed = String.trim(raw)

    case Regex.run(~r/^```(?:json)?\n(.*?)\n?```$/s, trimmed) do
      [_, code] -> String.trim(code)
      nil -> trimmed
    end
  end

  defp format_prompt(text, []) do
    """
    You are formatting a message for a Vestaboard LED display (6 rows × 22 columns).

    Input message:
    #{text}

    Reformat the message so it looks great on the board:
    - Keep each line at most 22 characters
    - At most 6 lines total (4 lines if you want a colored border — leave room!)
    - Use ALL CAPS (the board only renders uppercase)
    - Add spacing or line breaks to make it visually balanced
    - Choose a border color that fits the mood: red, orange, yellow, green, blue, violet, or white

    Return ONLY a JSON object with no explanation:
    {"text": "<formatted message>", "border_color": "<color>"}
    """
  end

  defp format_prompt(text, history) do
    history_section =
      history
      |> Enum.with_index(1)
      |> Enum.map(fn {%{prompt: p, text: t, render_opts: r}, i} ->
        border = Keyword.get(r, :border, "none")

        "#{i}. Prompt: \"#{p}\" → Displayed: \"#{String.replace(t, "\n", "↵")}\" (border: #{border})"
      end)
      |> Enum.join("\n")

    """
    You are formatting a message for a Vestaboard LED display (6 rows × 22 columns).

    Recent board history (most recent first):
    #{history_section}

    If the input message is a follow-up instruction (e.g. "make it bigger",
    "change the border to red", "use all caps"), apply it to the most recent
    board state above. Otherwise treat it as a fresh message.

    Input message:
    #{text}

    Reformat the message so it looks great on the board:
    - Keep each line at most 22 characters
    - At most 6 lines total (4 lines if you want a colored border — leave room!)
    - Use ALL CAPS (the board only renders uppercase)
    - Add spacing or line breaks to make it visually balanced
    - Choose a border color that fits the mood: red, orange, yellow, green, blue, violet, or white

    Return ONLY a JSON object with no explanation:
    {"text": "<formatted message>", "border_color": "<color>"}
    """
  end
end
