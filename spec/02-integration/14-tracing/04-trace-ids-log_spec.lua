local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"

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
    type = "ot",
    serializer_key = "ot",
    name = "ot-tracer-traceid",
    value = trace_id_hex_128,
    trace_id = trace_id_hex_128,
    trace_id_pattern = trace_id_hex_pattern,
  },
}

local function wait_json_log()
  helpers.wait_until(function()
    return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
  end, 10)

  local log = pl_file.read(FILE_LOG_PATH)
  return cjson.decode(pl_stringx.strip(log):match("%b{}"))
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

      local zipkin_route = bp.routes:insert({
        service = service,
        hosts = { "zipkin" },
      })

      bp.plugins:insert {
        name   = "file-log",
        config = {
          path   = FILE_LOG_PATH,
          reopen = true,
        },
      }

      bp.plugins:insert({
        name = "zipkin",
        route = { id = zipkin_route.id },
        config = {
          sample_ratio = 1,
          http_endpoint = "http://localhost:8080/v1/traces",
          header_type = config_header.type,
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
  end)
  end
end
