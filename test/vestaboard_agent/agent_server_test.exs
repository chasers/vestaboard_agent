defmodule VestaboardAgent.AgentServerTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.AgentServer

  defmodule FastAgent do
    @behaviour VestaboardAgent.Agent
    def name, do: "fast"
    def keywords, do: ["fast"]
    def handle(_prompt, _context), do: {:ok, :done}
  end

  defmodule SlowAgent do
    @behaviour VestaboardAgent.Agent
    def name, do: "slow"
    def keywords, do: ["slow"]

    def handle(_prompt, _context) do
      Process.sleep(10_000)
      {:ok, :done}
    end
  end

  defmodule ErrorAgent do
    @behaviour VestaboardAgent.Agent
    def name, do: "error"
    def keywords, do: ["error"]
    def handle(_prompt, _context), do: {:error, :something_went_wrong}
  end

  defp start_server(agent, prompt \\ "test", context \\ %{}) do
    start_supervised!({AgentServer, [agent: agent, prompt: prompt, context: context]})
  end

  test "starts with :running status" do
    pid = start_server(SlowAgent)
    assert {:running, nil} = AgentServer.status(pid)
  end

  test "transitions to :done when agent finishes" do
    pid = start_server(FastAgent)
    # give the Task time to complete
    Process.sleep(50)
    assert {:done, {:ok, :done}} = AgentServer.status(pid)
  end

  test "stores the agent's return value as result" do
    pid = start_server(ErrorAgent)
    Process.sleep(50)
    assert {:done, {:error, :something_went_wrong}} = AgentServer.status(pid)
  end

  test "cancel/1 stops a running agent" do
    pid = start_server(SlowAgent)
    assert :ok = AgentServer.cancel(pid)
    assert {:cancelled, nil} = AgentServer.status(pid)
  end

  test "cancel/1 is a no-op on a finished agent" do
    pid = start_server(FastAgent)
    Process.sleep(50)
    assert {:done, _} = AgentServer.status(pid)
    assert :ok = AgentServer.cancel(pid)
    assert {:done, _} = AgentServer.status(pid)
  end

  describe "awaiter notification" do
    test "notifies awaiter with result when task completes" do
      pid =
        start_supervised!({AgentServer, [agent: FastAgent, prompt: "test", awaiter: self()]})

      assert_receive {:agent_result, ^pid, {:ok, :done}}, 500
    end

    test "no message sent when no awaiter is set" do
      _pid = start_server(FastAgent)
      Process.sleep(100)
      refute_received {:agent_result, _, _}
    end
  end
end
