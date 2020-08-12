local helpers = require "spec.helpers"

describe("worker respawn", function()
  local admin_client, proxy_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database   = "off",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  before_each(function()
    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())
  end)

  after_each(function()
    if admin_client then
      admin_client:close()
    end

    if proxy_client then
      proxy_client:close()
    end
  end)

  it("lands on the correct cache page #5799", function()
    local res = assert(admin_client:send {
      method = "POST",
      path = "/config",
      body = {
        config = [[
        _format_version: "1.1"
        services:
        - name: my-service
          url: https://example.com
          plugins:
          - name: key-auth
          routes:
          - name: my-route
            paths:
            - /

        consumers:
        - username: my-user
          keyauth_credentials:
          - key: my-key
        ]],
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.response(res).has.status(201)

    local res = assert(proxy_client:get("/"))
    assert.res_status(401, res)

    res = assert(proxy_client:get("/", {
      headers = {
        apikey = "my-key"
      }
    }))
    assert.res_status(200, res)

    -- kill all the workers forcing all of them to respawn
    helpers.signal_workers(nil, "-TERM")

    proxy_client:close()
    proxy_client = assert(helpers.proxy_client())

    res = assert(proxy_client:get("/"))
    assert.res_status(401, res)

    res = assert(proxy_client:get("/", {
      headers = {
        apikey = "my-key"
      }
    }))
    assert.res_status(200, res)
  end)
end)
