local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("plugin: cors", function()
  local client
  setup(function()
    helpers.kill_all()
    assert(helpers.start_kong())

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "cors1.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      request_host = "cors2.com",
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      request_host = "cors3.com",
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api1.id
    })
    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api2.id,
      config = {
        origin = "example.com",
        methods = {"GET"},
        headers = {"origin", "type", "accepts"},
        exposed_headers = {"x-auth-token"},
        max_age = 23,
        credentials = true
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api3.id,
      config = {
        origin = "example.com",
        methods = {"GET"},
        headers = {"origin", "type", "accepts"},
        exposed_headers = {"x-auth-token"},
        max_age = 23,
        preflight_continue = true
      }
    })

    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("HTTP method: OPTIONS", function()
    it("gives appropriate defaults", function()
      local res = assert(client:send {
        method = "OPTIONS",
        headers = {
          ["Host"] = "cors1.com"
        }
      })
      assert.res_status(204, res)
      assert.equal("GET,HEAD,PUT,PATCH,POST,DELETE", res.headers["Access-Control-Allow-Methods"])
      assert.equal("*", res.headers["Access-Control-Allow-Origin"])
      assert.is_nil(res.headers["Access-Control-Allow-Headers"])
      assert.is_nil(res.headers["Access-Control-Expose-Headers"])
      assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
      assert.is_nil(res.headers["Access-Control-Max-Age"])
    end)
    it("accepts config options", function()
      local res = assert(client:send {
        method = "OPTIONS",
        headers = {
          ["Host"] = "cors2.com"
        }
      })
      assert.res_status(204, res)
      assert.equal("GET", res.headers["Access-Control-Allow-Methods"])
      assert.equal("example.com", res.headers["Access-Control-Allow-Origin"])
      assert.equal("23", res.headers["Access-Control-Max-Age"])
      assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
      assert.equal("origin,type,accepts", res.headers["Access-Control-Allow-Headers"])
      assert.is_nil(res.headers["Access-Control-Expose-Headers"])
    end)
    it("preflight_continue enabled", function()
      local res = assert(client:send {
        method = "OPTIONS",
        path = "/status/201",
        headers = {
          ["Host"] = "cors3.com"
        }
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.equal("201", json.code)
      assert.equal("OK", json.message)
    end)
  end)

  describe("HTTP method: others", function()
    it("gives appropriate defaults", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors1.com"
        }
      })
      assert.res_status(200, res)
      assert.equal("*", res.headers["Access-Control-Allow-Origin"])
      assert.is_nil(res.headers["Access-Control-Allow-Methods"])
      assert.is_nil(res.headers["Access-Control-Allow-Headers"])
      assert.is_nil(res.headers["Access-Control-Expose-Headers"])
      assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
      assert.is_nil(res.headers["Access-Control-Max-Age"])
    end)
    it("accepts config options", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors2.com"
        }
      })
      assert.res_status(200, res)
      assert.equal("example.com", res.headers["Access-Control-Allow-Origin"])
      assert.equal("x-auth-token", res.headers["Access-Control-Expose-Headers"])
      assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
      assert.is_nil(res.headers["Access-Control-Allow-Methods"])
      assert.is_nil(res.headers["Access-Control-Allow-Headers"])
      assert.is_nil(res.headers["Access-Control-Max-Age"])
    end)
  end)
end)
