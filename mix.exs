defmodule Gut.MixProject do
  use Mix.Project

  @source_url "https://github.com/vinibrsl/gut"

  def project do
    [
      app: :gut,
      version: "0.1.0",
      description: "Use LLM judgment in regular Elixir control flow.",
      source_url: @source_url,
      docs: [main: "readme", extras: ["README.md"]],
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => @source_url}
      ],
      elixir: ">= 1.18.0",
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [no_warn_undefined: [ReqLLM, ReqLLM.Output, ReqLLM.Response]],
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
      {:ex_doc, "~> 0.40", only: :docs, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.0", only: :test}
    ]
  end
end
