# Highlight Elixir SDK

The `highlight` package integrates Elixir applications with Highlight via
OpenTelemetry: error monitoring, `Logger` output as OTLP LogRecords, and
Phoenix/LiveView tracing, exported to `https://otel.highlight.io:4318` over
OTLP/HTTP.

## Installation

```elixir
defp deps do
  [
    {:highlight, "~> 0.2"}
  ]
end
```

Optional integrations are attached automatically when present:

```elixir
{:opentelemetry_phoenix, "~> 2.0"},
{:opentelemetry_bandit, "~> 0.3"},   # Bandit users
{:opentelemetry_cowboy, "~> 1.0"}    # Cowboy/Plug.Cowboy users
```

## Setup

Call `Highlight.init/1` once, early in `Application.start/2` — before your
endpoint starts serving traffic, so the exporter and instrumentation are
configured first:

```elixir
def start(_type, _args) do
  Highlight.init(project_id: System.fetch_env!("HIGHLIGHT_PROJECT_ID"))

  children = [
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Or with a config struct (equivalent):

```elixir
Highlight.init(%Highlight.Config{
  project_id: "your-project-id",
  service_name: "my-backend",
  service_version: "1.4.2"
})
```

`init/1` will:

- Point the OpenTelemetry exporter at `https://otel.highlight.io:4318`
  (OTLP/HTTP + protobuf) with the `x-highlight-project` header and a
  `highlight.project_id` resource attribute.
- Attach an OpenTelemetry `:logger` handler so `Logger` output is shipped
  as LogRecords on `v1/logs` (requires `opentelemetry_experimental`,
  included as a dependency).
- Attach `OpentelemetryPhoenix` — including LiveView spans — and
  Bandit/Cowboy server spans when those packages are in your deps.

## Recording exceptions

```elixir
try do
  risky_operation()
rescue
  e -> Highlight.record_exception(e)
end
```

`record_exception/5` accepts an exception or any thrown term and follows
the OpenTelemetry exception semantic convention. Optional `session_id` and
`request_id` arguments associate the error with a client session:

```elixir
Highlight.record_exception(exception, config, session_id, request_id)
```

## Phoenix error monitoring

Wire `Plug.ErrorHandler` errors into Highlight from your endpoint:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
  use Plug.ErrorHandler

  @impl Plug.ErrorHandler
  def handle_errors(conn, assigns) do
    Highlight.ErrorHandler.handle_errors(conn, assigns)
  end
end
```

Session/request IDs are read from the `X-Highlight-Request` header
(`<session_id>/<request_id>`), matching the client SDK convention.

To tag request spans with the same context on every request:

```elixir
plug Highlight.Plug
```

## Development

```sh
mix deps.get
mix compile
mix test
```

Requires Elixir `~> 1.13` and a compatible Erlang/OTP.
