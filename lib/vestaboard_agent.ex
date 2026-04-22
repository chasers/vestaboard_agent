defmodule VestaboardAgent do
  @moduledoc """
  Top-level convenience API for the Vestaboard agent.

  ## Quick start

      VestaboardAgent.display("happy Tuesday")

  This formats the message with the LLM (picking nice layout + border color),
  renders it, and sends it to the board.
  """

  alias VestaboardAgent.{Dispatcher, Formatter}

  @doc """
  Format `prompt` with the LLM and send it to the Vestaboard.

  The LLM rewrites the text for the 6×22 grid and chooses a border color.
  On LLM failure the raw prompt is sent without decoration.

  Returns `{:ok, map()}` on success or `{:error, reason}` on board write failure.
  """
  @spec display(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def display(prompt, opts \\ []) do
    {:ok, text, render_opts} = Formatter.format(prompt, opts)
    Dispatcher.dispatch(text, render_opts)
  end
end
