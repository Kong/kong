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
        replace = {
          body      = [[{"error": "non-sensitive message"}]],
          if_status = {"500"}
        }
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
  end)
end)
