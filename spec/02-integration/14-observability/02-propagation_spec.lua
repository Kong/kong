local helpers = require "spec.helpers"
local cjson = require "cjson"
local to_hex = require("resty.string").to_hex
local from_hex = require 'kong.observability.tracing.propagation.utils'.from_hex

local rand_bytes = require("kong.tools.rand").get_rand_bytes

local function gen_id(len)
  return to_hex(rand_bytes(len))
end


-- modifies the last byte of an ID
local function transform_bin_id(id, last_byte)
  if not id then
    return
  end
  local bytes = {string.byte(id, 1, #id)}
  bytes[#bytes] = string.byte(last_byte)
  return string.char(unpack(bytes))
end

local function generate_function_plugin_config(propagation_config, trace_id, span_id)
  local extract = propagation_config.extract or "nil"
  local inject = propagation_config.inject or "nil"
  local clear = propagation_config.clear or "nil"
  local default_format = propagation_config.default_format or "nil"

  return {
    access = {
      string.format([[
        local propagation = require 'kong.observability.tracing.propagation'
        local from_hex = require 'kong.observability.tracing.propagation.utils'.from_hex
        
        local function transform_bin_id(id, last_byte)
          if not id then
            return
          end
          local bytes = {string.byte(id, 1, #id)}
          bytes[#bytes] = string.byte(last_byte)
          return string.char(unpack(bytes))
        end

        propagation.propagate(
          propagation.get_plugin_params(
            {
              propagation = {
                extract        = %s,
                inject         = %s,
                clear          = %s,
                default_format = %s,
              }
            }
          ),
          function(ctx)
            -- create or modify the context so we can validate it later

            if not ctx.trace_id then
              ctx.trace_id = from_hex("%s")
            else
              ctx.trace_id = transform_bin_id(ctx.trace_id, from_hex("0"))
            end

            if not ctx.span_id then
              ctx.span_id = from_hex("%s")
              ngx.log(ngx.ERR, "generated span_id: " .. ctx.span_id)
            else
              ctx.span_id = transform_bin_id(ctx.span_id, from_hex("0"))
              ngx.log(ngx.ERR, "transformed span_id: " .. ctx.span_id)
            end

            if ctx.parent_id then
              ctx.span_id = transform_bin_id(ctx.parent_id, from_hex("0"))
              ngx.log(ngx.ERR, "transformed span_id: " .. ctx.span_id)
            end

            ctx.should_sample=true

            return ctx
          end
        )
      ]], extract, inject, clear, default_format, trace_id, span_id),
    },
  }
end

for _, strategy in helpers.each_strategy() do
  local proxy_client

  describe("tracing propagation spec #" .. strategy, function()

    describe("parsing incoming headers with multiple plugins", function ()
      local trace_id, span_id

      lazy_setup(function()
        trace_id = gen_id(16)
        span_id = gen_id(8)
        local bp, _ = assert(helpers.get_db_utils(strategy, {
          "routes",
          "plugins",
        }))

        local multi_plugin_route = bp.routes:insert({
          hosts = { "propagate.test" },
        })

        bp.plugins:insert({
          name = "pre-function",
          route = multi_plugin_route,
          config = generate_function_plugin_config({
            extract = "{}",               -- ignores incoming
            inject = '{ "preserve" }',    -- falls back to default
            default_format = '"b3-single"',      -- defaults to b3
          }, trace_id, span_id),
        })

        bp.plugins:insert({
          name = "post-function",
          route = multi_plugin_route,
          config = generate_function_plugin_config({
            extract = '{ "w3c", "b3" }',      -- reads b3
            inject = '{ "w3c" }',             -- and injects w3c
            default_format = "datadog",       -- default not used here
            clear = '{ "ot-tracer-spanid" }',     -- clears this header
          }),
        })

        helpers.start_kong({
          database = strategy,
          plugins = "bundled",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          untrusted_lua = "on",
        })
        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end
        helpers.stop_kong()
      end)

      it("propagates and clears as expected", function()
        local r = proxy_client:get("/", {
          headers = {
            ["ot-tracer-traceid"] = gen_id(16),
            ["ot-tracer-spanid"]  = gen_id(8),
            ["ot-tracer-sampled"] = "0",
            host = "propagate.test",
          },
        })

        local body = assert.response(r).has.status(200)
        local json = cjson.decode(body)

        assert.equals(trace_id .. "-" .. span_id .. "-1", json.headers.b3)
        local expected_trace_id = to_hex(transform_bin_id(from_hex(trace_id), from_hex("0")))
        local expected_span_id  = to_hex(transform_bin_id(from_hex(span_id),  from_hex("0")))
        assert.equals("00-" .. expected_trace_id .. "-" .. expected_span_id .. "-01", json.headers.traceparent)
        -- initial header remained unchanged
        assert.equals("0", json.headers["ot-tracer-sampled"])
        -- header configured to be cleared was cleared
        assert.is_nil(json.headers["ot-tracer-spanid"])
      end)
    end)
  end)
end
