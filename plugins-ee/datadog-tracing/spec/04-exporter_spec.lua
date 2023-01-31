-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"
require "kong.plugins.datadog-tracing.encoder"
local msgpack = require "MessagePack"
local bn = require "resty.openssl.bn"
local binstring = require("luassert.formatters.binarystring")

local table_merge = utils.table_merge
local HTTP_SERVER_PORT = helpers.get_available_port()
local PROXY_PORT = 9000

for _, strategy in helpers.each_strategy() do
  describe("datadog-tracing exporter #" .. strategy, function()
    local bp

    -- helpers
    local function setup_instrumentations(types, config, fixtures)
      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         paths = { "/" }})

      bp.plugins:insert({
        name = "datadog-tracing",
        config = table_merge({
          endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT,
          batch_flush_delay = 0, -- report immediately
        }, config)
      })

      assert(helpers.start_kong({
        proxy_listen = "0.0.0.0:" .. PROXY_PORT,
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "datadog-tracing",
        opentelemetry_tracing = types,
      }, nil, nil, fixtures))
    end

    describe("valid #http request", function ()
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "datadog-tracing" }))

        setup_instrumentations("all")
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        helpers.kill_http_server(HTTP_SERVER_PORT)
      end)

      it("works", function ()
        local headers, body
        helpers.wait_until(function()
          local thread = helpers.http_server(HTTP_SERVER_PORT, { timeout = 10 })
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
          })
          assert.res_status(200, r)

          -- close client connection
          cli:close()

          local ok
          ok, headers, body = thread:join()

          return ok
        end, 10)

        assert.is_string(body)

        local idx = tablex.find(headers, "Content-Type: application/msgpack")
        assert.not_nil(idx, headers)

        local decoded = assert(msgpack.unpack(body))
        assert.not_nil(decoded)

        local root_span = decoded[1][1]
        -- default tags
        assert.same("none", root_span.meta.env)
        assert.same("mock-service", root_span.meta["kong.service_name"])
      end)
    end)

    describe("#propagation", function ()
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "datadog-tracing" }))

        setup_instrumentations("request")
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        helpers.kill_http_server(HTTP_SERVER_PORT)
      end)

      setup(function()
        assert:add_formatter(binstring)
      end)

      teardown(function()
        assert:remove_formatter(binstring)
      end)

      it("#propagate datadog headers", function ()
        local trace_id = utils.get_rand_bytes(8)
        local parent_id = utils.get_rand_bytes(8)

        local headers, body
        helpers.wait_until(function()
          local thread = helpers.http_server(HTTP_SERVER_PORT, { timeout = 10 })
          local cli = helpers.proxy_client(7000, PROXY_PORT)
          local r = assert(cli:send {
            method  = "GET",
            path    = "/",
            headers = {
              ["x-datadog-trace-id"] = bn.from_binary(trace_id):to_dec(),
              ["x-datadog-parent-id"] = bn.from_binary(parent_id):to_dec(),
              ["x-datadog-sampling-priority"] = "1",
            }
          })
          assert.res_status(200, r)

          -- close client connection
          cli:close()

          local ok
          ok, headers, body = thread:join()

          return ok
        end, 10)

        assert.is_string(body)

        local idx = tablex.find(headers, "Content-Type: application/msgpack")
        assert.not_nil(idx, headers)


        assert.message("trace_id mismatch").match(trace_id, body, 1, true)
        assert.message("parent_id mismatch").match(parent_id, body, 1, true)
      end)
    end)

  end)
end
