local helpers = require "spec.helpers"

local HELLOWORLD = "HelloWorld"             -- just a test value
local FACEBOOK = "facebookexternalhit/1.1"  -- matches a known bot in `rules.lua`

describe("Plugin: bot-detection (access)", function()
  local client
  setup(function()
    local _, db, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "bot.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api2 = assert(dao.apis:insert {
      name         = "api-2",
      hosts        = { "bot2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api3 = assert(dao.apis:insert {
      name         = "api-3",
      hosts        = { "bot3.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    -- plugin 1
    assert(db.plugins:insert {
      api = { id = api1.id },
      name   = "bot-detection",
      config = {},
    })
    -- plugin 2
    assert(db.plugins:insert {
      api = { id = api2.id },
      name   = "bot-detection",
      config = {
        blacklist = { HELLOWORLD },
      },
    })
    -- plugin 3
    assert(db.plugins:insert {
      api = { id = api3.id },
      name   = "bot-detection",
      config = {
        whitelist = { FACEBOOK },
      },
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("allows regular requests", function()
    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  { host = "bot.com" }
    })
    assert.response(res).has.status(200)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  {
        host = "bot.com",
        ["user-agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36"
      }
    })
    assert.response(res).has.status(200)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  {
        host = "bot.com",
        ["user-agent"] = HELLOWORLD
      }
    })
    assert.response(res).has.status(200)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  {
        host = "bot.com",
        ["user-agent"] = "curl/7.43.0"
      }
    })
    assert.response(res).has.status(200)
  end)

  it("blocks bots", function()
    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "bot.com",
        ["user-agent"] = "Googlebot/2.1 (+http://www.google.com/bot.html)"
      },
    })
    assert.response(res).has.status(403)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "bot.com",
        ["user-agent"] = FACEBOOK,
      }
    })
    assert.response(res).has.status(403)
  end)

  it("blocks blacklisted user-agents", function()
    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "bot2.com",
        ["user-agent"] = HELLOWORLD,
      }
    })
    assert.response(res).has.status(403)
  end)

  it("allows whitelisted user-agents", function()
    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "bot3.com",
        ["user-agent"] = FACEBOOK
      }
    })
    assert.response(res).has.status(200)
  end)

end)

describe("Plugin: bot-detection configured global (access)", function()
  local client
  setup(function()
    local _, db, dao = helpers.get_db_utils()

    assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "bot.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    -- plugin 1
    assert(db.plugins:insert {
      api = ngx.null,  -- apply globally
      name   = "bot-detection",
      config = {},
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("allows regular requests", function()
    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  { host = "bot.com" }
    })
    assert.response(res).has.status(200)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  {
        host = "bot.com",
        ["user-agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36"
      }
    })
    assert.response(res).has.status(200)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  {
        host = "bot.com",
        ["user-agent"] = HELLOWORLD
      }
    })
    assert.response(res).has.status(200)

    local res = assert( client:send {
      method = "GET",
      path = "/request",
      headers =  {
        host = "bot.com",
        ["user-agent"] = "curl/7.43.0"
      }
    })
    assert.response(res).has.status(200)
  end)

end)
