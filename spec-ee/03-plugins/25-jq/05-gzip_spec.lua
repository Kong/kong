-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.all_strategies() do

describe("jq #" .. strategy, function()
  local client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services", "plugins",
    }, { "jq" })

    do
      local route = bp.routes:insert {
        hosts = { "gzip-response.example.com", },
        service = bp.services:insert {
          url = "http://127.0.0.1:12345/",
        },
      }

      bp.plugins:insert({
        route = { id = route.id },
        name = "jq",
        config = {
          response_jq_program = ".[0]",
        },
      })
    end

    do
      local route = bp.routes:insert {
        hosts = { "gzip-request.example.com", },
      }

      bp.plugins:insert({
        route = { id = route.id },
        name = "jq",
        config = {
          request_jq_program = ".[0]",
        },
      })
    end

    local fixtures = {
      http_mock = {
        gzip_response = [[
          server {
            server_name gzip-response.example.com;
            listen 12345;

            location ~ "/request" {
              content_by_lua_block {
                local body = "[{ \"foo\": \"bar\" }]"
                body = require("kong.tools.gzip").deflate_gzip(body)

                ngx.status = 200
                ngx.header["Content-Type"] = "application/json"
                ngx.header["Content-Length"] = #body
                ngx.header["Content-Encoding"] = "gzip"
                ngx.print(body)
              }
            }
          }
        ]]
      }
    }

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "jq"
    }, nil, nil, fixtures))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("response", function()
    it("filters gzip encoded body", function()
      local r = assert(client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "gzip-response.example.com",
          ["Accept-Encoding"] = "gzip",
        },
      })

      local json = assert.response(r).has.jsonbody()
      assert.same({ foo = "bar" }, json)
    end)
  end)

  describe("request", function()
    local body = "[{ \"foo\": \"bar\" }]"
    body = require("kong.tools.gzip").deflate_gzip(body)

    it("filters gzip encoded body", function()
      local r = assert(client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "gzip-request.example.com",
          ["Content-Type"] = "application/json",
          ["Content-Encoding"] = "gzip",
        },
        body = body,
      })

      local json = assert.request(r).has.jsonbody()
      assert.same({ foo = "bar" }, json.params)
    end)
  end)
end)

end
