local helpers = require "spec.helpers"

describe("Plugin: response transformer", function()

  local client

  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf"
    assert(helpers.prepare_prefix())

    local api1 = assert(helpers.dao.apis:insert {
      name = "tests-response-transformer",
      request_host = "response.com",
      upstream_url = "http://httpbin.org"
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "tests-response-transformer-2",
      request_host = "response2.com",
      upstream_url = "http://httpbin.org"
    })

     -- plugin config 1
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "response-transformer",
      config = {
        remove = {
          headers = {"Access-Control-Allow-Origin"},
          json = {"url"}
        }
      }
    })
    -- plugin config 2
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "response-transformer",
      config = {
        replace = {
          json = {"headers:/hello/world", "args:this is a / test", "url:\"wot\""}
        }
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.proxy_port))
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("parameters", function()
    it("remove a parameter", function()
      local response = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "response.com"
        }
      })
      assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.is.Nil(json.url)
    end)
    it("remove a header", function()
      local response = assert(client:send {
        method = "GET",
        path = "/response-headers",
        headers = {
          host = "response.com"
        }
      })
      assert.res_status(200, response)
      assert.has.jsonbody(response)
      assert.has.no.header("acess-control-allow-origin", response)
    end)
    it("replace a body parameter on GET", function()
      local response = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "response2.com"
        }
      })
      assert.res_status(200, response)
      local json = assert.has.jsonbody(response)
      assert.equals([[/hello/world]], json.headers)
      assert.equals([[this is a / test]], json.args)
      assert.equals([["wot"]], json.url)
    end)
  end)
end)
