local helpers = require "spec.helpers"

describe("Plugins triggering", function()
  local client
  setup(function()
    helpers.run_migrations()

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
      name         = "global1",
      hosts        = { "global1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name   = "key-auth",
      config = {},
    })
    assert(helpers.dao.plugins:insert {
      name   = "rate-limiting",
      config = {
        hour = 1,
      },
    })

    -- API Specific Configuration
    local api1 = assert(helpers.dao.apis:insert {
      name         = "api1",
      hosts        = { "api1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name   = "rate-limiting",
      api_id = api1.id,
      config = {
        hour = 2,
      },
    })

    -- Consumer Specific Configuration
    assert(helpers.dao.plugins:insert {
      name        = "rate-limiting",
      consumer_id = consumer2.id,
      config      = {
        hour = 3,
      },
    })

    -- API and Consumer Configuration
    local api2 = assert(helpers.dao.apis:insert {
      name         = "api2",
      hosts        = { "api2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name        = "rate-limiting",
      api_id      = api2.id,
      consumer_id = consumer2.id,
      config = {
        hour = 4,
      },
    })

    -- API with anonymous configuration
    local api3 = assert(helpers.dao.apis:insert {
      name         = "api3",
      hosts        = { "api3.com" },
      upstream_url = helpers.mock_upstream_url,
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

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
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

  describe("anonymous reports execution", function()
    -- anonymous reports are implemented as a plugin which is being executed
    -- by the plugins runloop, but which doesn't have a schema
    --
    -- This is a regression test after:
    --     https://github.com/Mashape/kong/issues/2756
    -- to ensure that this plugin plays well when it is being executed by
    -- the runloop (which accesses plugins schemas and is vulnerable to
    -- Lua indexing errors)
    --
    -- At the time of this test, the issue only arises when a request is
    -- authenticated via an auth plugin, and the runloop runs again, and
    -- tries to evaluate is the `schema.no_consumer` flag is set.
    -- Since the reports plugin has no `schema`, this indexing fails.

    setup(function()
      if client then
        client:close()
      end

      helpers.stop_kong()

      helpers.dao:truncate_tables()

      local api      = assert(helpers.dao.apis:insert {
        name         = "example",
        hosts        = { "mock_upstream" },
        upstream_url = helpers.mock_upstream_url
      })

      assert(helpers.dao.plugins:insert {
        name   = "key-auth",
        api_id = api.id,
      })

      local consumer = assert(helpers.dao.consumers:insert {
        username = "bob",
      })

      assert(helpers.dao.keyauth_credentials:insert {
        key         = "abcd",
        consumer_id = consumer.id,
      })

      assert(helpers.start_kong {
        nginx_conf        = "spec/fixtures/custom_nginx.template",
        anonymous_reports = true,
      })
      client = helpers.proxy_client()
    end)

    teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    it("runs without causing an internal error", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "mock_upstream",
        },
      })
      assert.res_status(401, res)

      res = assert(client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"]   = "mock_upstream",
          ["apikey"] = "abcd",
        },
      })
      assert.res_status(200, res)
    end)
  end)
end)
