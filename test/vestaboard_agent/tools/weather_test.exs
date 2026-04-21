defmodule VestaboardAgent.Tools.WeatherTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Tools.Weather

  @lat 37.7749
  @lon -122.4194

  @api_response %{
    "current" => %{
      "temperature_2m" => 68.4,
      "apparent_temperature" => 65.1,
      "weathercode" => 2,
      "windspeed_10m" => 12.3
    }
  }

  defp ctx(overrides \\ %{}) do
    Map.merge(%{latitude: @lat, longitude: @lon, plug: {Req.Test, __MODULE__}}, overrides)
  end

  test "name/0 returns weather" do
    assert Weather.name() == "weather"
  end

  test "returns {:ok, string} on success" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, @api_response)
    end)

    assert {:ok, text} = Weather.run(ctx())
    assert is_binary(text)
  end

  test "formats temperature and feels-like" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, @api_response)
    end)

    {:ok, text} = Weather.run(ctx())
    assert String.contains?(text, "68F")
    assert String.contains?(text, "FEELS 65F")
  end

  test "formats wind speed" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, @api_response)
    end)

    {:ok, text} = Weather.run(ctx())
    assert String.contains?(text, "WIND 12 MPH")
  end

  test "formats weather condition from WMO code" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, @api_response)
    end)

    {:ok, text} = Weather.run(ctx())
    assert String.contains?(text, "PARTLY CLOUDY")
  end

  test "returns error when location is missing" do
    assert {:error, :location_required} = Weather.run(%{})
  end

  test "reads location from app config when not in context" do
    original = Application.get_env(:vestaboard_agent, :weather, [])

    on_exit(fn ->
      Application.put_env(:vestaboard_agent, :weather, original)
    end)

    Application.put_env(:vestaboard_agent, :weather, latitude: @lat, longitude: @lon)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, @api_response)
    end)

    assert {:ok, _text} = Weather.run(%{plug: {Req.Test, __MODULE__}})
  end

  test "returns http error on non-200 response" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 503, "unavailable")
    end)

    assert {:error, {:http, 503}} = Weather.run(ctx())
  end

  for {code, expected} <- [
        {0, "CLEAR SKY"},
        {1, "MAINLY CLEAR"},
        {2, "PARTLY CLOUDY"},
        {3, "OVERCAST"},
        {45, "FOGGY"},
        {61, "RAIN"},
        {71, "SNOW"},
        {80, "RAIN SHOWERS"},
        {95, "THUNDERSTORM"}
      ] do
    test "WMO code #{code} renders as #{expected}" do
      response = put_in(@api_response, ["current", "weathercode"], unquote(code))

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, response)
      end)

      {:ok, text} = Weather.run(ctx())
      assert String.contains?(text, unquote(expected))
    end
  end
end
