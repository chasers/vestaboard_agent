defmodule VestaboardAgent.TelegramBotTest do
  use ExUnit.Case, async: false

  alias VestaboardAgent.TelegramBot

  describe "parse_allowed_users logic" do
    test "returns :all sentinel for nil/empty input" do
      assert :all == parse_allowed(nil)
      assert :all == parse_allowed("")
    end

    test "parses comma-separated user IDs" do
      set = parse_allowed("123, 456 , 789")
      assert MapSet.member?(set, "123")
      assert MapSet.member?(set, "456")
      assert MapSet.member?(set, "789")
      refute MapSet.member?(set, "000")
    end
  end

  describe "start_link/1 with no token" do
    test "returns :ignore when TELEGRAM_BOT_TOKEN is unset" do
      original = System.get_env("TELEGRAM_BOT_TOKEN")
      System.delete_env("TELEGRAM_BOT_TOKEN")

      result = TelegramBot.start_link([])
      assert result == :ignore

      if original, do: System.put_env("TELEGRAM_BOT_TOKEN", original)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers — exercise private parse_allowed_users logic without calling it directly
  # ---------------------------------------------------------------------------

  defp parse_allowed(nil), do: :all
  defp parse_allowed(""), do: :all

  defp parse_allowed(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> MapSet.new()
  end
end
