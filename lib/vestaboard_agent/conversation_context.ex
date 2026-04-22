defmodule VestaboardAgent.ConversationContext do
  @moduledoc """
  Stores the last N board states so the LLM can understand follow-up prompts.

  Each entry records what the user asked for, what text was displayed, and the
  render options (border color, alignment) that were used. The history is passed
  to the Formatter and router so prompts like "make it bigger" or "do that again"
  resolve correctly.
  """

  use GenServer

  @max_entries 5

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Prepend a new board-state entry. Trims the list to the last #{@max_entries} entries."
  @spec push(String.t(), String.t(), keyword()) :: :ok
  def push(prompt, formatted_text, render_opts) do
    GenServer.cast(__MODULE__, {:push, prompt, formatted_text, render_opts})
  end

  @doc "Return stored entries, newest first."
  @spec history() :: [%{prompt: String.t(), text: String.t(), render_opts: keyword()}]
  def history do
    GenServer.call(__MODULE__, :history)
  end

  @doc "Clear all history."
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # --- Server callbacks ---

  @impl true
  def init(:ok), do: {:ok, []}

  @impl true
  def handle_cast({:push, prompt, text, render_opts}, entries) do
    entry = %{prompt: prompt, text: text, render_opts: render_opts}
    {:noreply, Enum.take([entry | entries], @max_entries)}
  end

  @impl true
  def handle_call(:history, _from, entries), do: {:reply, entries, entries}
  def handle_call(:clear, _from, _entries), do: {:reply, :ok, []}
end
