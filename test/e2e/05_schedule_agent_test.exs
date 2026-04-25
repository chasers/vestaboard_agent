defmodule VestaboardAgent.E2E.ScheduleAgentTest do
  use VestaboardAgent.E2ECase

  alias VestaboardAgent.{Agents.ScheduleAgent, Dispatcher}
  alias VestaboardAgent.Tools.Clock

  defp unique_name, do: :"e2e_job_#{System.unique_integer([:positive])}"

  describe "interval scheduling" do
    test "sub-minute interval fires and updates the board" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      :sys.replace_state(Dispatcher, fn state -> %{state | last_board: nil} end)
      ScheduleAgent.schedule(name, Clock, 2)

      # Wait long enough for at least one fire
      Process.sleep(3_500)

      board = Dispatcher.last_board()

      assert board != nil,
             "Board was not updated after 3.5s — interval job may not have fired (job: #{name})"

      assert String.match?(board.text, ~r/\d+:\d+/),
             "Expected time pattern after Clock fires, got: #{inspect(board.text)}"
    end

    test "cancelling before first fire leaves board unchanged" do
      name = unique_name()

      :sys.replace_state(Dispatcher, fn state -> %{state | last_board: nil} end)
      ScheduleAgent.schedule(name, Clock, 5)
      ScheduleAgent.cancel(name)

      Process.sleep(6_000)

      assert Dispatcher.last_board() == nil,
             "Board was updated after cancel — job may not have been cancelled in time"
    end

    test "job appears in ScheduleAgent.list() after scheduling" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, 10)

      jobs = ScheduleAgent.list()

      assert Keyword.has_key?(jobs, name),
             "Expected #{name} in job list, got: #{inspect(jobs)}"

      assert Keyword.get(jobs, name) == :interval
    end

    test "cancelled job is removed from list" do
      name = unique_name()
      ScheduleAgent.schedule(name, Clock, 10)
      ScheduleAgent.cancel(name)

      refute Keyword.has_key?(ScheduleAgent.list(), name)
    end
  end

  describe "quantum (minute+) scheduling" do
    test "cron job appears in scheduler" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, "* * * * *")

      jobs = ScheduleAgent.list()

      assert Keyword.has_key?(jobs, name),
             "Expected #{name} in job list, got: #{inspect(jobs)}"

      assert Keyword.get(jobs, name) == :quantum
    end

    test "60-second integer routes to Quantum" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, 60)

      assert Keyword.get(ScheduleAgent.list(), name) == :quantum
    end
  end

  describe "NLP scheduling via display/1" do
    test "'show clock every 5 seconds' registers an interval job" do
      result = e2e_display("show clock every 5 seconds")

      assert result.display_result == {:ok, :done},
             "Expected {:ok, :done} for schedule prompt, got: #{inspect(result.display_result)}"

      jobs = ScheduleAgent.list()
      interval_jobs = Enum.filter(jobs, fn {_name, type} -> type == :interval end)

      assert interval_jobs != [],
             "Expected at least one interval job after scheduling, got: #{inspect(jobs)}"

      # Clean up the job(s) created by the NLP schedule
      Enum.each(interval_jobs, fn {name, _} -> ScheduleAgent.cancel(name) end)
    end
  end
end
