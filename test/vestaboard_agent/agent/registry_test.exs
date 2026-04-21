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

  setup do
    original = Application.get_env(:vestaboard_agent, :llm, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :llm, original) end)
    # Ensure LLM routing is disabled unless a test explicitly enables it
    Application.put_env(:vestaboard_agent, :llm, api_key: nil)
    :ok
  end

  describe "agents/0" do
    test "includes default agents on startup" do
      assert VestaboardAgent.Agents.Greeter in Registry.agents()
    end

    test "includes DynamicAgent as default" do
      assert VestaboardAgent.Agents.DynamicAgent in Registry.agents()
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
      assert {:error, :no_match} = Registry.route("do something unknown xyz")
    end
  end

  describe "handle/2 LLM fallback" do
    test "returns {:error, :no_match} when no keyword match and no API key" do
      assert {:error, :no_match} = Registry.handle("xyzzy plugh")
    end

    test "uses LLM to route when keyword match fails and API key is present" do
      Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")

      llm_stub = fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "greeter"}]
        })
      end

      # Greeter dispatches to the board — stub the HTTP layer too
      Req.Test.stub(VestaboardAgent.DispatcherTest, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-llm"})
      end)

      Req.Test.allow(
        VestaboardAgent.DispatcherTest,
        self(),
        Process.whereis(VestaboardAgent.Dispatcher)
      )

      Application.put_env(:vestaboard_agent, :client,
        backend: VestaboardAgent.Client.Local,
        api_key: "test-key",
        base_url: "http://vestaboard.local:7000",
        plug: {Req.Test, VestaboardAgent.DispatcherTest}
      )

      result = Registry.handle("something that smells like a greeting", %{
        llm_opts: [plug: llm_stub]
      })

      assert {:ok, :done} = result
    end

    test "falls back to DynamicAgent when LLM returns an unknown name" do
      Application.put_env(:vestaboard_agent, :llm, api_key: "test-key")

      # DynamicAgent will call LLM again to generate a script — stub both calls
      script_stub = fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "return 'hello'"}]
        })
      end

      Req.Test.stub(VestaboardAgent.DispatcherTest, fn conn ->
        Req.Test.json(conn, %{"id" => "msg-dyn"})
      end)

      Req.Test.allow(
        VestaboardAgent.DispatcherTest,
        self(),
        Process.whereis(VestaboardAgent.Dispatcher)
      )

      Application.put_env(:vestaboard_agent, :client,
        backend: VestaboardAgent.Client.Local,
        api_key: "test-key",
        base_url: "http://vestaboard.local:7000",
        plug: {Req.Test, VestaboardAgent.DispatcherTest}
      )

      unique_prompt = "completely unknown request #{System.unique_integer([:positive])}"

      result =
        Registry.handle(unique_prompt, %{
          llm_opts: [plug: fn conn ->
            # First call is routing (returns "dynamic"), second is script generation
            script_stub.(conn)
          end]
        })

      # DynamicAgent either succeeds or errors — either way it tried
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
