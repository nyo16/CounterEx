defmodule CounterEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :counter_ex,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "CounterEx",
      source_url: "https://github.com/nyo16/CounterEx",
      docs: [
        main: "CounterEx",
        extras: ["README.md"]
      ]
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
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:benchee, "~> 1.0"}
    ]
  end
end
