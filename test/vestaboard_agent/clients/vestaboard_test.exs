defmodule VestaboardAgent.Clients.VestaboardTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Clients.Vestaboard

  defmodule StubBackend do
    @behaviour VestaboardAgent.Clients.Vestaboard
    @impl true
    def read, do: {:ok, []}
    @impl true
    def write_characters(_), do: {:ok, %{}}
  end

  setup do
    original = Application.get_env(:vestaboard_agent, :client, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :client, original) end)
  end

  describe "backend/0" do
    test "defaults to Cloud" do
      Application.put_env(:vestaboard_agent, :client, [])
      assert Vestaboard.backend() == VestaboardAgent.Clients.Vestaboard.Cloud
    end

    test "returns the configured backend" do
      Application.put_env(:vestaboard_agent, :client, backend: StubBackend)
      assert Vestaboard.backend() == StubBackend
    end
  end

  describe "dispatch" do
    setup do
      Application.put_env(:vestaboard_agent, :client, backend: StubBackend)
    end

    test "read/0 delegates to backend" do
      assert {:ok, []} = Vestaboard.read()
    end

    test "write_characters/1 delegates to backend" do
      assert {:ok, %{}} = Vestaboard.write_characters([[0]])
    end
  end
end
