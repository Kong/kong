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
  local proxy_url_enable_traceid

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

      local route_traceid = bp.routes:insert({ service = http_srv,
                         protocols = { "http" },
                         paths = { "/enable_response_header_traceid" }})

      bp.plugins:insert({
        name = "opentelemetry",
        config = table_merge({
          endpoint = fmt("http://%s:%s/v1/traces", OTELCOL_HOST, OTELCOL_HTTP_PORT),
          batch_flush_delay = 0, -- report immediately
        }, config)
      })

      bp.plugins:insert({
        name = "opentelemetry",
        route      = { id = route_traceid.id },
        config = table_merge({
          endpoint = fmt("http://%s:%s/v1/traces", OTELCOL_HOST, OTELCOL_HTTP_PORT),
          batch_flush_delay = 0, -- report immediately
          http_response_header_for_traceid = "x-trace-id",
        }, config)
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "opentelemetry",
        tracing_instrumentations = types,
        tracing_sampling_rate = 1,
      })

      proxy_url = fmt("http://%s:%s", helpers.get_proxy_ip(), helpers.get_proxy_port())
      proxy_url_enable_traceid = fmt("http://%s:%s/enable_response_header_traceid", helpers.get_proxy_ip(), helpers.get_proxy_port())
    end

    describe("otelcol receives traces #http", function()
      local LIMIT = 100

      lazy_setup(function()
        -- clear file
        local shell = require "resty.shell"
        shell.run("mkdir -p $(dirname " .. OTELCOL_FILE_EXPORTER_PATH .. ")", nil, 0)
        shell.run("cat /dev/null > " .. OTELCOL_FILE_EXPORTER_PATH, nil, 0)
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
        httpc:close()
      end)

      it("send traces with config http_response_header_for_traceid enable", function()
        local httpc = http.new()
        for i = 1, LIMIT do
          local res, err = httpc:request_uri(proxy_url_enable_traceid)
          assert.is_nil(err)
          assert.same(200, res.status)
          assert.not_nil(res.headers["x-trace-id"])
          local trace_id = res.headers["x-trace-id"]
          local trace_id_regex = [[^[a-f0-9]{32}$]]
          local m = ngx.re.match(trace_id, trace_id_regex, "jo")
          assert.True(m ~= nil, "trace_id does not match regex: " .. trace_id_regex)
        end
        httpc:close()
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
    end)

  end)
end
