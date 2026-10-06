defmodule Highlight.MixProject do
  use Mix.Project

  def project do
    [
      app: :highlight,
      version: "0.2.0",
      description: "Highlight Elixir SDK for capturing logs, spans and metrics",
      elixir: "~> 1.13",
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        otel_getting_started: [
          version: "0.0.1",
          applications: [opentelemetry: :temporary, otel_getting_started: :permanent]
        ]
      ]
    ]
  end

  def package do
    [
      files: ["config", "lib", "mix.exs", "README.md"],
      maintainers: ["Vadim Korolik <vadim@highlight.io>"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/highlight/highlight"}
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:telemetry, "~> 1.0"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.10"},
      # Experimental OpenTelemetry logs support (`otel_log_handler`); ships
      # Logger output to the OTLP `v1/logs` endpoint.
      {:opentelemetry_experimental, "~> 0.6.0"},
      # Optional integrations; detected and attached by `Highlight.init/1`
      # when present in the host application.
      {:plug, "~> 1.14", optional: true},
      {:opentelemetry_phoenix, "~> 2.0", optional: true},
      {:opentelemetry_bandit, "~> 0.3", optional: true},
      {:opentelemetry_cowboy, "~> 1.0", optional: true}
    ]
  end
end
