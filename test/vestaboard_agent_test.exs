defmodule VestaboardAgentTest do
  use ExUnit.Case
  doctest VestaboardAgent

  test "greets the world" do
    assert VestaboardAgent.hello() == :world
  end
end
