defmodule VestaboardAgent.Tools.GreetingTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Tools.Greeting

  test "name/0 returns a string" do
    assert is_binary(Greeting.name())
  end

  test "implements the Tool behaviour" do
    assert function_exported?(Greeting, :name, 0)
    assert function_exported?(Greeting, :run, 1)
  end

  describe "run/1 greetings by time of day" do
    test "returns good morning before noon" do
      assert {:ok, "Good morning!"} = Greeting.run(%{now: "2026-04-21T08:00:00Z"})
    end

    test "returns good afternoon between noon and 6pm" do
      assert {:ok, "Good afternoon!"} = Greeting.run(%{now: "2026-04-21T14:00:00Z"})
    end

    test "returns good evening at or after 6pm" do
      assert {:ok, "Good evening!"} = Greeting.run(%{now: "2026-04-21T19:00:00Z"})
    end

    test "returns good afternoon at exactly noon" do
      assert {:ok, "Good afternoon!"} = Greeting.run(%{now: "2026-04-21T12:00:00Z"})
    end

    test "returns good evening at exactly 6pm" do
      assert {:ok, "Good evening!"} = Greeting.run(%{now: "2026-04-21T18:00:00Z"})
    end

    test "accepts a DateTime for context.now" do
      dt = ~U[2026-04-21 09:00:00Z]
      assert {:ok, "Good morning!"} = Greeting.run(%{now: dt})
    end

    test "defaults to afternoon when context is empty" do
      # no `now` → context.now is "" → tonumber("") is nil → defaults to 12 → afternoon
      assert {:ok, "Good afternoon!"} = Greeting.run(%{})
    end
  end
end
