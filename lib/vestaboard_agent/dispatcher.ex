defmodule VestaboardAgent.Dispatcher do
  @moduledoc """
  Serializes all writes to the Vestaboard through a single GenServer process.

  All agents share one board; routing every write through this GenServer ensures
  they never interleave. Sync (`dispatch/2`, `dispatch_tool/2`) block the caller
  until the write completes. Async variants (`dispatch_async/2`,
  `dispatch_tool_async/2`) are fire-and-forget with a TTL: if the message is
  still waiting when its deadline passes, it is silently dropped so stale data
  never appears on the board.

  After each successful write, `last_board/0` returns the rendered grid and its
  decoded text so callers (e.g. `GET /board`) can inspect what is currently
  displayed without reading back from the hardware.
  """

  use GenServer

  alias VestaboardAgent.{Client, Renderer}

  @default_ttl_ms 30_000

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec dispatch([[integer()]] | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def dispatch(message, opts \\ []) do
    GenServer.call(__MODULE__, {:dispatch, message, opts})
  end

  @spec dispatch_async([[integer()]] | String.t(), keyword()) :: :ok
  def dispatch_async(message, opts \\ []) do
    {ttl, opts} = Keyword.pop(opts, :ttl, @default_ttl_ms)
    deadline = System.monotonic_time(:millisecond) + ttl
    GenServer.cast(__MODULE__, {:dispatch_async, message, opts, deadline})
  end

  @spec dispatch_tool(module(), map()) :: {:ok, map()} | {:error, term()}
  def dispatch_tool(tool, context \\ %{}) do
    GenServer.call(__MODULE__, {:dispatch_tool, tool, context})
  end

  @spec dispatch_tool_async(module(), map(), keyword()) :: :ok
  def dispatch_tool_async(tool, context \\ %{}, opts \\ []) do
    {ttl, _opts} = Keyword.pop(opts, :ttl, @default_ttl_ms)
    deadline = System.monotonic_time(:millisecond) + ttl
    GenServer.cast(__MODULE__, {:dispatch_tool_async, tool, context, deadline})
  end

  @doc "Return the last successfully dispatched board state, or nil."
  @spec last_board() :: %{grid: [[integer()]], text: String.t()} | nil
  def last_board do
    GenServer.call(__MODULE__, :last_board)
  end

  # --- Server callbacks ---

  @impl true
  def init(:ok), do: {:ok, %{last_board: nil}}

  @impl true
  def handle_call(:last_board, _from, state) do
    {:reply, state.last_board, state}
  end

  def handle_call({:dispatch, message, opts}, _from, state) do
    {result, grid} = do_dispatch(message, opts)
    {:reply, result, maybe_update_board(state, result, grid)}
  end

  def handle_call({:dispatch_tool, tool, context}, _from, state) do
    {result, grid} = do_dispatch_tool(tool, context)
    {:reply, result, maybe_update_board(state, result, grid)}
  end

  @impl true
  def handle_cast({:dispatch_async, message, opts, deadline}, state) do
    {result, grid} = if expired?(deadline), do: {{:error, :expired}, nil}, else: do_dispatch(message, opts)
    {:noreply, maybe_update_board(state, result, grid)}
  end

  def handle_cast({:dispatch_tool_async, tool, context, deadline}, state) do
    {result, grid} = if expired?(deadline), do: {{:error, :expired}, nil}, else: do_dispatch_tool(tool, context)
    {:noreply, maybe_update_board(state, result, grid)}
  end

  # --- Private ---

  defp do_dispatch(grid, _opts) when is_list(grid) do
    {Client.write_characters(grid), grid}
  end

  defp do_dispatch(text, opts) when is_binary(text) do
    case Renderer.render(text, opts) do
      {:ok, grid} -> {Client.write_characters(grid), grid}
      err -> {err, nil}
    end
  end

  defp do_dispatch_tool(tool, context) do
    case tool.run(context) do
      {:ok, text} -> do_dispatch(text, [])
      err -> {err, nil}
    end
  end

  defp maybe_update_board(state, {:ok, _}, grid) when is_list(grid) do
    %{state | last_board: %{grid: grid, text: Renderer.decode_grid(grid)}}
  end

  defp maybe_update_board(state, _, _), do: state

  defp expired?(deadline), do: System.monotonic_time(:millisecond) > deadline
end
