defmodule VestaboardAgent.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    http_port = Application.get_env(:vestaboard_agent, :http_port, 4000)

    children = [
      VestaboardAgent.Dispatcher,
      VestaboardAgent.ConversationContext,
      VestaboardAgent.Scheduler,
      VestaboardAgent.IntervalScheduler,
      VestaboardAgent.ToolRegistry,
      VestaboardAgent.AgentSupervisor,
      VestaboardAgent.Agent.Registry,
      {Bandit, plug: VestaboardAgent.Router, port: http_port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: VestaboardAgent.Supervisor)
  end
end
