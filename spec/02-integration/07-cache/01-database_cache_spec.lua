local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Resolver", function()
  local admin_client

  setup(function()
    assert(helpers.start_kong({
      custom_plugins = "database-cache",
      lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua"
    }))
    admin_client = helpers.admin_client()

    assert(helpers.dao.apis:insert {
      request_host = "mockbin.com",
      upstream_url = "http://mockbin.com"
    })

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
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
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
      client:close()
    end

    assert(ngx.timer.at(0, make_request, 2))
    assert(ngx.timer.at(0, make_request, 5))
    assert(ngx.timer.at(0, make_request, 1))

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method = "GET",
        path = "/cache/invocations"
      })
      local body = assert.res_status(200, res)
      return cjson.decode(body).message == 3
    end, 10)

    -- Invocation are 3, but lookups should be 1
    local res = assert(admin_client:send {
      method = "GET",
      path = "/cache/lookups"
    })
    local body = assert.res_status(200, res)
    assert.equal(1, cjson.decode(body).message)

    ngx.sleep(1) -- block to allow timers requests to finish
  end)
end)
