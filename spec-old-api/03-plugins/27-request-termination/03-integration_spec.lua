local helpers = require "spec.helpers"

describe("Plugin: request-termination (integration)", function()
  local client, admin_client
  local consumer1

  setup(function()
    local bp, db, dao = helpers.get_db_utils()

    assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "api1.request-termination.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(db.plugins:insert {
      name = "key-auth",
    })
    consumer1 = bp.consumers:insert {
      username = "bob",
    }
    bp.keyauth_credentials:insert {
      key      = "kong",
      consumer = { id = consumer1.id },
    }

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
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
        consumer = { id = consumer1.id },
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
