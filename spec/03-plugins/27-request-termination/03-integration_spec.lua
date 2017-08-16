local helpers = require "spec.helpers"

describe("Plugin: request-termination (integration)", function()
  local client, admin_client
  local consumer1

  setup(function()
    helpers.run_migrations()

    assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "api1.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
    })
    consumer1 = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "kong",
      consumer_id = consumer1.id
    })


    assert(helpers.start_kong())
    client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)

  teardown(function()
    if client and admin_client then
      client:close()
      admin_client:close()
    end
    helpers.stop_kong()
  end)


  it("can be applied on a consumer", function()
    -- add the plugin to a consumer
    local res = assert(admin_client:send {
      method = "POST",
      path = "/plugins",
      headers = {
        ["Content-type"] = "application/json",
      },
      body = {
        name = "request-termination",
        consumer_id = consumer1.id,
      },
    })
    assert.response(res).has.status(201)
    
    -- verify access being blocked
    res = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        ["Host"] = "api1.request-termination.com",
        ["apikey"] = "kong",
      },
    })
    assert.response(res).has.status(503)
    local body = assert.response(res).has.jsonbody()
    assert.same({ message = "Service unavailable" }, body)
  end)
end)
