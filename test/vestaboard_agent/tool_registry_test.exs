defmodule VestaboardAgent.ToolRegistryTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.ToolRegistry
  alias VestaboardAgent.Tools.Clock

  @hello_script "return 'hello from lua'"

  # Each test gets its own ToolRegistry instance with an isolated temp dir,
  # so tests don't share state with the application-level registry.
  setup do
    tmp = System.tmp_dir!() |> Path.join("tool_registry_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, pid} = start_supervised({ToolRegistry, [scripts_dir: tmp, name: nil]})
    %{registry: pid, scripts_dir: tmp}
  end

  describe "register/2" do
    test "registers a module tool", %{registry: reg} do
      assert :ok = GenServer.call(reg, {:register, :test_clock, {:module, Clock}})
      assert {:ok, {:module, Clock}} = GenServer.call(reg, {:get, :test_clock})
    end

    test "public register/2 registers a module tool" do
      # The public API calls the named process; verify via the supervised instance
      assert :ok = ToolRegistry.register(:clock, Clock)
    end
  end

  describe "register_script/2" do
    test "stores the script in memory", %{registry: reg} do
      assert :ok = GenServer.call(reg, {:register_script, :greet, @hello_script})
      assert {:ok, {:script, @hello_script}} = GenServer.call(reg, {:get, :greet})
    end

    test "persists the script to disk", %{registry: reg, scripts_dir: dir} do
      GenServer.call(reg, {:register_script, :greet, @hello_script})
      assert File.exists?(Path.join(dir, "greet.lua"))
      assert File.read!(Path.join(dir, "greet.lua")) == @hello_script
    end

    test "rejects scripts with Lua syntax errors", %{registry: reg} do
      assert {:error, "Failed to compile Lua!" <> _} =
               GenServer.call(reg, {:register_script, :bad, "this is not lua ```"})
    end

    test "rejects markdown-fenced scripts that were not stripped", %{registry: reg} do
      fenced = "```lua\nreturn 'oops'\n```"

      assert {:error, "Failed to compile Lua!" <> _} =
               GenServer.call(reg, {:register_script, :bad_fenced, fenced})
    end

    test "accepts scripts that have runtime errors but valid syntax", %{registry: reg} do
      # This script will error at runtime (bad arithmetic) but compiles fine
      runtime_error_script = "return nil + 1"
      assert :ok = GenServer.call(reg, {:register_script, :runtime_err, runtime_error_script})
    end

    test "does not persist an invalid script to disk", %{registry: reg, scripts_dir: dir} do
      GenServer.call(reg, {:register_script, :bad, "not lua ```"})
      refute File.exists?(Path.join(dir, "bad.lua"))
    end
  end

  describe "unregister/1" do
    test "removes a module tool from the registry", %{registry: reg} do
      GenServer.call(reg, {:register, :temp, {:module, Clock}})
      GenServer.call(reg, {:unregister, :temp})
      assert {:error, :not_found} = GenServer.call(reg, {:get, :temp})
    end

    test "removes a script tool and deletes its file", %{registry: reg, scripts_dir: dir} do
      GenServer.call(reg, {:register_script, :temp_script, @hello_script})
      GenServer.call(reg, {:unregister, :temp_script})

      assert {:error, :not_found} = GenServer.call(reg, {:get, :temp_script})
      refute File.exists?(Path.join(dir, "temp_script.lua"))
    end

    test "is a no-op for unknown names", %{registry: reg} do
      assert :ok = GenServer.call(reg, {:unregister, :nonexistent})
    end
  end

  describe "get/1" do
    test "returns not_found for unknown names", %{registry: reg} do
      assert {:error, :not_found} = GenServer.call(reg, {:get, :unknown})
    end
  end

  describe "run/2" do
    test "runs a module tool", %{registry: reg} do
      GenServer.call(reg, {:register, :clk, {:module, Clock}})
      assert {:ok, text} = GenServer.call(reg, {:run, :clk, %{}})
      assert is_binary(text)
    end

    test "runs a Lua script tool", %{registry: reg} do
      GenServer.call(reg, {:register_script, :hello, @hello_script})
      assert {:ok, "hello from lua"} = GenServer.call(reg, {:run, :hello, %{}})
    end

    test "returns not_found for unknown names", %{registry: reg} do
      assert {:error, :not_found} = GenServer.call(reg, {:run, :unknown, %{}})
    end
  end

  describe "list/0" do
    test "returns module tools as :module type", %{registry: reg} do
      GenServer.call(reg, {:register, :clk, {:module, Clock}})
      list = GenServer.call(reg, :list)
      assert {:clk, :module} in list
    end

    test "returns script tools as :script type", %{registry: reg} do
      GenServer.call(reg, {:register_script, :hello, @hello_script})
      list = GenServer.call(reg, :list)
      assert {:hello, :script} in list
    end
  end

  describe "startup" do
    test "loads built-in tools on start", %{registry: reg} do
      list = GenServer.call(reg, :list)
      names = Keyword.keys(list)
      assert :clock in names
      assert :weather in names
      assert :quote in names
      assert :greeting in names
    end

    test "reloads persisted scripts on restart", %{scripts_dir: dir} do
      # Write a script directly to the dir before starting a fresh registry
      File.write!(Path.join(dir, "persisted.lua"), @hello_script)

      {:ok, reg2} = start_supervised({ToolRegistry, [scripts_dir: dir, name: nil]}, id: :reg2)

      assert {:ok, {:script, @hello_script}} = GenServer.call(reg2, {:get, :persisted})
    end
  end
end
