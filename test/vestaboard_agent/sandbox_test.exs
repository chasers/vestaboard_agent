defmodule VestaboardAgent.SandboxTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Sandbox

  defmodule StubSandbox do
    @behaviour VestaboardAgent.Sandbox
    @impl true
    def run(_script, _context), do: {:ok, "from stub"}
  end

  describe "backend/0" do
    test "returns Lua backend by default" do
      assert Sandbox.backend() == VestaboardAgent.Sandbox.Lua
    end

    test "returns the configured backend when set" do
      Application.put_env(:vestaboard_agent, :sandbox, StubSandbox)
      on_exit(fn -> Application.delete_env(:vestaboard_agent, :sandbox) end)

      assert Sandbox.backend() == StubSandbox
    end
  end

  describe "run/2" do
    test "delegates to the configured backend" do
      Application.put_env(:vestaboard_agent, :sandbox, StubSandbox)
      on_exit(fn -> Application.delete_env(:vestaboard_agent, :sandbox) end)

      assert {:ok, "from stub"} = Sandbox.run("anything")
    end

    test "runs a script through the default Lua backend" do
      assert {:ok, "ok"} = Sandbox.run(~s[return "ok"])
    end
  end
end
