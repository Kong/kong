local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"

describe("Plugin: key-auth (access)", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "key-auth1.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "key-auth2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api2.id,
      config = {
        hide_credentials = true
      }
    })

    local consumer1 = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "kong",
      consumer_id = consumer1.id
    })
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("Unauthorized", function()
    it("returns Unauthorized on missing credentials", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "key-auth1.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"No API Key found in headers, body or querystring"}]], body)
    end)
    it("returns WWW-Authenticate header on missing credentials", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "key-auth1.com"
        }
      })
      res:read_body()
      assert.equal('Key realm="'..meta._NAME..'"', res.headers["WWW-Authenticate"])
    end)
  end)

  describe("key in querystring", function()
    it("authenticates valid credentials", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          ["Host"] = "key-auth1.com",
        }
      })
      assert.res_status(200, res)
    end)
    it("returns 403 Forbidden on invalid key", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200?apikey=123",
        headers = {
          ["Host"] = "key-auth1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
    end)
  end)

  describe("key in headers", function()
    it("authenticates valid credentials", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "key-auth1.com",
          ["apikey"] = "kong"
        }
      })
      assert.res_status(200, res)
    end)
    it("returns 403 Forbidden on invalid key", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "key-auth1.com",
          ["apikey"] = "123"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
    end)
  end)

  describe("Consumer headers", function()
    it("sends Consumer headers to upstream", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          ["Host"] = "key-auth1.com",
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_string(json.headers["x-consumer-id"])
      assert.equal("bob", json.headers["x-consumer-username"])
    end)
  end)

  describe("config.hide_credentials", function()
    it("false sends key to upstream", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "key-auth1.com",
          ["apikey"] = "kong"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("kong", json.headers.apikey)
    end)
    it("true doesn't send key to upstream", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "key-auth2.com",
          ["apikey"] = "kong"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_nil(json.headers.apikey)
    end)
  end)
end)
