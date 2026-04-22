defmodule VestaboardAgent.Agents.GreeterTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Agents.Greeter

  test "name/0 returns a string" do
    assert is_binary(Greeter.name())
  end

  test "keywords/0 returns a non-empty list" do
    assert Greeter.keywords() != []
  end

  test "implements the Agent behaviour" do
    assert function_exported?(Greeter, :name, 0)
    assert function_exported?(Greeter, :keywords, 0)
    assert function_exported?(Greeter, :handle, 2)
  end

  test "handle/2 returns {:ok, text} with a greeting string" do
    assert {:ok, text} = Greeter.handle("say hello", %{})
    assert is_binary(text)
    assert String.length(text) > 0
  end

  test "handle/2 injects current time when context has no :now" do
    assert {:ok, text} = Greeter.handle("greet me", %{})
    assert is_binary(text)
  end

  test "handle/2 returns a time-appropriate greeting" do
    morning = ~U[2024-06-15 09:00:00Z]
    assert {:ok, text} = Greeter.handle("hello", %{now: morning})
    assert text =~ ~r/morning/i
  end
end
