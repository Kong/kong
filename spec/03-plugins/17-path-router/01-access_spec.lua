local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: path-router (access)", function()
  local client, admin_client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()
    admin_client = helpers.admin_client()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "path-router.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      request_path = "/test",
      strip_request_path = true,
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      request_path = "/request",
      upstream_url = "http://mockbin.com"
    })

    local config = {
      querystring = {
        mappings = {
          {
            name = "param1",
            value = "hello",
            forward_path = "/request?sup=param1"
          },
          {
            name = "param1",
            value = "hello2",
            forward_path = "/request?sup=param2",
            strip = true
          }
        }
      }
    }

    assert(helpers.dao.plugins:insert {
      name = "path-router",
      api_id = api1.id,
      config = config
    })
    assert(helpers.dao.plugins:insert {
      name = "path-router",
      api_id = api2.id,
      config = config
    })
    assert(helpers.dao.plugins:insert {
      name = "path-router",
      api_id = api3.id,
      config = config
    })

  end)
  teardown(function()
    if client and admin_client then
      client:close()
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("host resolver", function()
    it("routes when the param matches without strip", function()
      local res = assert(client:send {
        method = "GET",
        path = "/pippo/?param1=hello",
        headers = {
          ["Host"] = "path-router.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("param1", body.queryString.sup)
      assert.equal("hello", body.queryString.param1)
    end)
    it("routes when the param matches with strip", function()
      local res = assert(client:send {
        method = "GET",
        path = "/pippo/?param1=hello2",
        headers = {
          ["Host"] = "path-router.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("param2", body.queryString.sup)
      assert.is_nil(body.queryString.param1)
    end)
  end)

  describe("path resolver", function()
    it("routes when the param matches without strip", function()
      local res = assert(client:send {
        method = "GET",
        path = "/test/pippo/?param1=hello"
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("param1", body.queryString.sup)
      assert.equal("hello", body.queryString.param1)
    end)
    it("routes when the param matches with strip", function()
      local res = assert(client:send {
        method = "GET",
        path = "/test/pippo/?param1=hello2"
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("param2", body.queryString.sup)
      assert.is_nil(body.queryString.param1)
    end)
  end)

  describe("path resolver without strip", function()
    it("routes when the param matches without strip", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?param1=hello"
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("param1", body.queryString.sup)
      assert.equal("hello", body.queryString.param1)
    end)
    it("routes when the param matches with strip", function()
      local res = assert(client:send {
        method = "GET",
        path = "/request?param1=hello2"
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("param2", body.queryString.sup)
      assert.is_nil(body.queryString.param1)
    end)
  end)

end)
