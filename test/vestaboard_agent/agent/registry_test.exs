defmodule VestaboardAgent.Agent.RegistryTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Agent.Registry

  defmodule WeatherAgent do
    @behaviour VestaboardAgent.Agent
    @impl true
    def name, do: "weather"
    @impl true
    def keywords, do: ["weather", "forecast"]
    @impl true
    def handle(_prompt, _context), do: {:ok, :done}
  end

  describe "agents/0" do
    test "includes default agents on startup" do
      assert VestaboardAgent.Agents.Greeter in Registry.agents()
    end
  end

  describe "register/1" do
    test "adds an agent to the registry" do
      Registry.register(WeatherAgent)
      assert WeatherAgent in Registry.agents()
    end
  end

  describe "route/1" do
    test "matches a prompt to an agent by keyword" do
      assert {:ok, VestaboardAgent.Agents.Greeter} = Registry.route("say hello")
    end

    test "matching is case-insensitive" do
      assert {:ok, VestaboardAgent.Agents.Greeter} = Registry.route("HELLO THERE")
    end

    test "returns no_match when no agent matches" do
      assert {:error, :no_match} = Registry.route("do something unknown")
    end
  end

  describe "handle/2" do
    test "returns no_match error for unrecognized prompts" do
      assert {:error, :no_match} = Registry.handle("xyzzy")
    end
  end
end
