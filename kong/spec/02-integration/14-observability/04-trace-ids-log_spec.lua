local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local pl_file = require "pl.file"

local strip = require("kong.tools.string").strip

local FILE_LOG_PATH = os.tmpname()

local fmt = string.format

local trace_id_hex_128 = "4bf92000000000000000000000000001"
local span_id = "0000000000000003"
local trace_id_hex_pattern = "^%x+$"

local tracing_headers = {
  {
    type = "b3",
    serializer_key = "b3",
    name = "X-B3-TraceId",
    value = trace_id_hex_128,
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
  {
    type = "b3-single",
    serializer_key = "b3",
    name = "b3",
    value = fmt("%s-%s-1-%s", trace_id_hex_128, span_id, span_id),
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
  {
    type = "jaeger",
    serializer_key = "jaeger",
    name = "uber-trace-id",
    value = fmt("%s:%s:%s:%s", trace_id_hex_128, span_id, span_id, "01"),
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
  {
    type = "w3c",
    serializer_key = "w3c",
    name = "traceparent",
    value = fmt("00-%s-%s-01", trace_id_hex_128, span_id),
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
  {
    type = "gcp",
    serializer_key = "gcp",
    name = "x-cloud-trace-context",
    value = trace_id_hex_128 .. "/1;o=1",
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
  {
    type = "aws",
    serializer_key = "aws",
    name = "x-amzn-trace-id",
    value = fmt("Root=1-%s-%s;Parent=%s;Sampled=%s",
      string.sub(trace_id_hex_128, 1, 8),
      string.sub(trace_id_hex_128, 9, #trace_id_hex_128),
      span_id,
      "1"
    ),
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
  {
    type = "ot",
    serializer_key = "ot",
    name = "ot-tracer-traceid",
    value = trace_id_hex_128,
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
}

local function wait_json_log()
  local json

  assert
      .with_timeout(10)
      .ignore_exceptions(true)
      .eventually(function()
        local data = assert(pl_file.read(FILE_LOG_PATH))

        data = strip(data)
        assert(#data > 0, "log file is empty")

        data = data:match("%b{}")
        assert(data, "log file does not contain JSON")

        json = cjson.decode(data)
      end)
      .has_no_error("log file contains a valid JSON entry")

  return json
end

for _, strategy in helpers.each_strategy() do
  local proxy_client

  for _, config_header in ipairs(tracing_headers) do
  describe("Trace IDs log serializer spec #" .. strategy, function()
    lazy_setup(function()
      local bp, _ = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }))

      local service = bp.services:insert()

      local otel_route = bp.routes:insert({
        service = service,
        hosts = { "otel" },
      })

      local zipkin_route = bp.routes:insert({
        service = service,
        hosts = { "zipkin" },
      })

      local otel_zipkin_route = bp.routes:insert({
        service = service,
        hosts = { "otel_zipkin" },
      })

      local otel_zipkin_route_2 = bp.routes:insert({
        service = service,
        hosts = { "otel_zipkin_2" },
      })


      bp.plugins:insert {
        name   = "file-log",
        config = {
          path   = FILE_LOG_PATH,
          reopen = true,
        },
      }

      bp.plugins:insert({
        name = "opentelemetry",
        route = { id = otel_route.id },
        config = {
          traces_endpoint = "http://localhost:8080/v1/traces",
          header_type = config_header.type,
        }
      })

      bp.plugins:insert({
        name = "opentelemetry",
        route = { id = otel_zipkin_route.id },
        config = {
          traces_endpoint = "http://localhost:8080/v1/traces",
          header_type = config_header.type,
        }
      })

      bp.plugins:insert({
        name = "opentelemetry",
        route = { id = otel_zipkin_route_2.id },
        config = {
          traces_endpoint = "http://localhost:8080/v1/traces",
          header_type = "jaeger",
        }
      })

      bp.plugins:insert({
        name = "zipkin",
        route = { id = zipkin_route.id },
        config = {
          sample_ratio = 1,
          http_endpoint = "http://localhost:8080/v1/traces",
          header_type = config_header.type,
        }
      })

      bp.plugins:insert({
        name = "zipkin",
        route = { id = otel_zipkin_route.id },
        config = {
          sample_ratio = 1,
          http_endpoint = "http://localhost:8080/v1/traces",
          header_type = config_header.type,
        }
      })

      bp.plugins:insert({
        name = "zipkin",
        route = { id = otel_zipkin_route_2.id },
        config = {
          sample_ratio = 1,
          http_endpoint = "http://localhost:8080/v1/traces",
          header_type = "ot",
        }
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
        tracing_instrumentations = "all",
        tracing_sampling_rate = 1,
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if proxy_client then
        proxy_client:close()
      end
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      os.remove(FILE_LOG_PATH)
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end

      os.remove(FILE_LOG_PATH)
    end)

    describe("with Opentelemetry", function()
      local default_type_otel = "w3c"

      it("contains only the configured trace ID type: " .. config_header.type .. 
         " + the default (w3c) with no tracing headers in the request", function()
        local r = proxy_client:get("/", {
          headers = {
            host = "otel",
          },
        })
        assert.response(r).has.status(200)
        local json_log = wait_json_log()
        assert.not_nil(json_log)

        -- contains the configured trace id type
        assert.matches(config_header.trace_id_pattern,
                       json_log.trace_id[config_header.serializer_key])
        -- contains the default trace id type (generated trace id)
        assert.matches(trace_id_hex_pattern,
                       json_log.trace_id[default_type_otel])

        -- does not contain other types
        for _, header in ipairs(tracing_headers) do
          local k = header.serializer_key
          if k ~= config_header.serializer_key and k ~= default_type_otel then
            assert.is_nil(json_log.trace_id[k])
          end
        end
      end)

      for _, req_header in ipairs(tracing_headers) do
        it("contains only the configured trace ID type (" .. config_header.type ..
           ") + the incoming (" .. req_header.type .. ")", function()
          if req_header.type == config_header.type then
            return
          end

          local r = proxy_client:get("/", {
            headers = {
              host = "otel",
              [req_header.name] = req_header.value,
            },
          })
          assert.response(r).has.status(200)
          local json_log = wait_json_log()
          assert.not_nil(json_log)

          -- contains the configured trace id type
          assert.matches(config_header.trace_id_pattern,
                         json_log.trace_id[config_header.serializer_key])
          -- contains the incoming trace id
          assert.equals(req_header.trace_id,
                        json_log.trace_id[req_header.serializer_key])

          -- does not contain other types
          for _, header in ipairs(tracing_headers) do
            local k = header.serializer_key
            if k ~= config_header.serializer_key and k ~= req_header.serializer_key then
              assert.is_nil(json_log.trace_id[k])
            end
          end
        end)
      end
    end)

    describe("with Zipkin", function()
      local default_type_zipkin = "b3"

      it("contains only the configured trace ID type: " .. config_header.type .. 
         " + the default (b3) with no tracing headers in the request", function()
        local r = proxy_client:get("/", {
          headers = {
            host = "zipkin",
          },
        })
        assert.response(r).has.status(200)
        local json_log = wait_json_log()
        assert.not_nil(json_log)

        -- contains the configured trace id type
        assert.matches(config_header.trace_id_pattern,
                       json_log.trace_id[config_header.serializer_key])
        -- contains the default trace id type (generated trace id)
        assert.matches(trace_id_hex_pattern,
                       json_log.trace_id[default_type_zipkin])

        -- does not contain other types
        for _, header in ipairs(tracing_headers) do
          local k = header.serializer_key
          if k ~= config_header.serializer_key and k ~= default_type_zipkin then
            assert.is_nil(json_log.trace_id[k])
          end
        end
      end)

      for _, req_header in ipairs(tracing_headers) do
        it("contains only the configured trace ID type (" .. config_header.type ..
           ") + the incoming (" .. req_header.type .. ")", function()
          if req_header.type == config_header.type then
            return
          end

          local r = proxy_client:get("/", {
            headers = {
              host = "zipkin",
              [req_header.name] = req_header.value,
            },
          })
          assert.response(r).has.status(200)
          local json_log = wait_json_log()
          assert.not_nil(json_log)

          -- contains the configured trace id type of the incoming trace id
          assert.matches(config_header.trace_id_pattern,
                         json_log.trace_id[config_header.serializer_key])
          -- contains the incoming trace id
          assert.equals(req_header.trace_id,
                        json_log.trace_id[req_header.serializer_key])

          -- does not contain other types
          for _, header in ipairs(tracing_headers) do
            local k = header.serializer_key
            if k ~= config_header.serializer_key and k ~= req_header.serializer_key then
              assert.is_nil(json_log.trace_id[k])
            end
          end
        end)
      end
    end)

    describe("with Otel + Zipkin", function()
      local default_type_zipkin = "b3"

      it("contains configured + zipkin types", function()
        local r = proxy_client:get("/", {
          headers = {
            host = "otel_zipkin",
          },
        })
        assert.response(r).has.status(200)
        local json_log = wait_json_log()
        assert.not_nil(json_log)

        -- contains the configured trace id type
        assert.matches(config_header.trace_id_pattern,
                       json_log.trace_id[config_header.serializer_key])
        -- contains the default trace id type (generated trace id)
        -- here default only applies to zipkin because Opentelemetry executes second
        -- and finds a tracing header (b3) in the request
        assert.matches(trace_id_hex_pattern,
                       json_log.trace_id[default_type_zipkin])

        -- does not contain other types
        for _, header in ipairs(tracing_headers) do
          local k = header.serializer_key
          if k ~= config_header.serializer_key and k ~= default_type_zipkin then
            assert.is_nil(json_log.trace_id[k])
          end
        end
      end)

      it("contains trace id types from both plugins", function()
        local r = proxy_client:get("/", {
          headers = {
            host = "otel_zipkin_2",
            traceparent = "00-" .. trace_id_hex_128 .. "-" .. span_id .. "-01",
          },
        })
        assert.response(r).has.status(200)
        local json_log = wait_json_log()
        assert.not_nil(json_log)

        -- contains the input (w3c) header's trace id format
        assert.matches(trace_id_hex_pattern,
                       json_log.trace_id.w3c)
        -- contains the jaeger header's trace id format (injected by otel)
        assert.matches(trace_id_hex_pattern,
                       json_log.trace_id.jaeger)
        -- contains the ot header's trace id format (injected by zipkin)
        assert.matches(trace_id_hex_pattern,
                       json_log.trace_id.ot)

        -- does not contain other types
        for _, header in ipairs(tracing_headers) do
          local k = header.serializer_key
          if k ~= "w3c" and k ~= "jaeger" and k ~= "ot" then
            assert.is_nil(json_log.trace_id[k])
          end
        end
      end)
    end)
  end)
  end
end
