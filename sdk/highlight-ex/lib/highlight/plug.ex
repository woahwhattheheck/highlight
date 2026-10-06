defmodule Highlight.Plug do
  @moduledoc """
  A `Plug` that tags the current OpenTelemetry span with the Highlight
  session and request IDs from the `X-Highlight-Request` header.

      plug Highlight.Plug

  Add it after your server instrumentation (Bandit/Cowboy OTel) so the
  request span already exists when the plug runs. When no span is active
  the plug is a no-op.
  """

  @behaviour Plug

  alias OpenTelemetry.Tracer
  alias OpenTelemetry.Span

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Highlight.ErrorHandler.session_request_ids(conn) do
      {nil, nil} ->
        :ok

      {session_id, request_id} ->
        span_ctx = Tracer.current_span_ctx()

        if Span.is_valid(span_ctx) do
          Span.set_attributes(
            span_ctx,
            Highlight.span_attributes(
              Highlight.current_config() || %Highlight.Config{project_id: nil},
              session_id,
              request_id
            )
          )
        end
    end

    conn
  end
end
