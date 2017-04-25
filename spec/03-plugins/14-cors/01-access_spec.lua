local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: cors (access)", function()
  local client

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "cors1.com" },
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "cors2.com" },
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      name = "api-3",
      hosts = { "cors3.com" },
      upstream_url = "http://mockbin.com"
    })
    local api4 = assert(helpers.dao.apis:insert {
      name = "api-4",
      hosts = { "cors4.com" },
      upstream_url = "http://mockbin.com"
    })
    local api5 = assert(helpers.dao.apis:insert {
      name = "api-5",
      hosts = { "cors5.com" },
      upstream_url = "http://mockbin.com"
    })
    local api6 = assert(helpers.dao.apis:insert {
      name = "api-6",
      hosts = { "cors6.com" },
      upstream_url = "http://mockbin.com"
    })
    local api7 = assert(helpers.dao.apis:insert {
      name = "api-7",
      hosts = { "cors7.com" },
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
        origins = {"example.com"},
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
        origins = {"example.com"},
        methods = {"GET"},
        headers = {"origin", "type", "accepts"},
        exposed_headers = {"x-auth-token"},
        max_age = 23,
        preflight_continue = true
      }
    })

    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api4.id
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api4.id
    })

    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api5.id,
      config = {
        origins = { "*" },
        credentials = true
      }
    })

    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api6.id,
      config = {
        origins = {"example.com", "example.org"},
        methods = {"GET"},
        headers = {"origin", "type", "accepts"},
        exposed_headers = {"x-auth-token"},
        max_age = 23,
        preflight_continue = true
      }
    })

    assert(helpers.dao.plugins:insert {
      name = "cors",
      api_id = api7.id,
      config = {
        origins = { "*" },
        credentials = false
      }
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
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

    it("gives appropriate defaults when origin is explicitly set to *", function()
      local res = assert(client:send {
        method = "OPTIONS",
        headers = {
          ["Host"] = "cors5.com"
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

    it("replies with request-headers if present in request", function()
      local res = assert(client:send {
        method = "OPTIONS",
        headers = {
          ["Host"] = "cors5.com",
          ["Access-Control-Request-Headers"] = "origin,accepts",
        }
      })

      assert.res_status(204, res)
      assert.equal("origin,accepts", res.headers["Access-Control-Allow-Headers"])
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

    it("works with 404 responses", function()
      local res = assert(client:send {
        method = "GET",
        path = "/asdasdasd",
        headers = {
          ["Host"] = "cors1.com"
        }
      })
      assert.res_status(404, res)
      assert.equal("*", res.headers["Access-Control-Allow-Origin"])
      assert.is_nil(res.headers["Access-Control-Allow-Methods"])
      assert.is_nil(res.headers["Access-Control-Allow-Headers"])
      assert.is_nil(res.headers["Access-Control-Expose-Headers"])
      assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
      assert.is_nil(res.headers["Access-Control-Max-Age"])
    end)

    it("works with 40x responses returned by another plugin", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors4.com"
        }
      })
      assert.res_status(401, res)
      assert.equal("*", res.headers["Access-Control-Allow-Origin"])
      assert.is_nil(res.headers["Access-Control-Allow-Methods"])
      assert.is_nil(res.headers["Access-Control-Allow-Headers"])
      assert.is_nil(res.headers["Access-Control-Expose-Headers"])
      assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
      assert.is_nil(res.headers["Access-Control-Max-Age"])
    end)

    it("sets CORS orgin based on origin host", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors6.com",
          ["Origin"] = "http://www.example.com"
        }
      })
      assert.res_status(200, res)
      assert.equal("http://www.example.com", res.headers["Access-Control-Allow-Origin"])
    end)

    it("does not sets CORS orgin if origin host is not in origin_domains list", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors6.com",
          ["Origin"] = "http://www.example.net"
        }
      })
      assert.res_status(200, res)
      assert.is_nil(res.headers["Access-Control-Allow-Origin"])
    end)

    it("responds with the requested Origin when config.credentials=true", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors5.com",
          ["Origin"] = "http://www.example.net"
        }
      })
      assert.res_status(200, res)
      assert.equals("http://www.example.net", res.headers["Access-Control-Allow-Origin"])
      assert.equals("true", res.headers["Access-Control-Allow-Credentials"])
    end)

    it("responds with the requested Origin (including port) when config.credentials=true", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors5.com",
          ["Origin"] = "http://www.example.net:3000"
        }
      })
      assert.res_status(200, res)
      assert.equals("http://www.example.net:3000", res.headers["Access-Control-Allow-Origin"])
      assert.equals("true", res.headers["Access-Control-Allow-Credentials"])
    end)

    it("responds with * when config.credentials=false", function()
      local res = assert(client:send {
        method = "GET",
        headers = {
          ["Host"] = "cors7.com",
          ["Origin"] = "http://www.example.net"
        }
      })
      assert.res_status(200, res)
      assert.equals("*", res.headers["Access-Control-Allow-Origin"])
      assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
    end)
  end)
end)
