defmodule VestaboardAgent.AgentSupervisorTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.AgentSupervisor

  defmodule InstantAgent do
    @behaviour VestaboardAgent.Agent
    def name, do: "instant"
    def keywords, do: []
    def handle(_prompt, _context), do: {:ok, :done}
  end

  defmodule BlockingAgent do
    @behaviour VestaboardAgent.Agent
    def name, do: "blocking"
    def keywords, do: []

    def handle(_prompt, _context) do
      Process.sleep(10_000)
      {:ok, :done}
    end
  end

  test "run/3 returns {:ok, pid}" do
    assert {:ok, pid} = AgentSupervisor.run(InstantAgent, "test")
    assert is_pid(pid)
  end

  test "run/3 spawns a child under the supervisor" do
    before_count = length(AgentSupervisor.list())
    {:ok, _pid} = AgentSupervisor.run(BlockingAgent, "test")
    after_count = length(AgentSupervisor.list())
    assert after_count == before_count + 1
  end

  test "status/1 reflects agent state" do
    {:ok, pid} = AgentSupervisor.run(InstantAgent, "test")
    Process.sleep(50)
    assert {:done, {:ok, :done}} = AgentSupervisor.status(pid)
  end

  test "cancel/1 stops a running agent" do
    {:ok, pid} = AgentSupervisor.run(BlockingAgent, "test")
    assert :ok = AgentSupervisor.cancel(pid)
    refute Process.alive?(pid)
  end

  test "list/0 returns a list" do
    assert is_list(AgentSupervisor.list())
  end
end
