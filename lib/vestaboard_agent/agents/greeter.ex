defmodule VestaboardAgent.Agents.Greeter do
  @moduledoc """
  Displays a time-appropriate greeting on the board.

  Triggered by prompts containing: greet, greeting, hello, good morning,
  good afternoon, good evening.
  """

  @behaviour VestaboardAgent.Agent

  alias VestaboardAgent.Tools.Greeting

  @impl true
  def name, do: "greeter"

  @impl true
  def keywords,
    do: ["greet", "greeting", "hello", "good morning", "good afternoon", "good evening"]

  @impl true
  def description, do: "Show a time-appropriate greeting on the board"

  @impl true
  def handle(_prompt, context) do
    ctx = Map.put_new(context, :now, DateTime.utc_now())
    Greeting.run(ctx)
  end
end
