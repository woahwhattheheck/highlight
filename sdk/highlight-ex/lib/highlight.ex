defmodule Highlight do
  @moduledoc """
  Highlight SDK for Elixir: error monitoring, logging and tracing backed by
  OpenTelemetry, exporting OTLP/HTTP to `https://otel.highlight.io:4318`.

  ## Usage

      Highlight.init(project_id: "<PROJECT_ID>")

      # or
      Highlight.init(%Highlight.Config{project_id: "<PROJECT_ID>"})

  `init/1` configures the OpenTelemetry exporters, attaches a `:logger`
  handler that ships `Logger` output as LogRecords to `v1/logs`, and
  attaches Phoenix/LiveView + web-server instrumentation when the optional
  `:opentelemetry_phoenix`, `:opentelemetry_bandit` or
  `:opentelemetry_cowboy` packages are present.

  Exceptions are recorded following the OpenTelemetry exception reporting
  specification:

      try do
        risky()
      rescue
        e -> Highlight.record_exception(e)
      end
  """

  require OpenTelemetry.Tracer, as: Tracer
  alias OpenTelemetry.Span
  require Logger

  @highlight_project_header "x-highlight-project"
  @log_handler_id :highlight_log_handler
  @config_key {__MODULE__, :config}

  defmodule Config do
    @moduledoc """
    Configuration for the Highlight SDK.

    * `:project_id` - Highlight project ID. Required for data to be routed
      to a project; sent as the `x-highlight-project` exporter header and
      as the `highlight.project_id` resource/record attribute.
    * `:service_name`, `:service_version` - OTLP resource attributes.
    * `:otlp_endpoint` - OTLP/HTTP base endpoint. Defaults to the Highlight
      collector at `https://otel.highlight.io:4318`.
    * `:attach_log_handler` - attach the OpenTelemetry `:logger` handler so
      `Logger` output is exported as LogRecords on `v1/logs`. Default true.
    * `:instrument_phoenix` - attach `OpentelemetryPhoenix` (with LiveView
      spans) and the Bandit/Cowboy server spans when those optional
      packages are present. Default true.
    """

    @enforce_keys [:project_id]
    defstruct project_id: nil,
              service_name: nil,
              service_version: nil,
              otlp_endpoint: "https://otel.highlight.io:4318",
              attach_log_handler: true,
              instrument_phoenix: true
  end

  @doc """
  Initialize the Highlight SDK.

  Accepts a `%Highlight.Config{}`, a keyword list, or nothing (in which case
  `config :highlight, :project_id` is read). Call once, early in
  `Application.start/2`, before traffic is served.
  """
  @spec init(Config.t() | keyword()) :: :ok
  def init(config \\ []) do
    config = resolve_config(config)
    :persistent_term.put(@config_key, config)
    configure_opentelemetry(config)
    {:ok, _} = Application.ensure_all_started(:opentelemetry)
    if config.attach_log_handler, do: attach_log_handler()
    maybe_instrument_phoenix(config)
    :ok
  end

  @doc "The config stored by the most recent `init/1` call, or nil."
  @spec current_config() :: Config.t() | nil
  def current_config, do: :persistent_term.get(@config_key, nil)

  defp resolve_config(%Config{} = config), do: config

  defp resolve_config(opts) when is_list(opts) do
    opts = Keyword.put_new(opts, :project_id, Application.get_env(:highlight, :project_id))
    struct!(Config, opts)
  end

  defp configure_opentelemetry(%Config{} = config) do
    Application.put_env(:opentelemetry, :span_processor, :batch)
    Application.put_env(:opentelemetry, :traces_exporter, :otlp)

    Application.put_env(:opentelemetry, :resource_detectors, [
      :otel_resource_env_var,
      :otel_resource_app_env
    ])

    Application.put_env(:opentelemetry_exporter, :otlp_protocol, :http_protobuf)
    Application.put_env(:opentelemetry_exporter, :otlp_endpoint, config.otlp_endpoint)

    existing_headers = Application.get_env(:opentelemetry_exporter, :otlp_headers, [])

    headers =
      existing_headers
      |> Enum.reject(fn {k, _v} -> String.downcase(to_string(k)) == @highlight_project_header end)
      |> Kernel.++([{@highlight_project_header, to_string(config.project_id)}])

    Application.put_env(:opentelemetry_exporter, :otlp_headers, headers)

    resource =
      %{}
      |> maybe_put("highlight.project_id", config.project_id)
      |> maybe_put("service.name", config.service_name)
      |> maybe_put("service.version", config.service_version)
      |> Map.put("telemetry.sdk.language", "erlang")
      |> Map.put("telemetry.sdk.name", "opentelemetry")
      |> Map.put("telemetry.sdk.version", otel_sdk_version())

    existing_resource =
      case Application.get_env(:opentelemetry, :resource, %{}) do
        m when is_map(m) -> m
        l when is_list(l) -> Map.new(l)
      end

    Application.put_env(
      :opentelemetry,
      :resource,
      Map.merge(existing_resource, resource)
    )
  end

  defp otel_sdk_version do
    case Application.spec(:opentelemetry, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp attach_log_handler do
    case Application.ensure_all_started(:opentelemetry_experimental) do
      {:ok, _} ->
        # re-init refreshes the handler config (e.g. a changed endpoint)
        _ = :logger.remove_handler(@log_handler_id)

        :logger.add_handler(@log_handler_id, :otel_log_handler, %{
          level: :info,
          exporter: {:opentelemetry_exporter, %{protocol: :http_protobuf}}
        })

      {:error, reason} ->
        Logger.warning(
          "highlight: opentelemetry_experimental unavailable, " <>
            "console logs will not be exported as LogRecords: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp maybe_instrument_phoenix(%Config{instrument_phoenix: false}), do: :ok

  defp maybe_instrument_phoenix(%Config{instrument_phoenix: true}) do
    if Code.ensure_loaded?(OpentelemetryPhoenix) do
      adapter = if Code.ensure_loaded?(OpentelemetryBandit), do: :bandit, else: :cowboy2
      OpentelemetryPhoenix.setup(adapter: adapter, liveview: true)

      cond do
        Code.ensure_loaded?(OpentelemetryBandit) -> OpentelemetryBandit.setup()
        Code.ensure_loaded?(:opentelemetry_cowboy) -> :opentelemetry_cowboy.setup()
        true -> :ok
      end
    end

    :ok
  end

  @doc """
  Records an exception on a `highlight-ctx` span, following the
  OpenTelemetry exception reporting semantic convention.

  `config` may be omitted to reuse the config stored by `init/1`.
  `session_id` and `request_id` carry the Highlight context (normally
  extracted from the `X-Highlight-Request` header). `stacktrace` should be
  the original `__STACKTRACE__`; when omitted the current process stacktrace
  is used.

  Returns `:ok`.

  ## Examples

      try do
        risky()
      rescue
        e -> Highlight.record_exception(e)
      end

      Highlight.record_exception(exception, config, "session_id", "request_id")
  """
  @spec record_exception(
          term(),
          Config.t() | nil,
          String.t() | nil,
          String.t() | nil,
          Exception.stacktrace() | nil
        ) :: :ok
  def record_exception(
        exception,
        config \\ nil,
        session_id \\ nil,
        request_id \\ nil,
        stacktrace \\ nil
      ) do
    config = config || current_config() || %Config{project_id: nil}
    exception = normalize_exception(exception, stacktrace)

    attributes =
      span_attributes(config, session_id, request_id)

    Tracer.with_span "highlight-ctx", %{attributes: attributes} do
      span_ctx = Tracer.current_span_ctx()
      Tracer.set_status(:error, Exception.message(exception))
      Span.record_exception(span_ctx, exception, stacktrace, [])
    end

    :ok
  end

  @doc false
  def span_attributes(%Config{} = config, session_id, request_id) do
    []
    |> maybe_put_attr(:"highlight.project_id", config.project_id)
    |> maybe_put_attr(:"highlight.session_id", session_id)
    |> maybe_put_attr(:"highlight.trace_id", request_id)
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, key, value), do: [{key, value} | attrs]

  defp normalize_exception(%{__exception__: true} = exception, _stacktrace), do: exception

  defp normalize_exception(exception, stacktrace),
    do: Exception.normalize(:error, exception, stacktrace || [])
end
