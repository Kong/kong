local helpers    = require "spec.helpers"


local HELLOWORLD = "HelloWorld"               -- just a test value
local FACEBOOK   = "facebookexternalhit/1.1"  -- matches a known bot in `rules.lua`


for _, strategy in helpers.each_strategy() do
  describe("Plugin: bot-detection (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
      })

      local route1 = bp.routes:insert {
        hosts = { "bot.com" },
      }

      local route2 = bp.routes:insert {
        hosts = { "bot2.com" },
      }

      local route3 = bp.routes:insert {
        hosts = { "bot3.com" },
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "bot-detection",
        config   = {},
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "bot-detection",
        config   = {
          blacklist = { HELLOWORLD },
        },
      }

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "bot-detection",
        config   = {
          whitelist = { FACEBOOK },
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("allows regular requests", function()
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  { host = "bot.com" }
      })
      assert.response(res).has.status(200)

      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  {
          host           = "bot.com",
          ["user-agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36"
        }
      })
      assert.response(res).has.status(200)

      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  {
          host           = "bot.com",
          ["user-agent"] = HELLOWORLD
        }
      })
      assert.response(res).has.status(200)

      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  {
          host           = "bot.com",
          ["user-agent"] = "curl/7.43.0"
        }
      })
      assert.response(res).has.status(200)
    end)

    it("blocks bots", function()
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host           = "bot.com",
          ["user-agent"] = "Googlebot/2.1 (+http://www.google.com/bot.html)"
        },
      })
      assert.response(res).has.status(403)

      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host           = "bot.com",
          ["user-agent"] = FACEBOOK,
        }
      })
      assert.response(res).has.status(403)
    end)

    it("blocks blacklisted user-agents", function()
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host           = "bot2.com",
          ["user-agent"] = HELLOWORLD,
        }
      })
      assert.response(res).has.status(403)
    end)

    it("allows whitelisted user-agents", function()
      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host           = "bot3.com",
          ["user-agent"] = FACEBOOK
        }
      })
      assert.response(res).has.status(200)
    end)

  end)

  describe("Plugin: bot-detection configured global (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
      })

      bp.routes:insert {
        hosts = { "bot.com" },
      }

      bp.plugins:insert {
        route = nil,  -- apply globally
        name     = "bot-detection",
        config   = {},
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("allows regular requests", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  { host = "bot.com" }
      })
      assert.response(res).has.status(200)

      local res = assert( proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  {
          host           = "bot.com",
          ["user-agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36"
        }
      })
      assert.response(res).has.status(200)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  {
          host           = "bot.com",
          ["user-agent"] = HELLOWORLD
        }
      })
      assert.response(res).has.status(200)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers =  {
          host           = "bot.com",
          ["user-agent"] = "curl/7.43.0"
        }
      })
      assert.response(res).has.status(200)
    end)
  end)
end
