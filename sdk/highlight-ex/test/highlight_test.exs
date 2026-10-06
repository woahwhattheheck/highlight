defmodule HighlightTest do
  use ExUnit.Case
  doctest Highlight

  setup do
    _ = :logger.remove_handler(:highlight_log_handler)
    :ok
  end

  test "init stores config and sets exporter endpoint + project header" do
    :ok =
      Highlight.init(
        project_id: "test-project",
        service_name: "test-service",
        attach_log_handler: false,
        instrument_phoenix: false
      )

    assert %Highlight.Config{project_id: "test-project", service_name: "test-service"} =
             Highlight.current_config()

    assert {"x-highlight-project", "test-project"} in Application.get_env(
             :opentelemetry_exporter,
             :otlp_headers
           )

    assert Application.get_env(:opentelemetry_exporter, :otlp_protocol) == :http_protobuf
    assert Application.get_env(:opentelemetry, :traces_exporter) == :otlp

    resource = Application.get_env(:opentelemetry, :resource)
    assert resource["highlight.project_id"] == "test-project"
    assert resource["service.name"] == "test-service"
    assert resource["telemetry.sdk.name"] == "opentelemetry"
  end

  test "init reads project_id from app env when not passed" do
    Application.put_env(:highlight, :project_id, "env-project")
    :ok = Highlight.init(attach_log_handler: false, instrument_phoenix: false)
    assert Highlight.current_config().project_id == "env-project"
  after
    Application.delete_env(:highlight, :project_id)
  end

  test "init attaches the otel logger handler for LogRecords" do
    :ok = Highlight.init(project_id: "p", instrument_phoenix: false)
    assert :highlight_log_handler in :logger.get_handler_ids()

    assert {:ok, config} = :logger.get_handler_config(:highlight_log_handler)
    assert config.module == :otel_log_handler
  end

  test "record_exception accepts an exception struct" do
    :ok = Highlight.init(project_id: "p", attach_log_handler: false, instrument_phoenix: false)

    try do
      raise ArgumentError, "bad arg"
    rescue
      e -> assert :ok = Highlight.record_exception(e, nil, "sess", "req", __STACKTRACE__)
    end
  end

  test "record_exception normalizes thrown values" do
    :ok = Highlight.init(project_id: "p", attach_log_handler: false, instrument_phoenix: false)

    try do
      throw("unexpected error")
    catch
      e -> assert :ok = Highlight.record_exception(e, %Highlight.Config{project_id: "p"})
    end
  end

  test "record_exception works without init using defaults" do
    :persistent_term.erase({Highlight, :config})
    assert :ok = Highlight.record_exception(%RuntimeError{message: "x"})
  end

  test "session_request_ids parses the X-Highlight-Request header" do
    conn = %Plug.Conn{req_headers: [{"x-highlight-request", "sess123/req456"}]}
    assert {"sess123", "req456"} = Highlight.ErrorHandler.session_request_ids(conn)

    conn2 = %Plug.Conn{req_headers: []}
    assert {nil, nil} = Highlight.ErrorHandler.session_request_ids(conn2)

    conn3 = %Plug.Conn{req_headers: [{"x-highlight-request", "nopair"}]}
    assert {nil, nil} = Highlight.ErrorHandler.session_request_ids(conn3)
  end
end
