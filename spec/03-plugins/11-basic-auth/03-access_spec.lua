local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"
local utils = require "kong.tools.utils"

describe("Plugin: basic-auth (access)", function()
  local client
  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "basic-auth1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "basic-auth",
      api_id = api1.id
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "basic-auth2.com" },
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
    local anonymous_user = assert(helpers.dao.consumers:insert {
      username = "no-body"
    })
    assert(helpers.dao.basicauth_credentials:insert {
      username = "bob",
      password = "kong",
      consumer_id = consumer.id
    })
     assert(helpers.dao.basicauth_credentials:insert {
      username = "user123",
      password = "password123",
      consumer_id = consumer.id
    })

    local api3 = assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "basic-auth3.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "basic-auth",
      api_id = api3.id,
      config = {
        anonymous = anonymous_user.id
      }
    })

    local api4 = assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "basic-auth4.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "basic-auth",
      api_id = api4.id,
      config = {
        anonymous = utils.uuid() -- a non-existing consumer id
      }
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
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
    it("authenticates valid credentials in Authorization", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = "Basic dXNlcjEyMzpwYXNzd29yZDEyMw==",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal('bob', body.headers["x-consumer-username"])
    end)
    it("returns 403 for valid Base64 encoding", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Authorization"] = "Basic adXNlcjEyMzpwYXNzd29yZDEyMw==",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = assert.res_status(403, res)
      assert.equal([[{"message":"Invalid authentication credentials"}]], body)
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

  describe("config.anonymous", function()
    it("works with right credentials and anonymous", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = "Basic dXNlcjEyMzpwYXNzd29yZDEyMw==",
          ["Host"] = "basic-auth3.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal('bob', body.headers["x-consumer-username"])
      assert.is_nil(body.headers["x-anonymous-consumer"])
    end)
    it("works with wrong credentials and anonymous", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "basic-auth3.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal('true', body.headers["x-anonymous-consumer"])
      assert.equal('no-body', body.headers["x-consumer-username"])
    end)
    it("errors when anonymous user doesn't exist", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "basic-auth4.com"
        }
      })
      assert.response(res).has.status(500)
    end)
  end)
end)
