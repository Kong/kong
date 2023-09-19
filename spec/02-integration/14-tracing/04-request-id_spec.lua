local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"
local pl_file = require "pl.file"

local to_hex = require "resty.string".to_hex

local TEST_CONF = helpers.test_conf


local function get_request_id_from_logs(log_pattern)
  local request_id
  log_pattern = log_pattern or ""
  assert
  .eventually(function()
    local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)
    if not logs then
      return false
    end

    local _
    _, _, request_id = logs:find(log_pattern .. ".-, request_id: \"(%x+)\"")
    return request_id ~= nil
  end)
  .with_timeout(5)
  .ignore_exceptions(true)
  .is_truthy()
  return request_id
end


for _, strategy in helpers.each_strategy() do
describe("Request ID error log tests #" .. strategy, function()
  local service
  local proxy_client
  local log_pattern = "hello"
  local error_pattern = "error%-generator"

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" }, { "error-generator" })

    service = bp.services:insert()

    bp.routes:insert({
      service = service,
      hosts = { "no_plugins" },
    })

    local otel_route = bp.routes:insert({
      service = service,
      hosts = { "otel_host" },
    })

    local zipkin_route = bp.routes:insert({
      service = service,
      hosts = { "zipkin_host" },
    })

    local correlation_route = bp.routes:insert({
      service = service,
      hosts = { "correlation_host" },
    })

    local otel_correlation_route = bp.routes:insert({
      service = service,
      hosts = { "otel_correlation_host" },
    })

    local zipkin_correlation_route = bp.routes:insert({
      service = service,
      hosts = { "zipkin_correlation_host" },
    })

    local zipkin_otel_correlation_route = bp.routes:insert({
      service = service,
      hosts = { "zipkin_otel_correlation_host" },
    })

    local runtime_error_route = bp.routes:insert({
      service = service,
      hosts = { "runtime_error_host" },
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = { id = otel_route.id },
      config = {
        endpoint = "http://localhost:8080/v1/traces",
      }
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = { id = otel_correlation_route.id },
      config = {
        endpoint = "http://localhost:8080/v1/traces",
      }
    })

    bp.plugins:insert({
      name = "opentelemetry",
      route = { id = zipkin_otel_correlation_route.id },
      config = {
        endpoint = "http://localhost:8080/v1/traces",
      }
    })

    bp.plugins:insert {
      name = "correlation-id",
      route = { id = correlation_route.id },
    }

    bp.plugins:insert {
      name = "correlation-id",
      route = { id = otel_correlation_route.id },
    }

    bp.plugins:insert {
      name = "correlation-id",
      route = { id = zipkin_correlation_route.id },
    }

    bp.plugins:insert {
      name = "correlation-id",
      route = { id = zipkin_otel_correlation_route.id },
    }

    bp.plugins:insert {
      name = "zipkin",
      route = { id = zipkin_route.id },
      config = {
        sample_ratio = 1,
        default_header_type = "w3c",
      }
    }

    bp.plugins:insert {
      name = "zipkin",
      route = { id = zipkin_correlation_route.id },
      config = {
        sample_ratio = 1,
        default_header_type = "w3c",
      }
    }

    bp.plugins:insert {
      name = "zipkin",
      route = { id = zipkin_otel_correlation_route.id },
      config = {
        sample_ratio = 1,
        default_header_type = "w3c",
      }
    }

    bp.plugins:insert({
      name = "post-function",
      config = {
        access = { "ngx.log(ngx.INFO, \"" .. log_pattern .. "\")" }
      }
    })

    bp.plugins:insert({
      name = "error-generator",
      route = { id = runtime_error_route.id },
      config = {
        header_filter = true,
      }
    })

    helpers.start_kong({
      database = strategy,
      plugins = "bundled, error-generator",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })
  end)

  before_each(function()
    helpers.clean_logfile()
    proxy_client = helpers.proxy_client()
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    if proxy_client then
      proxy_client:close()
    end
  end)

  it("generates a new request ID when no tracing plugins are configured", function()
    local rid = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        ["Host"] = "no_plugins",
        ["Kong-Request-ID"] = rid,
        traceparent = "00-" .. rid .. "-00f067aa0ba902b7-01",
      }
    })

    local req_id = get_request_id_from_logs(log_pattern)
    assert.matches("^[a-f0-9]+$", req_id)
    assert.is_not.equal(req_id, rid)
  end)

  it("updates request_id with trace_id from incoming header when opentelemetry is configured", function()
    local rid = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        host = "otel_host",
        traceparent = "00-" .. rid .. "-00f067aa0ba902b7-01",
      },
    })

    assert.equals(rid, get_request_id_from_logs(log_pattern))
  end)

  it("updates request_id with trace_id from incoming header when zipkin is configured", function()
    local rid = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        host = "zipkin_host",
        traceparent = "00-" .. rid .. "-00f067aa0ba902b7-01",
      },
    })

    assert.equals(rid, get_request_id_from_logs(log_pattern))
  end)

  it("updates request_id with correlation ID when correlation-id is configured", function()
    local rid = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        ["Host"] = "correlation_host",
        ["Kong-Request-ID"] = rid,
      }
    })

    assert.equals(rid, get_request_id_from_logs(log_pattern))
  end)

  it("correlation ID takes precedence over Opentelemetry to set request_id", function()
    local rid_corr = to_hex(utils.get_rand_bytes(16))
    local rid_otel = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        ["Host"] = "otel_correlation_host",
        ["Kong-Request-ID"] = rid_corr,
        traceparent = "00-" .. rid_otel .. "-00f067aa0ba902b7-01",
      }
    })

    local rid_from_logs = get_request_id_from_logs(log_pattern)
    assert.equals(rid_corr, rid_from_logs)
    assert.not_equal(rid_otel, rid_from_logs)
  end)

  it("correlation ID takes precedence over Zipkin to set request_id", function()
    local rid_corr = to_hex(utils.get_rand_bytes(16))
    local rid_zipkin = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        ["Host"] = "zipkin_correlation_host",
        ["Kong-Request-ID"] = rid_corr,
        traceparent = "00-" .. rid_zipkin .. "-00f067aa0ba902b7-01",
      }
    })

    local rid_from_logs = get_request_id_from_logs(log_pattern)
    assert.equals(rid_corr, rid_from_logs)
    assert.not_equal(rid_zipkin, rid_from_logs)
  end)

  it("correlation ID takes precedence over Zipkin and OTel to set request_id", function()
    local rid_corr = to_hex(utils.get_rand_bytes(16))
    local rid_trace = to_hex(utils.get_rand_bytes(16))
    proxy_client:get("/", {
      headers = {
        ["Host"] = "zipkin_otel_correlation_host",
        ["Kong-Request-ID"] = rid_corr,
        traceparent = "00-" .. rid_trace .. "-00f067aa0ba902b7-01",
      }
    })

    local rid_from_logs = get_request_id_from_logs(log_pattern)
    assert.equals(rid_corr, rid_from_logs)
    assert.not_equal(rid_trace, rid_from_logs)
  end)

  it("logs a request ID in the output of runtime errors", function()
    pcall(proxy_client.get, proxy_client, "/", {
      headers = {
        ["Host"] = "runtime_error_host",
      }
    })

    local req_id = get_request_id_from_logs(error_pattern)
    assert.matches("^[a-f0-9]+$", req_id)
  end)
end)
end
