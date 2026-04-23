defmodule VestaboardAgent.Agents.DisplayAgentTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Agents.DisplayAgent

  test "strips 'display ' prefix and returns the rest" do
    assert DisplayAgent.handle("display Good morning Teddy!", %{}) == {:ok, "Good morning Teddy!"}
  end

  test "is case-insensitive for the prefix" do
    assert DisplayAgent.handle("DISPLAY Hello world", %{}) == {:ok, "Hello world"}
  end

  test "handles extra whitespace after keyword" do
    assert DisplayAgent.handle("display   spaced out", %{}) == {:ok, "spaced out"}
  end

  test "keywords/0 includes display" do
    assert "display" in DisplayAgent.keywords()
  end
end
