local helpers = require "spec.helpers"

describe("Plugins triggering", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

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

    -- Global configuration
    assert(helpers.dao.apis:insert {
      request_host = "global1.com",
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
      request_host = "api1.com",
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
      request_host = "api2.com",
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
end)
