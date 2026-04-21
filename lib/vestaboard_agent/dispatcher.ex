defmodule VestaboardAgent.Dispatcher do
  @moduledoc """
  Serializes all writes to the Vestaboard through a single GenServer process.

  All agents share one board; routing every write through this GenServer ensures
  they never interleave. Sync (`dispatch/2`, `dispatch_tool/2`) block the caller
  until the write completes. Async variants (`dispatch_async/2`,
  `dispatch_tool_async/2`) are fire-and-forget with a TTL: if the message is
  still waiting when its deadline passes, it is silently dropped so stale data
  never appears on the board.
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

  # --- Server callbacks ---

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:dispatch, message, opts}, _from, state) do
    {:reply, do_dispatch(message, opts), state}
  end

  def handle_call({:dispatch_tool, tool, context}, _from, state) do
    {:reply, do_dispatch_tool(tool, context), state}
  end

  @impl true
  def handle_cast({:dispatch_async, message, opts, deadline}, state) do
    unless expired?(deadline), do: do_dispatch(message, opts)
    {:noreply, state}
  end

  def handle_cast({:dispatch_tool_async, tool, context, deadline}, state) do
    unless expired?(deadline), do: do_dispatch_tool(tool, context)
    {:noreply, state}
  end

  # --- Private ---

  defp do_dispatch(grid, _opts) when is_list(grid), do: Client.write_characters(grid)

  defp do_dispatch(text, opts) when is_binary(text) do
    with {:ok, grid} <- Renderer.render(text, opts) do
      Client.write_characters(grid)
    end
  end

  defp do_dispatch_tool(tool, context) do
    with {:ok, text} <- tool.run(context) do
      do_dispatch(text, [])
    end
  end

  defp expired?(deadline), do: System.monotonic_time(:millisecond) > deadline
end
