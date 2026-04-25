defmodule VestaboardAgent.Scheduler do
  @moduledoc """
  Quantum job scheduler for cron-based scheduling (minute-or-above intervals).

  Managed by `ScheduleAgent`. Sub-minute intervals use `IntervalScheduler` instead.
  """

  use Quantum, otp_app: :vestaboard_agent
end
