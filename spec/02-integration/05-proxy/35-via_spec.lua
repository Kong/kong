-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers   = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local cjson     = require "cjson"
local meta      = require "kong.meta"

local str_fmt   = string.format

local SERVER_TOKENS = meta._SERVER_TOKENS

for _, strategy in helpers.all_strategies() do
  describe("append Kong Gateway info to the 'Via' header [#" .. strategy .. "]", function()
    local mock, proxy_client, declarative_config

    lazy_setup(function()
      local mock_port = helpers.get_available_port()
      mock = http_mock.new(mock_port, {
        ["/via"] = {
          access = [[
ngx.req.set_header("X-Req-To", "http_mock")
          ]],
          content = [[
local cjson = require "cjson"
ngx.say(cjson.encode({ via = tostring(ngx.var.http_via) }))
          ]],
          -- bug: https://github.com/Kong/kong/pull/12753
          header_filter = "", header = [[
ngx.header["Via"] = 'HTTP/1.1 http_mock'
ngx.header["Content-type"] = 'application/json'
          ]],
        },
      }, {
        prefix = "servroot_mock",
        req = true,
        resp = false,
      })
      assert(mock:start())

      local bp = helpers.get_db_utils(
        strategy == "off" and "postgres" or strategy,
        {
          "routes",
          "services",
        }
      )

      local service = assert(bp.services:insert {
        name = "via_service",
        url = "http://127.0.0.1:" .. mock_port .. "/via",
      })

      assert(bp.routes:insert {
        name = "via_route",
        hosts = { "test.via" },
        paths = { "/get" },
        service = { id = service.id },
      })

      declarative_config = helpers.make_yaml_file(str_fmt([=[
        _format_version: '3.0'
        _transform: true
        services:
        - name: via_service
          url: "http://127.0.0.1:%s/via"
          routes:
          - name: via_route
            hosts:
            - test.via
            paths:
            - /get
      ]=], mock_port))

      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and declarative_config or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        nginx_worker_processes = 1,
      }))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("in both the inbound and outbound directions", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["Host"] = "test.via",
          ["Via"] = "1.1 dev",
        }
      })
      local body = assert.res_status(200, res)
      local json_body = cjson.decode(body)
      assert.are_same({ via = "1.1 dev,HTTP/1.1 " .. SERVER_TOKENS }, json_body)
      assert.are_same("HTTP/1.1 http_mock,1.1 " .. SERVER_TOKENS, res.headers["Via"])
      assert.is_nil(res.headers["Server"])
    end)
  end)
end
