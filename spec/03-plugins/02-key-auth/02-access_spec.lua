local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"
local utils = require "kong.tools.utils"

describe("Plugin: key-auth (access)", function()
  local client
  setup(function()
    local anonymous_user = assert(helpers.dao.consumers:insert {
      username = "no-body"
    })
    
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "key-auth1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })

    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "key-auth2.com" },
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

    local api3 = assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "key-auth3.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api3.id,
      config = {
        anonymous = anonymous_user.id
      }
    })

    local api4 = assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "key-auth4.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api4.id,
      config = {
        anonymous = utils.uuid()  -- unknown consumer
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
          ["Host"] = "key-auth1.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"No API key found in headers or querystring"}]], body)
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
    it("handles duplicated key in querystring", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200?apikey=kong&apikey=kong",
        headers = {
          ["Host"] = "key-auth1.com"
        }
      })
      local body = assert.res_status(401, res)
      assert.equal([[{"message":"Duplicate API key found"}]], body)
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
      assert.is_nil(json.headers["x-anonymous-consumer"])
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

  describe("config.anonymous", function()
    it("works with right credentials and anonymous", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          ["Host"] = "key-auth3.com",
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
          ["Host"] = "key-auth3.com"
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
          ["Host"] = "key-auth4.com"
        }
      })
      assert.response(res).has.status(500)
    end)
  end)
end)
