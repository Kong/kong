local helpers = require "spec.helpers"
local cjson = require "cjson"
local to_hex = require "resty.string".to_hex
local get_rand_bytes = require("kong.tools.rand").get_rand_bytes

local fmt = string.format
local W3C_TRACE_ID_HEX_LEN = 32


local function gen_trace_id(traceid_byte_count)
  return to_hex(get_rand_bytes(traceid_byte_count))
end


local function to_id_len(id, len)
  if #id < len then
    return string.rep('0', len - #id) .. id
  elseif #id > len then
    return string.sub(id, -len)
  end

  return id
end


local function gen_span_id()
  return to_hex(get_rand_bytes(8))
end


for _, strategy in helpers.each_strategy() do
for _, traceid_byte_count in ipairs({ 8, 16 }) do
describe("http integration tests with zipkin server (no http_endpoint) [#"
         .. strategy .. "] traceid_byte_count: "
         .. traceid_byte_count, function()

  local service
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" })

    -- enable zipkin plugin globally pointing to mock server
    bp.plugins:insert({
      name = "zipkin",
      -- enable on TCP as well (by default it is only enabled on http, https, grpc, grpcs)
      protocols = { "http", "https", "tcp", "tls", "grpc", "grpcs" },
      config = {
        sample_ratio = 1,
        traceid_byte_count = traceid_byte_count,
        static_tags = {
          { name = "static", value = "ok" },
        },
        header_type = "w3c", -- will always add w3c "traceparent" header
      }
    })

    service = bp.services:insert()

    -- kong (http) mock upstream
    bp.routes:insert({
      service = service,
      hosts = { "http-route" },
    })

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("propagates tracing headers (b3 request)", function()
    local trace_id = gen_trace_id(traceid_byte_count)
    local r = proxy_client:get("/", {
      headers = {
        ["x-b3-sampled"] = "1",
        ["x-b3-traceid"] = trace_id,
        host  = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.equals(trace_id, json.headers["x-b3-traceid"])
    assert.matches("00%-" .. to_id_len(trace_id, W3C_TRACE_ID_HEX_LEN) .. "%-%x+-01", json.headers.traceparent)
  end)

  describe("propagates tracing headers (b3-single request)", function()
    it("with parent_id", function()
      local trace_id = gen_trace_id(traceid_byte_count)
      local span_id = gen_span_id()
      local parent_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-%s-%s", trace_id, span_id, "1", parent_id),
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-1%-%x+", json.headers.b3)
      assert.matches("00%-" .. to_id_len(trace_id, W3C_TRACE_ID_HEX_LEN) .. "%-%x+-01", json.headers.traceparent)
    end)

    it("without parent_id", function()
      local trace_id = gen_trace_id(traceid_byte_count)
      local span_id = gen_span_id()

      local r = proxy_client:get("/", {
        headers = {
          b3 = fmt("%s-%s-1", trace_id, span_id),
          host = "http-route",
        },
      })
      local body = assert.response(r).has.status(200)
      local json = cjson.decode(body)
      assert.matches(trace_id .. "%-%x+%-1%-%x+", json.headers.b3)
      assert.matches("00%-" .. to_id_len(trace_id, W3C_TRACE_ID_HEX_LEN) .. "%-%x+-01", json.headers.traceparent)
    end)
  end)

  it("propagates w3c tracing headers", function()
    local trace_id = gen_trace_id(16) -- w3c only admits 16-byte trace_ids
    local parent_id = gen_span_id()

    local r = proxy_client:get("/", {
      headers = {
        traceparent = fmt("00-%s-%s-01", trace_id, parent_id),
        host = "http-route"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    assert.matches("00%-" .. to_id_len(trace_id, W3C_TRACE_ID_HEX_LEN) .. "%-%x+-01", json.headers.traceparent)
  end)

  it("propagates jaeger tracing headers", function()
    local trace_id = gen_trace_id(traceid_byte_count)
    local span_id = gen_span_id()
    local parent_id = gen_span_id()

    local r = proxy_client:get("/", {
      headers = {
        ["uber-trace-id"] = fmt("%s:%s:%s:%s", trace_id, span_id, parent_id, "1"),
        host = "http-route"
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)
    local expected_len = traceid_byte_count * 2

    -- Trace ID is left padded with 0 for assert
    assert.matches( ('0'):rep(expected_len-#trace_id) .. trace_id .. ":%x+:" .. span_id .. ":01", json.headers["uber-trace-id"])
  end)

  it("propagates ot headers", function()
    local trace_id = gen_trace_id(traceid_byte_count)
    local span_id = gen_span_id()
    local r = proxy_client:get("/", {
      headers = {
        ["ot-tracer-traceid"] = trace_id,
        ["ot-tracer-spanid"] = span_id,
        ["ot-tracer-sampled"] = "1",
        host = "http-route",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    local expected_len = traceid_byte_count * 2
    assert.equals(to_id_len(trace_id, expected_len), json.headers["ot-tracer-traceid"])
  end)
end)
end

describe("global plugin doesn't overwrites", function()
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, { "services", "routes", "plugins" })

    -- enable zipkin plugin globally pointing to mock server
    bp.plugins:insert({
      name = "zipkin",
      config = {
        sample_ratio = 1,
        header_type = "b3-single",
        default_header_type = "b3-single",
      }
    })

    local service = bp.services:insert()

    -- kong (http) mock upstream
    local route = bp.routes:insert({
      service = service,
      hosts = { "http-route-with-plugin" },
    })

    bp.routes:insert({
      service = service,
      hosts = { "http-service-with-plugin" },
    })

    bp.plugins:insert({
      route = route,
      name = "zipkin",
      config = {
        sample_ratio = 0,
        header_type = "b3",
        default_header_type = "b3",
      },
    })

    bp.plugins:insert({
      service = service,
      name = "zipkin",
      config = {
        sample_ratio = 0,
        header_type = "w3c",
        default_header_type = "w3c",
      },
    })

    helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    proxy_client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  -- service plugin overrides global plugin
  it("service-specific plugin", function()
    local r = proxy_client:get("/", {
      headers = {
        host = "http-service-with-plugin",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    assert.is_nil(json.headers.b3)
    assert.matches("00%-%x+-%x+-00", json.headers.traceparent)
  end)

  -- route plugin overrides service plugin and global plugin
  it("route-specific plugin", function()
    local r = proxy_client:get("/", {
      headers = {
        host = "http-route-with-plugin",
      },
    })
    local body = assert.response(r).has.status(200)
    local json = cjson.decode(body)

    assert.is_nil(json.headers.b3)
    assert.not_nil(json.headers["x-b3-traceid"])
    assert.equal("0", json.headers["x-b3-sampled"])
  end)
end)
end
