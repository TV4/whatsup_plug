defmodule Whatsup.MixProject do
  use Mix.Project

  def project do
    [
      app: :whatsup_plug,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: ["test.watch": :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.8"},
      {:jason, "~> 1.1"},
      {:httpoison, "~> 1.6"},
      {:mox, "~> 0.5", only: :test},
      {:mix_test_watch, "~> 0.9", only: :test}
    ]
  end
end
