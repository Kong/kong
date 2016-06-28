local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"

describe("Plugin: basic-auth", function()
  local client
  setup(function()
    helpers.kill_all()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "basic-auth1.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "basic-auth",
      api_id = api1.id
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "basic-auth2.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "basic-auth",
      api_id = api2.id,
      config = {
        hide_credentials = true
      }
    })

    local consumer = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    assert(helpers.dao.basicauth_credentials:insert {
      username = "bob",
      password = "kong",
      consumer_id = consumer.id
    })

    assert(helpers.start_kong())
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)
  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  describe("Unauthorized", function()
    it("returns Unauthorized on missing credentials", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"Unauthorized"}]], body)
    end)
    it("returns WWW-Authenticate header on missing credentials", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "basic-auth1.com"
        }
      })
      assert.res_status(401, res)
      assert.equal('Basic realm="'..meta._NAME..'"', res.headers["WWW-Authenticate"])
    end)
  end)

  describe("Forbidden", function()
    it("returns 403 Forbidden on invalid credentials in Authorization", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Authorization"] = "foobar",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
    end)
    it("returns 403 Forbidden on invalid credentials in Proxy-Authorization", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Proxy-Authorization"] = "foobar",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
    end)
    it("returns 403 Forbidden on password only", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Authorization"] = "Basic a29uZw==",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
    end)
    it("returns 403 Forbidden on username only", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Authorization"] = "Basic Ym9i",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
    end)
    it("authenticates valid credentials in Authorization", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"] = "basic-auth1.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("authenticates valid credentials in Proxy-Authorization", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Proxy-Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"] = "basic-auth1.com"
        }
      })
      assert.res_status(200, res)
    end)
  end)

  describe("Consumer headers", function()
    it("sends Consumer headers to upstream", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"] = "basic-auth1.com"
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
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("Basic Ym9iOmtvbmc=", json.headers.authorization)
    end)
    it("true doesn't send key to upstream", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = "Basic Ym9iOmtvbmc=",
          ["Host"] = "basic-auth2.com"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_nil(json.headers.authorization)
    end)
  end)
end)
