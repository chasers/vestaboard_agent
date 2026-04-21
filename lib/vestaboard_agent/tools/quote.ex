defmodule VestaboardAgent.Tools.Quote do
  @moduledoc """
  Returns a quote from a local list, rotating by day.
  """

  @behaviour VestaboardAgent.Tool

  @quotes [
    "The only way to do great work is to love what you do. - Steve Jobs",
    "In the middle of difficulty lies opportunity. - Albert Einstein",
    "It does not matter how slowly you go as long as you do not stop. - Confucius",
    "Life is what happens when you're busy making other plans. - John Lennon",
    "The future belongs to those who believe in the beauty of their dreams. - Eleanor Roosevelt",
    "Strive not to be a success, but rather to be of value. - Albert Einstein",
    "You miss 100% of the shots you don't take. - Wayne Gretzky",
    "Whether you think you can or you think you can't, you're right. - Henry Ford",
    "The best time to plant a tree was 20 years ago. The second best time is now. - Chinese Proverb",
    "An unexamined life is not worth living. - Socrates",
    "Spread love everywhere you go. - Mother Teresa",
    "When you reach the end of your rope, tie a knot in it and hang on. - Franklin D. Roosevelt",
    "Always remember that you are absolutely unique. - Margaret Mead",
    "Do not go where the path may lead, go instead where there is no path. - Ralph Waldo Emerson",
    "You will face many defeats in life, but never let yourself be defeated. - Maya Angelou",
    "The greatest glory in living lies not in never falling, but in rising every time we fall. - Nelson Mandela",
    "In the end, it's not the years in your life that count. It's the life in your years. - Abraham Lincoln",
    "Never let the fear of striking out keep you from playing the game. - Babe Ruth",
    "Life is either a daring adventure or nothing at all. - Helen Keller",
    "Many of life's failures are people who did not realize how close they were to success. - Thomas Edison"
  ]

  @impl true
  def name, do: "quote"

  @impl true
  def run(context \\ %{}) do
    index = pick_index(context)
    {:ok, Enum.at(@quotes, index)}
  end

  def quotes, do: @quotes

  defp pick_index(context) do
    date =
      case Map.get(context, :now) do
        %DateTime{} = dt -> DateTime.to_date(dt)
        %Date{} = d -> d
        _ -> Date.utc_today()
      end

    rem(Date.to_gregorian_days(date), length(@quotes))
  end
end
