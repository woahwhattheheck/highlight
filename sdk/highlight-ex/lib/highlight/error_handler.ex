defmodule Highlight.ErrorHandler do
  @moduledoc """
  Integration for `Plug.ErrorHandler` error monitoring in Phoenix/Plug
  applications.

  In your endpoint:

      defmodule MyAppWeb.Endpoint do
        use Phoenix.Endpoint, otp_app: :my_app
        use Plug.ErrorHandler

        @impl Plug.ErrorHandler
        def handle_errors(conn, assigns) do
          Highlight.ErrorHandler.handle_errors(conn, assigns)
        end
      end

  The Highlight session and request IDs are extracted from the
  `X-Highlight-Request` header (`<session_id>/<request_id>`) so captured
  errors are associated with the client session that produced them.
  """

  @highlight_request_header "x-highlight-request"

  @doc """
  Records `%{kind: kind, reason: reason, stack: stack}` as reported by
  `Plug.ErrorHandler` to Highlight, tagging the span with the Highlight
  session and request IDs from the request headers.
  """
  @spec handle_errors(Plug.Conn.t(), map()) :: :ok
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    {session_id, request_id} = session_request_ids(conn)
    exception = Exception.normalize(kind, reason, stack)
    Highlight.record_exception(exception, nil, session_id, request_id, stack)
    :ok
  end

  @doc """
  Parses the `X-Highlight-Request` header into `{session_id, request_id}`.
  Returns `{nil, nil}` when the header is absent or malformed.
  """
  @spec session_request_ids(Plug.Conn.t()) :: {String.t() | nil, String.t() | nil}
  def session_request_ids(conn) do
    case Plug.Conn.get_req_header(conn, @highlight_request_header) do
      [header | _] ->
        case String.split(header, "/", parts: 2) do
          [session_id, request_id] -> {session_id, request_id}
          _ -> {nil, nil}
        end

      [] ->
        {nil, nil}
    end
  end
end
