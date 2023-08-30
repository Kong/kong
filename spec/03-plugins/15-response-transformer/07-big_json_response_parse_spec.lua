-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"

local TEST_CONF = helpers.test_conf


local function find_in_file(pat)
  local f = assert(io.open(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log, "r"))
  local line = f:read("*l")

  while line do
    if line:match(pat) then
      return true
    end

    line = f:read("*l")
  end

  return false
end

for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-transformer [#" .. strategy .. "]", function()
    local proxy_client
    local mock

    lazy_setup(function()
      bp, db  = helpers.get_db_utils(strategy)

      assert(db:truncate("routes"))
      assert(db:truncate("services"))
      local port = helpers.get_available_port()
      mock = http_mock.new("localhost:" .. port, {
        ["/add"] = {
          content = [[
            local cjson = require("cjson.safe").new()
            local cjson_encode = cjson.encode

            ngx.header.content_type = "application/json"

            mock_json = {
              big_field = string.rep("*", 1024*1024),
            }
            ngx.say(cjson_encode(mock_json))
          ]]
        },
        ["/remove"] = {
          content = [[
            local cjson = require("cjson.safe").new()
            local cjson_encode = cjson.encode

            ngx.header.content_type = "application/json"

            mock_json = {
              param = 2,
              big_field = string.rep("*", 1024*1024),
            }
            ngx.say(cjson_encode(mock_json))
          ]]
        }
      }, {
        record_opts = {
          req = false,
        }
      })

      assert(mock:start())

      local service = assert(bp.services:insert {
        protocol = "http",
        host = "127.0.0.1",
        port = port,
      })

      local route = assert(bp.routes:insert {
        hosts = { "rtlj.com" },
        service = service,
      })

      bp.plugins:insert {
        route = { id = route.id },
        name     = "response-transformer",
        config   = {
          add    = {
            json = {"p1:v1"},
          },
          remove = {
            json = {"params"},
          },
        },
      }

      assert(helpers.start_kong({
        database           = strategy,
        nginx_http_charset = "off",
        log_level          = 'warn',
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
      mock:stop()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    it("add new parameters on large JSON body", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/add",
        headers = {
          host  = "rtlj.com",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equal("v1", json.p1)
      assert(not find_in_file("body transform failed: failed parsing json body"))
    end)
    it("remove parameters on large JSON body", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/remove",
        headers = {
          host  = "rtlj.com",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.is_nil(json.params)
      assert(not find_in_file("body transform failed: failed parsing json body"))
    end)
  end)
end
