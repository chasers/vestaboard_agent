defmodule VestaboardAgent.Agents.ScheduleAgent do
  @moduledoc """
  Schedules a tool to run on a recurring interval and dispatch its output to the board.

  For intervals >= 60 seconds, uses `VestaboardAgent.Scheduler` (Quantum) with a
  standard cron expression. For sub-minute intervals, uses
  `VestaboardAgent.IntervalScheduler` backed by `:timer.apply_interval`.

  ## Programmatic API

      # Show the clock every minute (cron string)
      ScheduleAgent.schedule(:clock, Clock, "* * * * *")

      # Show clock every 15 seconds (integer seconds)
      ScheduleAgent.schedule(:clock, Clock, 15)

      # Show weather every 10 minutes with a location
      ScheduleAgent.schedule(:weather, Weather, "*/10 * * * *", %{
        latitude: 37.7749,
        longitude: -122.4194
      })

      ScheduleAgent.cancel(:clock)
      ScheduleAgent.list()

  ## Natural-language API (via `handle/2`)

      ScheduleAgent.handle("show clock every 15 seconds", %{})
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.{Dispatcher, IntervalScheduler, LLM, Scheduler, ToolRegistry}

  @impl true
  def name, do: "schedule"

  @impl true
  def keywords, do: ["schedule", "every", "cron", "timer", "remind"]

  @impl true
  def handle(prompt, context) do
    llm_opts = Map.get(context, :llm_opts, [])
    tool_names = ToolRegistry.list() |> Enum.map(fn {name, _} -> Atom.to_string(name) end)

    with {:ok, %{tool: tool_name, interval_seconds: secs}} <-
           LLM.parse_schedule(prompt, tool_names, llm_opts),
         {:ok, tool_atom} <- to_existing_atom(tool_name),
         {:ok, entry} <- ToolRegistry.get(tool_atom),
         tool_module <- entry_to_runnable(tool_atom, entry),
         job_name = job_name(tool_atom),
         :ok <- schedule(job_name, tool_module, secs) do
      {:ok, :done}
    end
  end

  @doc """
  Schedule a tool to run on a recurring schedule under `name`.

  `schedule` is either:
  - a cron expression string (e.g. `"*/5 * * * *"`) — delegated to Quantum
  - a positive integer (seconds) — uses `IntervalScheduler` if < 60, else converts to cron
  """
  @spec schedule(atom(), module() | atom(), String.t() | pos_integer(), map()) :: :ok
  def schedule(name, tool, schedule, context \\ %{})

  def schedule(name, tool, cron, context) when is_binary(cron) do
    job =
      Scheduler.new_job()
      |> Quantum.Job.set_name(name)
      |> Quantum.Job.set_schedule(Crontab.CronExpression.Parser.parse!(cron))
      |> Quantum.Job.set_task(fn -> Dispatcher.dispatch_tool_async(tool, context) end)

    Scheduler.add_job(job)
  end

  def schedule(name, tool, seconds, context) when is_integer(seconds) and seconds > 0 do
    if seconds < 60 do
      IntervalScheduler.schedule(name, seconds * 1_000, fn ->
        Dispatcher.dispatch_tool_async(tool, context)
      end)
    else
      cron = seconds_to_cron(seconds)
      schedule(name, tool, cron, context)
    end
  end

  @doc "Cancel a scheduled job by name (checks both Quantum and IntervalScheduler)."
  @spec cancel(atom()) :: :ok
  def cancel(name) do
    Scheduler.delete_job(name)
    IntervalScheduler.cancel(name)
  end

  @doc "List all scheduled jobs from both schedulers."
  @spec list() :: [{atom(), :quantum | :interval}]
  def list do
    quantum_jobs = Scheduler.jobs() |> Enum.map(fn {name, _} -> {name, :quantum} end)
    interval_jobs = IntervalScheduler.list() |> Enum.map(fn {name, _} -> {name, :interval} end)
    quantum_jobs ++ interval_jobs
  end

  # --- Private ---

  defp to_existing_atom(str) do
    {:ok, String.to_existing_atom(str)}
  rescue
    ArgumentError -> {:error, {:unknown_tool, str}}
  end

  defp entry_to_runnable(_name, {:module, mod}), do: mod

  defp entry_to_runnable(name, {:script, _script}) do
    # Return the atom name so dispatch_tool_async can resolve via ToolRegistry
    name
  end

  defp job_name(tool_atom) do
    :"#{tool_atom}_#{System.unique_integer([:positive])}"
  end

  defp seconds_to_cron(seconds) do
    minutes = div(seconds, 60)

    cond do
      minutes == 1 -> "* * * * *"
      minutes < 60 -> "*/#{minutes} * * * *"
      rem(minutes, 60) == 0 -> "0 */#{div(minutes, 60)} * * *"
      true -> "*/#{minutes} * * * *"
    end
  end
end
