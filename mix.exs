defmodule CounterEx.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/nyo16/CounterEx"

  def project do
    [
      app: :counter_ex,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "CounterEx",
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
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
      # Runtime
      {:telemetry, "~> 1.3"},

      # Dev and Test
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:benchee, "~> 1.3", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    """
    A high-performance Elixir library for managing counters with pluggable backends.
    Supports ETS, Erlang :atomics, and :counters modules with namespace organization.
    """
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["nyo16"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE.md CHANGELOG.md guides)
    ]
  end

  defp docs do
    [
      main: "CounterEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        "guides/migration.md": [title: "Migration Guide"],
        "guides/backends.md": [title: "Backend Comparison"]
      ],
      groups_for_modules: [
        Backends: [
          CounterEx.Backend,
          CounterEx.Backend.ETS,
          CounterEx.Backend.Atomics,
          CounterEx.Backend.Counters
        ]
      ]
    ]
  end
end
