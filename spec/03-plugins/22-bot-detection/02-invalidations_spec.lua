local helpers = require "spec.helpers"

describe("Plugin: bot-detection (hooks)", function()
  local plugin, proxy_client, admin_client

  setup(function()
    helpers.run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name = "bot.com",
      hosts = { "bot.com" },
      upstream_url = "http://mockbin.com"
    })
    plugin = assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "bot-detection",
      config = {},
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)

  after_each(function()
    if proxy_client then proxy_client:close() end
    if admin_client then admin_client:close() end
  end)

  it("blocks a newly entered user-agent", function()
    local res
    res = assert( proxy_client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "bot.com",
        ["user-agent"] = "helloworld"
      }
    })
    assert.response(res).has.status(200)

    -- Update the plugin
    res = assert(admin_client:send {
      method = "PATCH",
      path = "/apis/bot.com/plugins/" .. plugin.id,
      body = {
        ["config.blacklist"] = "helloworld"
      },
      headers = {
        ["content-type"] = "application/json"
      }
    })
    assert.response(res).has.status(200)

    local check_status = function()
      local res = assert(proxy_client:send {
        mehod = "GET",
        path = "/request",
        headers = {
          host = "bot.com",
          ["user-agent"] = "helloworld",
        },
      })
      res:read_body()  -- must call read_body to complete call, otherwise next iteration fails
      return res.status == 403
    end
    helpers.wait_until(check_status, 10)
  end)

  it("allows a newly entered user-agent", function()
    local res
    res = assert(proxy_client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "bot.com",
        ["user-agent"] = "facebookexternalhit/1.1"
      }
    })
    assert.response(res).has.status(403)

    -- Update the plugin
    res = assert(admin_client:send {
      method = "PATCH",
      path = "/apis/bot.com/plugins/" .. plugin.id,
      body = {
        ["config.whitelist"] = "facebookexternalhit/1.1"
      },
      headers = {
        ["content-type"] = "application/json",
      }
    })
    assert.response(res).has.status(200)

    local check_status = function()
      local res = assert(proxy_client:send {
        mehod = "GET",
        path = "/request",
        headers = {
          host = "bot.com",
          ["user-agent"] = "facebookexternalhit/1.1"
        }
      })
      res:read_body()  -- must call read_body to complete call, otherwise next iteration fails
      return res.status == 200
    end
    helpers.wait_until(check_status, 10)
  end)

end)
