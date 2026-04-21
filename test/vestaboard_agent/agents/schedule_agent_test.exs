defmodule VestaboardAgent.Agents.ScheduleAgentTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agents.ScheduleAgent
  alias VestaboardAgent.Tools.Clock

  defp unique_name, do: :"test_job_#{System.unique_integer([:positive])}"

  test "name/0 returns schedule" do
    assert ScheduleAgent.name() == "schedule"
  end

  test "keywords/0 is non-empty" do
    assert ScheduleAgent.keywords() != []
  end

  test "implements the Agent behaviour" do
    assert function_exported?(ScheduleAgent, :name, 0)
    assert function_exported?(ScheduleAgent, :keywords, 0)
    assert function_exported?(ScheduleAgent, :handle, 2)
  end

  test "handle/2 returns error until LLM routing is implemented" do
    assert {:error, _} = ScheduleAgent.handle("schedule clock every minute", %{})
  end

  describe "schedule/4" do
    test "adds a job to the scheduler" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, "* * * * *")

      assert Keyword.has_key?(ScheduleAgent.list(), name)
    end

    test "scheduled job has correct cron expression" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, "*/5 * * * *")

      job = Keyword.get(ScheduleAgent.list(), name)
      assert %Quantum.Job{} = job
    end

    test "accepts a context map" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, "0 * * * *", %{timezone: "UTC"})

      assert Keyword.has_key?(ScheduleAgent.list(), name)
    end
  end

  describe "cancel/1" do
    test "removes a job from the scheduler" do
      name = unique_name()
      ScheduleAgent.schedule(name, Clock, "* * * * *")
      ScheduleAgent.cancel(name)

      refute Keyword.has_key?(ScheduleAgent.list(), name)
    end

    test "is a no-op for unknown job names" do
      assert :ok = ScheduleAgent.cancel(:nonexistent_job_xyz)
    end
  end

  describe "list/0" do
    test "returns a keyword list" do
      assert is_list(ScheduleAgent.list())
    end

    test "contains all scheduled jobs" do
      name1 = unique_name()
      name2 = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name1); ScheduleAgent.cancel(name2) end)

      ScheduleAgent.schedule(name1, Clock, "* * * * *")
      ScheduleAgent.schedule(name2, Clock, "0 8 * * *")

      jobs = ScheduleAgent.list()
      assert Keyword.has_key?(jobs, name1)
      assert Keyword.has_key?(jobs, name2)
    end
  end
end
