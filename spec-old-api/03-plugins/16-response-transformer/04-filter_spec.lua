local helpers = require "spec.helpers"

describe("Plugin: response-transformer (filter)", function()
  local client

  setup(function()
    local _, db, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "tests-response-transformer",
      hosts        = { "response.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api2 = assert(dao.apis:insert {
      name         = "tests-response-transformer-2",
      hosts        = { "response2.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(db.plugins:insert {
      api = { id = api1.id },
      name = "response-transformer",
      config = {
        remove = {
          headers = {"Access-Control-Allow-Origin"},
          json = {"url"}
        }
      }
    })
    assert(db.plugins:insert {
      api = { id = api2.id },
      name = "response-transformer",
      config = {
        replace = {
          json = {"headers:/hello/world", "uri_args:this is a / test", "url:\"wot\""}
        }
      }
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("parameters", function()
    it("remove a parameter", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "response.com"
        }
      })
      assert.response(r).has.status(200)
      local json = assert.response(r).has.jsonbody()
      assert.is_nil(json.url)
    end)
    it("remove a header", function()
      local r = assert(client:send {
        method = "GET",
        path = "/response-headers",
        headers = {
          host = "response.com"
        }
      })
      assert.response(r).has.status(200)
      assert.response(r).has.jsonbody()
      assert.response(r).has.no.header("acess-control-allow-origin")
    end)
    it("replace a body parameter on GET", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "response2.com"
        }
      })
      assert.response(r).status(200)
      local json = assert.response(r).has.jsonbody()
      assert.equals([[/hello/world]], json.headers)
      assert.equals([["wot"]], json.url)
      assert.equals([[this is a / test]], json.uri_args)
    end)
  end)
end)
