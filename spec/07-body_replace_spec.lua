local helpers = require "spec.helpers"


describe("Plugin: response-transformer-advanced (filter)", function()
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils()

    local route1 = bp.routes:insert({
      hosts = { "response.com" },
    })

    local route2 = bp.routes:insert({
      hosts = { "response2.com" },
    })

    bp.plugins:insert {
      route     = { id = route1.id },
      name      = "response-transformer-advanced",
      config    = {
        replace = {
          body      = [[{"error": "non-sensitive message"}]],
          if_status = {"500"}
        }
      }
    }

    bp.plugins:insert {
      route     = { id = route2.id },
      name      = "response-transformer-advanced",
      config    = {
        replace = {
          body      = "plugin_text",
          if_status = {"401"}
        }
      }
    }

    bp.plugins:insert {
      route     = { id = route2.id },
      name      = "key-auth",
    }

    local consumer1 = bp.consumers:insert {
      username = "consumer1"
    }

    bp.keyauth_credentials:insert {
      key = "foo1",
      consumer = { id = consumer1.id }
    }

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled, response-transformer-advanced"
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    proxy_client = helpers.proxy_client()
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end
  end)

  describe("body", function()
    it("replace full body if status code matches", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/500",
        headers = {
          host  = "response.com"
        }
      })
      local json = assert.response(res).has.jsonbody()
      assert.same("non-sensitive message", json.error)
    end)
    it("doesn't replace full body if status code doesn't match", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host  = "response.com"
        }
      })
      local body = assert.res_status(200, res)
      assert.not_same(body, [["error": "non-sensitive message"]])
    end)
    it("does not validate replaced body against content type", function()
      -- the replaced body will be "plugin_text" -> plain text
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host  = "response2.com",
        }
      })
      -- we got a 401 due to no credentials provided
      local body = assert.res_status(401, res)
      local content_type = res.headers["content-type"]
      -- content type returned by key-auth is application/json
      assert.same("application/json; charset=utf-8", content_type)
      -- the plugin doesn’t validate the value in config.replace.body
      -- against the content type, so ensure that we pass the replaced
      -- body to the client even though the content type is different
      assert.equal("plugin_text", body)
    end)
  end)
end)
