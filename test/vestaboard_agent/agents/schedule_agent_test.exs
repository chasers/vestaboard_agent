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

  describe "handle/2" do
    setup do
      original_llm = Application.get_env(:vestaboard_agent, :llm, [])
      on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original_llm) end)
      Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")
      :ok
    end

    test "returns {:ok, :done} on a valid schedule prompt" do
      stub = fn conn ->
        Req.Test.json(conn, %{
          content: [%{text: ~s({"tool": "clock", "interval_seconds": 30})}]
        })
      end

      assert {:ok, :done} =
               ScheduleAgent.handle("show clock every 30 seconds", %{llm_opts: [plug: stub]})
    end

    test "returns error when LLM returns invalid JSON" do
      stub = fn conn ->
        Req.Test.json(conn, %{content: [%{text: "not json"}]})
      end

      assert {:error, _} =
               ScheduleAgent.handle("show something", %{llm_opts: [plug: stub]})
    end

    test "returns error when tool name is unknown" do
      stub = fn conn ->
        Req.Test.json(conn, %{
          content: [%{text: ~s({"tool": "nonexistent_xyz", "interval_seconds": 60})}]
        })
      end

      assert {:error, _} =
               ScheduleAgent.handle("show nonexistent", %{llm_opts: [plug: stub]})
    end
  end

  describe "schedule/4 with cron string" do
    test "adds a job to Quantum" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, "* * * * *")

      assert Keyword.has_key?(VestaboardAgent.Scheduler.jobs(), name)
    end

    test "accepts a context map" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, "0 * * * *", %{timezone: "UTC"})

      assert Keyword.has_key?(VestaboardAgent.Scheduler.jobs(), name)
    end
  end

  describe "schedule/4 with integer seconds" do
    test "sub-minute uses IntervalScheduler" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, 15)

      assert Keyword.has_key?(VestaboardAgent.IntervalScheduler.list(), name)
      refute Keyword.has_key?(VestaboardAgent.Scheduler.jobs(), name)
    end

    test "60 seconds uses Quantum" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, 60)

      assert Keyword.has_key?(VestaboardAgent.Scheduler.jobs(), name)
      refute Keyword.has_key?(VestaboardAgent.IntervalScheduler.list(), name)
    end

    test "5 minutes uses Quantum" do
      name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(name) end)

      ScheduleAgent.schedule(name, Clock, 300)

      assert Keyword.has_key?(VestaboardAgent.Scheduler.jobs(), name)
    end
  end

  describe "cancel/1" do
    test "removes a Quantum job" do
      name = unique_name()
      ScheduleAgent.schedule(name, Clock, "* * * * *")
      ScheduleAgent.cancel(name)

      refute Keyword.has_key?(VestaboardAgent.Scheduler.jobs(), name)
    end

    test "removes an interval job" do
      name = unique_name()
      ScheduleAgent.schedule(name, Clock, 10)
      ScheduleAgent.cancel(name)

      refute Keyword.has_key?(VestaboardAgent.IntervalScheduler.list(), name)
    end

    test "is a no-op for unknown names" do
      assert :ok = ScheduleAgent.cancel(:nonexistent_job_xyz)
    end
  end

  describe "list/0" do
    test "returns a list of {name, type} tuples" do
      assert is_list(ScheduleAgent.list())
      Enum.each(ScheduleAgent.list(), fn {name, type} ->
        assert is_atom(name)
        assert type in [:quantum, :interval]
      end)
    end

    test "includes both quantum and interval jobs" do
      q_name = unique_name()
      i_name = unique_name()
      on_exit(fn -> ScheduleAgent.cancel(q_name); ScheduleAgent.cancel(i_name) end)

      ScheduleAgent.schedule(q_name, Clock, "* * * * *")
      ScheduleAgent.schedule(i_name, Clock, 5)

      all = ScheduleAgent.list()
      assert Keyword.get(all, q_name) == :quantum
      assert Keyword.get(all, i_name) == :interval
    end
  end
end
