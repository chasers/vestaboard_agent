defmodule VestaboardAgent.ClientTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.Client

  defmodule StubBackend do
    @behaviour VestaboardAgent.Client
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
      assert Client.backend() == VestaboardAgent.Client.Cloud
    end

    test "returns the configured backend" do
      Application.put_env(:vestaboard_agent, :client, backend: StubBackend)
      assert Client.backend() == StubBackend
    end
  end

  describe "dispatch" do
    setup do
      Application.put_env(:vestaboard_agent, :client, backend: StubBackend)
    end

    test "read/0 delegates to backend" do
      assert {:ok, []} = Client.read()
    end

    test "write_characters/1 delegates to backend" do
      assert {:ok, %{}} = Client.write_characters([[0]])
    end
  end
end
