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
      "services", "plugins"
    }, { "jq","proxy-cache-advanced" })

    do
      local route = bp.routes:insert {
        hosts = { "proxy-cache-advanced-response.example.com", },
        service = bp.services:insert {
          url = "http://127.0.0.1:12346/",
        },
      }

      local route2 = bp.routes:insert {
        hosts = { "no-proxy-cache-advanced-response.example.com", },
        service = bp.services:insert {
          url = "http://127.0.0.1:12346/",
        },
      }

      bp.plugins:insert({
        route = { id = route.id },
        name = "jq",
        config = {
          response_jq_program = '[.["england-and-wales"].events[] | . + {division: "england-and-wales"}]',
        },
      })

      bp.plugins:insert({
        route = { id = route2.id },
        name = "jq",
        config = {
          response_jq_program = '[.["england-and-wales"].events[] | . + {division: "england-and-wales"}]',
        },
      })

      bp.plugins:insert({
        route = { id = route.id },
        name = "proxy-cache-advanced",
        config = {
          strategy = "memory",
        },
      })
    end

    local fixtures = {
      http_mock = {
        gzip_response = [[
          server {
            server_name proxy-cache-advanced-response.example.com;
            listen 12346;

            location ~ "/request" {
              content_by_lua_block {
                local body = '{ "england-and-wales": { "events": [ {"name": "Event1", "date": "2024-01-01"}, {"name": "Event2", "date": "2024-02-01"} ] }}'

                ngx.status = 200
                ngx.header["Content-Type"] = "application/json"
                ngx.header["Content-Length"] = #body
                --ngx.header["Content-Encoding"] = "gzip"
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
      plugins = "jq,proxy-cache-advanced"
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
    it("disable proxy-cache-advanced", function()
      local r = assert(client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "no-proxy-cache-advanced-response.example.com",
        },
      })

      assert.same(r.has_body, true)
      assert.same('[{"name":"Event1","date":"2024-01-01","division":"england-and-wales"},{"name":"Event2","date":"2024-02-01","division":"england-and-wales"}]\n', r:read_body())
    end)
 
    it("enable proxy-cache-advanced", function()
      local r = assert(client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "proxy-cache-advanced-response.example.com",
        },
      })

      assert.same(r.has_body, true)
      assert.same('[{"name":"Event1","date":"2024-01-01","division":"england-and-wales"},{"name":"Event2","date":"2024-02-01","division":"england-and-wales"}]\n', r:read_body())

      --repeat access to prove proxy-cache-advanced and jq work as expected
      local r = assert(client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "proxy-cache-advanced-response.example.com",
        },
      })
      assert.same(r.has_body, true)
      assert.same('[{"name":"Event1","date":"2024-01-01","division":"england-and-wales"},{"name":"Event2","date":"2024-02-01","division":"england-and-wales"}]\n', r:read_body())
    end)
  end)

  --describe("request", function()
    --local body = "[{ \"foo\": \"bar\" }]"
    --body = require("kong.tools.gzip").deflate_gzip(body)

    --it("filters gzip encoded body", function()
      --local r = assert(client:send {
        --method  = "GET",
        --path    = "/request",
        --headers = {
          --["Host"] = "gzip-request.example.com",
          --["Content-Type"] = "application/json",
          --["Content-Encoding"] = "gzip",
        --},
        --body = body,
      --})

      --local json = assert.request(r).has.jsonbody()
      --assert.same({ foo = "bar" }, json.params)
    --end)
  --end)
end)

end
