defmodule Mix.Tasks.Test.E2e do
  @shortdoc "Run the end-to-end test suite against a real Vestaboard"
  @moduledoc """
  Runs all tests tagged `:e2e` against a live Vestaboard and real Anthropic API.

  Required environment variables:
    VESTABOARD_LOCAL_API_KEY  — local board API key
    ANTHROPIC_API_KEY         — Anthropic API key for LLM calls

  Optional:
    VESTABOARD_BASE_URL       — board address (default: http://vestaboard.local:7000)
    E2E_PACE_MS               — ms to sleep between tests (default: 1000)
    E2E_REPORT_FILE           — path to append JSONL results (default: none)

  Examples:
    mix test.e2e
    mix test.e2e test/e2e/03_http_chat_test.exs
    E2E_PACE_MS=500 mix test.e2e
    E2E_REPORT_FILE=/tmp/e2e.jsonl mix test.e2e
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    required = ["VESTABOARD_LOCAL_API_KEY", "ANTHROPIC_API_KEY"]
    missing = Enum.filter(required, &(System.get_env(&1) == nil))

    if missing != [] do
      Mix.shell().error("""

      ✗ Missing required environment variables:
        #{Enum.join(missing, "\n  ")}

      Export them first:
        export VESTABOARD_LOCAL_API_KEY=your_key
        export ANTHROPIC_API_KEY=sk-ant-...
        mix test.e2e
      """)

      exit({:shutdown, 1})
    end

    Mix.shell().info("Running E2E suite against #{System.get_env("VESTABOARD_BASE_URL", "http://vestaboard.local:7000")}")

    Mix.Task.run("test", [
      "--only", "e2e"
      | (if args == [], do: ["test/e2e"], else: args)
    ])
  end
end
