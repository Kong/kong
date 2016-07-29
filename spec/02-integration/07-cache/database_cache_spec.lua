local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Resolver", function()
  setup(function()
    assert(helpers.dao.apis:insert {
      request_host = "mockbin.com",
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.start_kong({
      ["custom_plugins"] = "database-cache",
      lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua"
    }))

    -- Add the plugin
    local admin_client = helpers.admin_client()
    local res = assert(admin_client:send {
      method = "POST",
      path = "/apis/mockbin.com/plugins/",
      body = {
        name = "database-cache"
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, res)
    admin_client:close()
  end)

  teardown(function()
    helpers.kill_all()
  end)

  it("avoids dog-pile effect", function()
    local function make_request(premature, sleep_time)
      local client = helpers.proxy_client()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200?sleep="..sleep_time,
        headers = {
          ["Host"] = "mockbin.com"
        }
      })
      res:read_body()
      client:close()
    end

    assert(ngx.timer.at(0, make_request, 2))
    assert(ngx.timer.at(0, make_request, 5))
    assert(ngx.timer.at(0, make_request, 1))

    helpers.wait_until(function()
      local admin_client = helpers.admin_client()
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/invocations"
      })
      local body = res:read_body()
      admin_client:close()
      return cjson.decode(body).message == 3
    end, 10)

    -- Invocation are 3, but lookups should be 1
    local admin_client = helpers.admin_client()
    local res = assert(admin_client:send {
      method = "GET",
      path = "/cache/lookups"
    })
    local body = res:read_body()
    admin_client:close()
    assert.equal(1, cjson.decode(body).message)
  end)
end)
