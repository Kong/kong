local helpers = require "spec.helpers"
local cjson = require "cjson"


describe("Plugin: canary (access)", function()
  local proxy_client, admin_client, api1, api2

  setup(function()
    helpers.run_migrations()

    api1 = assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "canary1.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id,
      config = {}
    })

    api2 = assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "canary2.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {}
    })

    local consumer1 = assert(helpers.dao.consumers:insert {
      username = "consumer1",
      id = "11111111-70ef-467c-8c82-0d89fa551b47"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey123",
      consumer_id = consumer1.id
    })

    local consumer2 = assert(helpers.dao.consumers:insert {
      username = "consumer2",
      id = "bc32e4ec-e4df-11e7-80c1-9a214cf093ae"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey124",
      consumer_id = consumer2.id
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      custom_plugins = "canary",
    }))
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
  end)


  teardown(function()
    helpers.stop_kong("servroot", true)
  end)

  describe("Canary", function()
    it("test percentage 50%", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/requests?apikey=apikey123",
        headers = {
          ["Host"] = "canary1.com"
        }
      })
      assert.res_status(200, res)

      res = assert(admin_client:send {
        method = "POST",
        path = "/apis/" .. api1.name .."/plugins",
        headers = {
          ["Host"] = "canary1.com",
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "canary",
          config = {
            upstream_uri = "/requests/path2",
            percentage = "50",
            steps = "4",
          }
        }
      })
      assert.res_status(201, res)
      local count = {
        ["/requests/path2"] = 0,
        ["/requests"] = 0
      }

      for n = 1, 10 do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = "apikey123"
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        count[json.vars.request_uri] = count[json.vars.request_uri] + 1

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary1.com",
            ["apikey"] = "apikey124"
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        count[json.vars.request_uri] = count[json.vars.request_uri] + 1
      end

      assert.is_equal(count["/requests/path2"],
                      count["/requests"] )
    end)
    it("test start", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/requests?apikey=apikey123",
        headers = {
          ["Host"] = "canary2.com"
        }
      })
      assert.res_status(200, res)

      res = assert(admin_client:send {
        method = "POST",
        path = "/apis/" .. api2.name .."/plugins/",
        headers = {
          ["Host"] = "canary1.com",
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "canary",
          config = {
            upstream_uri = "/requests/path2",
            percentage = nil,
            steps = 4,
            start = ngx.time() + 1,
            duration = 5
          }
        }
      })
      ngx.sleep(1)
      assert.res_status(201, res)
      local count = {
        ["/requests/path2"] = 0,
        ["/requests"] = 0
      }

      for n = 1, 5 do
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary2.com",
            ["apikey"] = "apikey123"
          }
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        count[json.vars.request_uri] = count[json.vars.request_uri] + 1

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/requests",
          headers = {
            ["Host"] = "canary2.com",
            ["apikey"] = "apikey124"
          }
        })


        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        count[json.vars.request_uri] = count[json.vars.request_uri] + 1

        ngx.sleep(1)

      end

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/requests",
        headers = {
          ["Host"] = "canary2.com",
          ["apikey"] = "apikey124"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_equal("/requests/path2", json.vars.request_uri)
    end)
  end)
end)
