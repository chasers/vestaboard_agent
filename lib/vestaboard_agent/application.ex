defmodule VestaboardAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VestaboardAgent.Dispatcher,
      VestaboardAgent.Scheduler,
      VestaboardAgent.ToolRegistry,
      VestaboardAgent.AgentSupervisor,
      VestaboardAgent.Agent.Registry
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: VestaboardAgent.Supervisor)
  end
end
