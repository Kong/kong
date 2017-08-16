local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: request-termination (access)", function()
  local client, admin_client

  setup(function()
    helpers.run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "api1.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-termination",
      api_id = api1.id,
      config = {
      }
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "api2.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-termination",
      api_id = api2.id,
      config = {
        status_code=404
      }
    })
    local api3 = assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "api3.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-termination",
      api_id = api3.id,
      config = {
        status_code=406,
        message="Invalid"
      }
    })
    local api4 = assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "api4.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-termination",
      api_id = api4.id,
      config = {
        body="<html><body><h1>Service is down for maintenance</h1></body></html>"
      }
    })
    local api5 = assert(helpers.dao.apis:insert {
      name = "api-5",
      hosts = { "api5.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-termination",
      api_id = api5.id,
      config = {
        status_code=451,
        content_type="text/html",
        body="<html><body><h1>Service is down due to content infringement</h1></body></html>"
      }
    })
    local api6 = assert(helpers.dao.apis:insert {
      name = "api-6",
      hosts = { "api6.request-termination.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-termination",
      api_id = api6.id,
      config = {
        status_code=503,
        body='{"code": 1, "message": "Service unavailable"}'
      }
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

  describe("status code and message", function()
    it("default status code and message", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api1.request-termination.com"
        }
      })
      local body = assert.res_status(503, res)
      local json = cjson.decode(body)
      assert.same({ message = "Service unavailable" }, json)
    end)
    
    it("status code with default message", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api2.request-termination.com"
        }
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.same({ message = "Not found" }, json)
    end)
    
    it("status code with custom message", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api3.request-termination.com"
        }
      })
      local body = assert.res_status(406, res)
      local json = cjson.decode(body)
      assert.same({ message = "Invalid" }, json)
    end)

  end)

  describe("status code and body", function()
    it("default status code and body", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api4.request-termination.com"
        }
      })
      local body = assert.res_status(503, res)
      assert.equal([[<html><body><h1>Service is down for maintenance</h1></body></html>]], body)
    end)
    
    it("status code with default message", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api5.request-termination.com"
        }
      })
      local body = assert.res_status(451, res)
      assert.equal([[<html><body><h1>Service is down due to content infringement</h1></body></html>]], body)
    end)
    
    it("status code with custom message", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api6.request-termination.com"
        }
      })
      local body = assert.res_status(503, res)
      local json = cjson.decode(body)
      assert.same({ code = 1, message = "Service unavailable" }, json)
    end)

  end)
end)
