defmodule VestaboardAgent.Agents.ScheduleAgent do
  @moduledoc """
  Schedules a tool to run on a cron expression and dispatch its output to the board.

  Uses `VestaboardAgent.Scheduler` (Quantum) under the hood. All writes go
  through `Dispatcher.dispatch_tool_async/3` so concurrent schedules are
  serialized and stale writes are dropped automatically.

  ## Programmatic API

      # Show the clock every minute
      ScheduleAgent.schedule(:clock, Clock, "* * * * *")

      # Show weather every 10 minutes with a location
      ScheduleAgent.schedule(:weather, Weather, "*/10 * * * *", %{
        latitude: 37.7749,
        longitude: -122.4194
      })

      ScheduleAgent.cancel(:clock)
      ScheduleAgent.list()
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.{Dispatcher, Scheduler}

  @impl true
  def name, do: "schedule"

  @impl true
  def keywords, do: ["schedule", "every", "cron", "timer", "remind"]

  @impl true
  def handle(_prompt, _context) do
    {:error, :requires_llm_routing}
  end

  @doc "Schedule a tool to run on a cron expression."
  @spec schedule(atom(), module(), String.t(), map()) :: :ok
  def schedule(name, tool_module, cron_expr, context \\ %{}) do
    job =
      Scheduler.new_job()
      |> Quantum.Job.set_name(name)
      |> Quantum.Job.set_schedule(Crontab.CronExpression.Parser.parse!(cron_expr))
      |> Quantum.Job.set_task(fn -> Dispatcher.dispatch_tool_async(tool_module, context) end)

    Scheduler.add_job(job)
  end

  @doc "Cancel a scheduled job by name."
  @spec cancel(atom()) :: :ok
  def cancel(name) do
    Scheduler.delete_job(name)
  end

  @doc "List all scheduled jobs as a keyword list of `{name, Quantum.Job.t()}`."
  @spec list() :: [{atom(), Quantum.Job.t()}]
  def list do
    Scheduler.jobs()
  end
end
