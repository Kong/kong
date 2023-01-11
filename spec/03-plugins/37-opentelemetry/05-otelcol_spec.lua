require "kong.plugins.opentelemetry.proto"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local ngx_re = require "ngx.re"
local http = require "resty.http"


local fmt = string.format
local table_merge = utils.table_merge
local split = ngx_re.split

local OTELCOL_HOST = helpers.otelcol_host
local OTELCOL_HTTP_PORT = helpers.otelcol_http_port
local OTELCOL_FILE_EXPORTER_PATH = helpers.otelcol_file_exporter_path

for _, strategy in helpers.each_strategy() do
  local proxy_url
  local admin_client
  local plugin

  describe("otelcol #" .. strategy, function()
    -- helpers
    local function setup_instrumentations(types, config)
      local bp, _ = assert(helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, { "opentelemetry" }))

      local http_srv = assert(bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
      })

      bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         paths = { "/" }})

      plugin = bp.plugins:insert({
        name = "opentelemetry",
        config = table_merge({
          endpoint = fmt("http://%s:%s/v1/traces", OTELCOL_HOST, OTELCOL_HTTP_PORT),
          batch_flush_delay = 0, -- report immediately
        }, config)
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "opentelemetry",
        opentelemetry_tracing = types,
      })

      proxy_url = fmt("http://%s:%s", helpers.get_proxy_ip(), helpers.get_proxy_port())
      admin_client = helpers.admin_client()
    end

    describe("otelcol receives traces #http", function()
      local LIMIT = 100

      lazy_setup(function()
        -- clear file
        os.execute("cat /dev/null > " .. OTELCOL_FILE_EXPORTER_PATH)
        setup_instrumentations("all")
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("send traces", function()
        local httpc = http.new()
        for i = 1, LIMIT do
          local res, err = httpc:request_uri(proxy_url)
          assert.is_nil(err)
          assert.same(200, res.status)
        end
      end)

      it("valid traces", function()
        helpers.wait_until(function()
          local f = assert(io.open(OTELCOL_FILE_EXPORTER_PATH, "rb"))
          local raw_content = f:read("*all")
          f:close()

          local parts = split(raw_content, "\n", "jo")
          return #parts > 0
        end, 10)
      end)


      it("traces info after update by admin api", function()
        os.execute("cat /dev/null > " .. OTELCOL_FILE_EXPORTER_PATH)
        local httpc = http.new()
        for i = 1, LIMIT do
          local res, err = httpc:request_uri(proxy_url)
          assert.is_nil(err)
          assert.same(200, res.status)
        end
        
        helpers.wait_until(function()
          local f = assert(io.open(OTELCOL_FILE_EXPORTER_PATH, "rb"))
          local raw_content = f:read("*all")
          f:close()

          local parts = split(raw_content, "\n", "jo")
          if not string.find(raw_content, "kong") then
            return false
          end
          return #parts > 0
        end, 10)

        os.execute("cat /dev/null > " .. OTELCOL_FILE_EXPORTER_PATH)
        local res = admin_client:patch("/plugins/" .. plugin.id, {
          body = {
            config = {
              resource_attributes = {
                ["service.name"] = "kong-dev-new",
              },
              batch_flush_delay = 0,
            },
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        assert.res_status(200, res)

        local httpc = http.new()
        for i = 1, LIMIT do
          local res, err = httpc:request_uri(proxy_url)
          assert.is_nil(err)
          assert.same(200, res.status)
        end

        helpers.wait_until(function()
          local f = assert(io.open(OTELCOL_FILE_EXPORTER_PATH, "rb"))
          local raw_content = f:read("*all")
          f:close()

          local parts = split(raw_content, "\n", "jo")
          if not string.find(raw_content, "kong-dev-new") then
            return false
          end
          return #parts > 0
        end, 10)

      end)

    end)

  end)
end
