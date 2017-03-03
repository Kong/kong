local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Upstream headers", function()
  local client

  setup(function()
    assert(helpers.dao.apis:insert {
      name = "headers-inspect",
      uris = "/headers-inspect",
      upstream_url = "http://placeholder.com", -- unused
    })

    assert(helpers.dao.apis:insert {
      name = "proxy-mock",
      hosts = "proxy-mock.com",
      upstream_url = "http://" .. helpers.test_conf.proxy_listen .. "/headers-inspect",
    })

    assert(helpers.start_kong({
      custom_plugins = "headers-inspect",
      lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua"
    }))

    local admin_client = helpers.admin_client()

    local res = assert(admin_client:send {
      method = "POST",
      path = "/apis/headers-inspect/plugins",
      body = {
        name = "headers-inspect"
      },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })

    assert.res_status(201, res)

    admin_client:close()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("X-Forwarded-For", function()
    it("if not present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("127.0.0.1", json["x-forwarded-for"])
    end)

    it("forwards value if present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com",
          ["X-Forwarded-For"] = "10.0.0.1",
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("10.0.0.1, 127.0.0.1", json["x-forwarded-for"])
    end)
  end)

  describe("X-Forwarded-Proto", function()
    it("if not present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("http", json["x-forwarded-proto"])
    end)

    it("if present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com",
          ["X-Forwarded-Proto"] = "https"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("https", json["x-forwarded-proto"])
    end)
  end)

  describe("X-Forwarded-Host", function()
    it("if not present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("proxy-mock.com", json["x-forwarded-host"])
    end)

    it("if present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com",
          ["X-Forwarded-Host"] = "example.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("example.com", json["x-forwarded-host"])
    end)
  end)

  describe("X-Forwarded-Port", function()
    it("if not present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal(helpers.test_conf.proxy_port, tonumber(json["x-forwarded-port"]))
    end)

    it("if present in request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
        headers = {
          ["Host"] = "proxy-mock.com",
          ["X-Forwarded-Port"] = "80"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      assert.equal("80", json["x-forwarded-port"])
    end)
  end)
end)
