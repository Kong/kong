local helpers = require "spec.helpers"


describe("Plugin: response-transformer-advanced (filter)", function()
  local proxy_client

  setup(function()
    local bp = helpers.get_db_utils()

    local route1 = bp.routes:insert({
      hosts = { "response.com" },
    })

    bp.plugins:insert {
      route     = { id = route1.id },
      name      = "response-transformer-advanced",
      config    = {
        whitelist = {
          json      = {"headers"},
        }
      }
    }

    local route2 = bp.routes:insert({
      hosts = { "response2.com" },
    })

    bp.plugins:insert {
      route     = { id = route2.id },
      name      = "response-transformer-advanced",
      config    = {
      }
    }

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled, response-transformer-advanced"
    }))
  end)

  teardown(function()
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
        path    = "/anything",
        headers = {
          host  = "response2.com"
        }
      })
      local json = assert.response(res).has.jsonbody()
      assert.not_nil(json.url)
      assert.not_nil(json.headers)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/anything",
        headers = {
          host  = "response.com"
        }
      })
      local json = assert.response(res).has.jsonbody()
      assert.is_nil(json.url)
      assert.not_nil(json.headers)
    end)
  end)
end)
