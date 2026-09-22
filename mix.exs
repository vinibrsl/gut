defmodule Gut.MixProject do
  use Mix.Project

  def project do
    [
      app: :gut,
      version: "0.1.0",
      elixir: ">= 1.14.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:jason, "~> 1.4"},
      {:req_llm, "~> 1.24", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.0", only: :test}
    ]
  end
end
