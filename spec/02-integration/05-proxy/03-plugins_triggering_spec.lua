local helpers = require "spec.helpers"

describe("Plugins triggering", function()
  local client
  setup(function()
    local consumer1 = assert(helpers.dao.consumers:insert {
      username = "consumer1"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "secret1",
      consumer_id = consumer1.id
    })
    local consumer2 = assert(helpers.dao.consumers:insert {
      username = "consumer2"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "secret2",
      consumer_id = consumer2.id
    })
    local consumer3 = assert(helpers.dao.consumers:insert {
      username = "anonymous"
    })

    -- Global configuration
    assert(helpers.dao.apis:insert {
      name = "global1",
      hosts = { "global1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      config = { }
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      config = {
        hour = 1,
      }
    })

    -- API Specific Configuration
    local api1 = assert(helpers.dao.apis:insert {
      name = "api1",
      hosts = { "api1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api1.id,
      config = {
        hour = 2,
      }
    })

    -- Consumer Specific Configuration
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      consumer_id = consumer2.id,
      config = {
        hour = 3,
      }
    })

    -- API and Consumer Configuration
    local api2 = assert(helpers.dao.apis:insert {
      name = "api2",
      hosts = { "api2.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api2.id,
      consumer_id = consumer2.id,
      config = {
        hour = 4,
      }
    })

    -- API with anonymous configuration
    local api3 = assert(helpers.dao.apis:insert {
      name = "api3",
      hosts = { "api3.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      config = {
        anonymous = consumer3.id,
      },
      api_id = api3.id,
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      consumer_id = consumer3.id,
      api_id = api3.id,
      config = {
        hour = 5,
      }
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("checks global configuration without credentials", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200",
      headers = { Host = "global1.com" }
    })
    assert.res_status(401, res)
  end)
  it("checks global api configuration", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200?apikey=secret1",
      headers = { Host = "global1.com" }
    })
    assert.res_status(200, res)
    assert.equal("1", res.headers["x-ratelimit-limit-hour"])
  end)
  it("checks api specific configuration", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200?apikey=secret1",
      headers = { Host = "api1.com" }
    })
    assert.res_status(200, res)
    assert.equal("2", res.headers["x-ratelimit-limit-hour"])
  end)
  it("checks global consumer configuration", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200?apikey=secret2",
      headers = { Host = "global1.com" }
    })
    assert.res_status(200, res)
    assert.equal("3", res.headers["x-ratelimit-limit-hour"])
  end)
  it("checks consumer specific configuration", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200?apikey=secret2",
      headers = { Host = "api2.com" }
    })
    assert.res_status(200, res)
    assert.equal("4", res.headers["x-ratelimit-limit-hour"])
  end)
  it("checks anonymous consumer specific configuration", function()
    local res = assert(client:send {
      method = "GET",
      path = "/status/200",
      headers = { Host = "api3.com" }
    })
    assert.res_status(200, res)
    assert.equal("5", res.headers["x-ratelimit-limit-hour"])
  end)
end)
