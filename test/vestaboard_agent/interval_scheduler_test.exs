defmodule VestaboardAgent.IntervalSchedulerTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.IntervalScheduler

  defp unique_name, do: :"interval_job_#{System.unique_integer([:positive])}"

  describe "schedule/3" do
    test "adds a job and it fires" do
      name = unique_name()
      parent = self()
      on_exit(fn -> IntervalScheduler.cancel(name) end)

      IntervalScheduler.schedule(name, 50, fn -> send(parent, :fired) end)

      assert_receive :fired, 500
    end

    test "replaces an existing job with the same name" do
      name = unique_name()
      parent = self()
      on_exit(fn -> IntervalScheduler.cancel(name) end)

      IntervalScheduler.schedule(name, 10_000, fn -> send(parent, :old) end)
      IntervalScheduler.schedule(name, 50, fn -> send(parent, :new) end)

      assert_receive :new, 500
      refute_received :old
    end
  end

  describe "cancel/1" do
    test "stops the job from firing" do
      name = unique_name()
      parent = self()

      IntervalScheduler.schedule(name, 50, fn -> send(parent, :fired) end)
      IntervalScheduler.cancel(name)

      refute_receive :fired, 200
    end

    test "is a no-op for unknown names" do
      assert :ok = IntervalScheduler.cancel(:does_not_exist)
    end
  end

  describe "list/0" do
    test "returns scheduled jobs" do
      name = unique_name()
      on_exit(fn -> IntervalScheduler.cancel(name) end)

      IntervalScheduler.schedule(name, 60_000, fn -> :ok end)

      assert Keyword.has_key?(IntervalScheduler.list(), name)
    end

    test "does not include cancelled jobs" do
      name = unique_name()
      IntervalScheduler.schedule(name, 60_000, fn -> :ok end)
      IntervalScheduler.cancel(name)

      refute Keyword.has_key?(IntervalScheduler.list(), name)
    end
  end
end
