defmodule VestaboardAgent.Dispatcher do
  @moduledoc """
  Sends a message to the Vestaboard.

  Accepts either a pre-rendered 6×22 character grid or a plain text string
  (which is passed through `VestaboardAgent.Renderer` first).
  """

  alias VestaboardAgent.{Client, Renderer}

  @doc """
  Dispatch a message to the board.

  Accepts:
    * a 6×22 `[[integer()]]` grid — sent directly
    * a `String.t()` — rendered then sent; accepts same opts as `Renderer.render/2`
  """
  @spec dispatch([[integer()]] | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def dispatch(message, opts \\ [])

  def dispatch(grid, _opts) when is_list(grid) do
    Client.write_characters(grid)
  end

  def dispatch(text, opts) when is_binary(text) do
    with {:ok, grid} <- Renderer.render(text, opts) do
      Client.write_characters(grid)
    end
  end
end
