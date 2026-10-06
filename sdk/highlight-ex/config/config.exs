import Config

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  resource_detectors: [:otel_resource_env_var, :otel_resource_app_env]

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "https://otel.highlight.io:4318"

if config_env() == :test do
  # Never export over the network in tests.
  config :opentelemetry, traces_exporter: :none
  config :opentelemetry_exporter, otlp_endpoint: "http://localhost:1"
end
