local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"
local utils = require "kong.tools.utils"

describe("Plugin: basic-auth (access)", function()

  local client

  setup(function()
    local bp, _, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "basic-auth1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(dao.plugins:insert {
      name   = "basic-auth",
      api_id = api1.id,
    })

    local api2 = assert(dao.apis:insert {
      name         = "api-2",
      hosts        = { "basic-auth2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(dao.plugins:insert {
      name   = "basic-auth",
      api_id = api2.id,
      config = {
        hide_credentials = true,
      },
    })

    local consumer = bp.consumers:insert {
      username = "bob",
    }
    local anonymous_user = bp.consumers:insert {
      username = "no-body",
    }
    assert(dao.basicauth_credentials:insert {
      username    = "bob",
      password    = "kong",
      consumer_id = consumer.id,
    })
     assert(dao.basicauth_credentials:insert {
      username    = "user123",
      password    = "password123",
      consumer_id = consumer.id,
    })
    assert(dao.basicauth_credentials:insert {
      username    = "user321",
      password    = "password:123",
      consumer_id = consumer.id,
    })

    local api3 = assert(dao.apis:insert {
      name         = "api-3",
      hosts        = { "basic-auth3.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(dao.plugins:insert {
      name   = "basic-auth",
      api_id = api3.id,
      config = {
        anonymous = anonymous_user.id,
      },
    })

    local api4 = assert(dao.apis:insert {
      name         = "api-4",
      hosts        = { "basic-auth4.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(dao.plugins:insert {
      name   = "basic-auth",
      api_id = api4.id,
      config = {
        anonymous = utils.uuid(), -- a non-existing consumer id
      },
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
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
      local json = cjson.decode(body)
      assert.same({ message = "Unauthorized" }, json)
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
      assert.equal('Basic realm="' .. meta._NAME .. '"', res.headers["WWW-Authenticate"])
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid authentication credentials" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid authentication credentials" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid authentication credentials" }, json)
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid authentication credentials" }, json)
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

    it("authenticates with a password containing ':'", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Authorization"] = "Basic dXNlcjMyMTpwYXNzd29yZDoxMjM=",
          ["Host"] = "basic-auth1.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("bob", body.headers["x-consumer-username"])
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
      local json = cjson.decode(body)
      assert.same({ message = "Invalid authentication credentials" }, json)
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

describe("Plugin: basic-auth (access)", function()

  local client, user1, user2, anonymous

  setup(function()
    local bp, _, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "logical-and.com" },
      upstream_url = helpers.mock_upstream_url .. "/request",
    })
    assert(dao.plugins:insert {
      name   = "basic-auth",
      api_id = api1.id,
    })
    assert(dao.plugins:insert {
      name   = "key-auth",
      api_id = api1.id,
    })

    anonymous = bp.consumers:insert {
      username = "Anonymous",
    }
    user1 = bp.consumers:insert {
      username = "Mickey",
    }
    user2 = bp.consumers:insert {
      username = "Aladdin",
    }

    local api2 = assert(dao.apis:insert {
      name         = "api-2",
      hosts        = { "logical-or.com" },
      upstream_url = helpers.mock_upstream_url .. "/request",
    })
    assert(dao.plugins:insert {
      name   = "basic-auth",
      api_id = api2.id,
      config = {
        anonymous = anonymous.id,
      },
    })
    assert(dao.plugins:insert {
      name   = "key-auth",
      api_id = api2.id,
      config = {
        anonymous = anonymous.id,
      },
    })

    assert(dao.keyauth_credentials:insert {
      key         = "Mouse",
      consumer_id = user1.id,
    })
    assert(dao.basicauth_credentials:insert {
      username    = "Aladdin",
      password    = "OpenSesame",
      consumer_id = user2.id,
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    client = helpers.proxy_client()
  end)


  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("multiple auth without anonymous, logical AND", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id or id == user2.id)
    end)

    it("fails 401, with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
          ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
        }
      })
      assert.response(res).has.status(401)
    end)

    it("fails 401, with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-and.com",
        }
      })
      assert.response(res).has.status(401)
    end)

  end)

  describe("multiple auth with anonymous, logical OR", function()

    it("passes with all credentials provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
          ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert(id == user1.id or id == user2.id)
    end)

    it("passes with only the first credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["apikey"] = "Mouse",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert.equal(user1.id, id)
    end)

    it("passes with only the second credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
          ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.no.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.not_equal(id, anonymous.id)
      assert.equal(user2.id, id)
    end)

    it("passes with no credential provided", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "logical-or.com",
        }
      })
      assert.response(res).has.status(200)
      assert.request(res).has.header("x-anonymous-consumer")
      local id = assert.request(res).has.header("x-consumer-id")
      assert.equal(id, anonymous.id)
    end)

  end)

end)
