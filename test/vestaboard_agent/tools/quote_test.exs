defmodule VestaboardAgent.Tools.QuoteTest do
  use ExUnit.Case, async: true

  alias VestaboardAgent.Tools.Quote

  @fixed_dt ~U[2024-06-15 12:00:00Z]

  test "name/0 returns quote" do
    assert Quote.name() == "quote"
  end

  test "run/1 returns {:ok, string}" do
    assert {:ok, text} = Quote.run(%{now: @fixed_dt})
    assert is_binary(text)
    assert String.length(text) > 0
  end

  test "returns a quote from the known list" do
    {:ok, text} = Quote.run(%{now: @fixed_dt})
    assert text in Quote.quotes()
  end

  test "returns the same quote for the same date" do
    ctx = %{now: @fixed_dt}
    {:ok, first} = Quote.run(ctx)
    {:ok, second} = Quote.run(ctx)
    assert first == second
  end

  test "returns a different quote for a different date" do
    quotes =
      for day <- 1..length(Quote.quotes()) do
        dt = %DateTime{
          year: 2024,
          month: 1,
          day: 1,
          hour: 0,
          minute: 0,
          second: 0,
          time_zone: "Etc/UTC",
          zone_abbr: "UTC",
          utc_offset: 0,
          std_offset: 0
        }

        shifted = DateTime.add(dt, (day - 1) * 86_400, :second)
        {:ok, text} = Quote.run(%{now: shifted})
        text
      end

    assert length(Enum.uniq(quotes)) == length(Quote.quotes())
  end

  test "accepts a Date in context" do
    {:ok, text} = Quote.run(%{now: ~D[2024-06-15]})
    assert is_binary(text)
    assert text in Quote.quotes()
  end

  test "defaults to today when no :now in context" do
    assert {:ok, text} = Quote.run(%{})
    assert text in Quote.quotes()
  end

  test "defaults to today when called with no args" do
    assert {:ok, text} = Quote.run()
    assert text in Quote.quotes()
  end
end
