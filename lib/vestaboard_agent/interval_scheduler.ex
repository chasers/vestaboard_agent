defmodule VestaboardAgent.IntervalScheduler do
  @moduledoc """
  Sub-minute interval scheduling using `:timer.apply_interval`.

  Used by `ScheduleAgent` when the requested interval is less than 60 seconds.
  Minute-and-above intervals go through Quantum instead.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Schedule `fun` to run every `interval_ms` milliseconds under `name`."
  @spec schedule(atom(), pos_integer(), (-> any())) :: :ok
  def schedule(name, interval_ms, fun) when is_atom(name) and is_integer(interval_ms) do
    GenServer.call(__MODULE__, {:schedule, name, interval_ms, fun})
  end

  @doc "Cancel a job by name. No-op if the name is unknown."
  @spec cancel(atom()) :: :ok
  def cancel(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:cancel, name})
  end

  @doc "List all interval jobs as `[{name, interval_ms}]`."
  @spec list() :: [{atom(), pos_integer()}]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- Server callbacks ---

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:schedule, name, interval_ms, fun}, _from, state) do
    if existing = Map.get(state, name) do
      :timer.cancel(existing.tref)
    end

    {:ok, tref} = :timer.apply_interval(interval_ms, :erlang, :apply, [fun, []])
    {:reply, :ok, Map.put(state, name, %{tref: tref, interval_ms: interval_ms})}
  end

  def handle_call({:cancel, name}, _from, state) do
    case Map.get(state, name) do
      nil -> {:reply, :ok, state}
      %{tref: tref} -> :timer.cancel(tref); {:reply, :ok, Map.delete(state, name)}
    end
  end

  def handle_call(:list, _from, state) do
    entries = Enum.map(state, fn {name, %{interval_ms: ms}} -> {name, ms} end)
    {:reply, entries, state}
  end
end
