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

      bp.plugins:insert({
        name = "opentelemetry",
        config = table_merge({
          endpoint = fmt("http://%s:%s/v1/traces", OTELCOL_HOST, OTELCOL_HTTP_PORT),
          batch_flush_delay = -1, -- report immediately
        }, config)
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "opentelemetry",
        opentelemetry_tracing = types,
      })

      proxy_url = fmt("http://%s:%s", helpers.get_proxy_ip(), helpers.get_proxy_port())
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
        ngx.sleep(3)
        local f = assert(io.open(OTELCOL_FILE_EXPORTER_PATH, "rb"))
        local raw_content = f:read("*all")
        f:close()

        local parts = split(raw_content, "\n", "jo")
        assert.is_true(#parts > 0)
      end)
    end)

  end)
end
