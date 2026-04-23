defmodule VestaboardAgent.Agents.DisplayAgent do
  @moduledoc """
  Displays literal text on the board.

  Triggered by prompts starting with "display". Strips the leading keyword
  and returns the rest of the prompt as-is for formatting and rendering.
  """

  @behaviour VestaboardAgent.Agent

  @impl true
  def name, do: "display"

  @impl true
  def keywords, do: ["display"]

  @impl true
  def handle(prompt, _context) do
    text =
      prompt
      |> String.trim()
      |> String.replace(~r/^display\s+/i, "")

    {:ok, text}
  end
end
