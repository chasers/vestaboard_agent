defmodule VestaboardAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :vestaboard_agent,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/e2e"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def cli do
    [preferred_envs: ["test.e2e": :test]]
  end

  def application do
    [
      mod: {VestaboardAgent.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:lua, "~> 0.4.0"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:quantum, "~> 3.0"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.0"},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
