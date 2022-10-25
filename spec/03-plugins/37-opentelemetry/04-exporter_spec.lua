require "kong.plugins.opentelemetry.proto"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"
local pb = require "pb"
local pl_file = require "pl.file"
local ngx_re = require "ngx.re"

local table_merge = utils.table_merge
local HTTP_SERVER_PORT = 35000
local PROXY_PORT = 9000

for _, strategy in helpers.each_strategy() do
  describe("opentelemetry exporter #" .. strategy, function()
    local bp

    lazy_setup(function ()
      -- overwrite for testing
      pb.option("enum_as_value")
      pb.option("auto_default_values")
    end)

    lazy_teardown(function()
      -- revert it back
      pb.option("enum_as_name")
      pb.option("no_default_values")
    end)

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
        name = "opentelemetry",
        config = table_merge({
          endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT,
          batch_flush_delay = -1, -- report immediately
        }, config)
      })

      assert(helpers.start_kong({
        proxy_listen = "0.0.0.0:" .. PROXY_PORT,
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "opentelemetry",
        opentelemetry_tracing = types,
      }, nil, nil, fixtures))
    end

    describe("valid #http request", function ()
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("all", {
          headers = {
            ["X-Access-Token"] = "token",
          },
        })
      end)

      lazy_teardown(function()
        helpers.kill_http_server(HTTP_SERVER_PORT)
        helpers.stop_kong()
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

        local idx = tablex.find(headers, "Content-Type: application/x-protobuf")
        assert.not_nil(idx, headers)

        -- custom http headers
        idx = tablex.find(headers, "X-Access-Token: token")
        assert.not_nil(idx, headers)

        local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
        assert.not_nil(decoded)

        -- array is unstable
        local res_attr = decoded.resource_spans[1].resource.attributes
        table.sort(res_attr, function(a, b)
          return a.key < b.key
        end)
        -- default resource attributes
        assert.same("service.instance.id", res_attr[1].key)
        assert.same("service.name", res_attr[2].key)
        assert.same({string_value = "kong"}, res_attr[2].value)
        assert.same("service.version", res_attr[3].key)
        assert.same({string_value = kong.version}, res_attr[3].value)

        local scope_spans = decoded.resource_spans[1].scope_spans
        assert.is_true(#scope_spans > 0, scope_spans)
      end)
    end)

    describe("overwrite resource attributes #http", function ()
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        setup_instrumentations("all", {
          resource_attributes = {
            ["service.name"] = "kong_oss",
            ["os.version"] = "debian",
          }
        })
      end)

      lazy_teardown(function()
        helpers.kill_http_server(HTTP_SERVER_PORT)
        helpers.stop_kong()
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

        local idx = tablex.find(headers, "Content-Type: application/x-protobuf")
        assert.not_nil(idx, headers)

        local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", body))
        assert.not_nil(decoded)

        -- array is unstable
        local res_attr = decoded.resource_spans[1].resource.attributes
        table.sort(res_attr, function(a, b)
          return a.key < b.key
        end)
        -- resource attributes
        assert.same("os.version", res_attr[1].key)
        assert.same({string_value = "debian"}, res_attr[1].value)
        assert.same("service.instance.id", res_attr[2].key)
        assert.same("service.name", res_attr[3].key)
        assert.same({string_value = "kong_oss"}, res_attr[3].value)
        assert.same("service.version", res_attr[4].key)
        assert.same({string_value = kong.version}, res_attr[4].value)

        local scope_spans = decoded.resource_spans[1].scope_spans
        assert.is_true(#scope_spans > 0, scope_spans)
      end)
    end)

    describe("data #race with cascaded multiple spans", function ()
      lazy_setup(function()
        bp, _ = assert(helpers.get_db_utils(strategy, {
          "services",
          "routes",
          "plugins",
        }, { "opentelemetry" }))

        pl_file.delete("/tmp/kong_opentelemetry_data")

        local fixtures = {
          http_mock = {}
        }

        fixtures.http_mock.my_server_block = [[
          server {
            server_name myserver;
            listen ]] .. HTTP_SERVER_PORT .. [[;
            client_body_buffer_size 1024k;

            location / {
              content_by_lua_block {
                ngx.req.read_body()
                local data = ngx.req.get_body_data()

                local fd = assert(io.open("/tmp/kong_opentelemetry_data", "a"))
                assert(fd:write(ngx.encode_base64(data)))
                assert(fd:write("\n")) -- ensure last line ends in newline
                assert(fd:close())

                return 200;
              }
            }
          }
        ]]

        for i = 1, 5 do
          local svc = assert(bp.services:insert {
            host = "127.0.0.1",
            port = PROXY_PORT,
            path = i == 1 and "/" or ("/cascade-" .. (i - 1)),
          })

          bp.routes:insert({ service = svc,
                             protocols = { "http" },
                             paths = { "/cascade-" .. i },
                             strip_path = true })
        end

        setup_instrumentations("request", {}, fixtures)
      end)

      lazy_teardown(function()
        -- pl_file.delete("/tmp/kong_opentelemetry_data")
        helpers.kill_http_server(HTTP_SERVER_PORT)
        helpers.stop_kong()
      end)

      it("send enough spans", function ()
        local pb_set = {}
        local cli = helpers.proxy_client(7000, PROXY_PORT)
        local r = assert(cli:send {
          method  = "GET",
          path    = "/cascade-5",
        })
        assert.res_status(200, r)

        -- close client connection
        cli:close()

        helpers.wait_until(function()
          local fd, err = io.open("/tmp/kong_opentelemetry_data", "r")
          if err then
            return false, "failed to open file: " .. err
          end

          local body = fd:read("*a")
          pb_set = ngx_re.split(body, "\n")

          print("pb set length: ", #pb_set)
          local count = 0
          for _, pb_data in ipairs(pb_set) do
            local decoded = assert(pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", ngx.decode_base64(pb_data)))
            assert.not_nil(decoded)
            -- print(require("inspect")(decoded))

            local scope_spans = decoded.resource_spans[1].scope_spans
            if scope_spans then
              for _, scope_span in ipairs(scope_spans) do
                count = count + #scope_span.spans
              end
            end
          end

          if count < 6 then
            return false, "not enough spans: " .. count
          end

          return true
        end, 10)
      end)
    end)

  end)
end
