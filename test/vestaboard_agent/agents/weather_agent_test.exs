defmodule VestaboardAgent.Agents.WeatherAgentTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Agents.WeatherAgent

  test "name/0 returns a string" do
    assert is_binary(WeatherAgent.name())
  end

  test "keywords/0 returns a non-empty list" do
    assert WeatherAgent.keywords() != []
  end

  test "implements the Agent behaviour" do
    assert function_exported?(WeatherAgent, :name, 0)
    assert function_exported?(WeatherAgent, :keywords, 0)
    assert function_exported?(WeatherAgent, :handle, 2)
  end

  test "handle/2 returns {:ok, text} when location is configured" do
    plug = {Req.Test, __MODULE__}

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "current" => %{
          "temperature_2m" => 72.1,
          "apparent_temperature" => 68.4,
          "weathercode" => 0,
          "windspeed_10m" => 5.2
        }
      })
    end)

    assert {:ok, text} = WeatherAgent.handle("what's the weather?", %{
      latitude: 37.7749,
      longitude: -122.4194,
      plug: plug
    })

    assert is_binary(text)
    assert text =~ "72"
    assert text =~ "CLEAR SKY"
  end

  test "handle/2 returns {:error, :location_required} when no location is set" do
    original = Application.get_env(:vestaboard_agent, :weather, [])
    Application.put_env(:vestaboard_agent, :weather, [])
    on_exit(fn -> Application.put_env(:vestaboard_agent, :weather, original) end)

    assert {:error, :location_required} = WeatherAgent.handle("weather", %{})
  end
end
