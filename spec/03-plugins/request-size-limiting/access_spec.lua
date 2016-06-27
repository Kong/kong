local helpers = require "spec.helpers"

describe("Plugin: request-size-limiting", function()
  local client
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())

    local api = assert(helpers.dao.apis:insert {
      request_host = "limit.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-size-limiting",
      api_id = api.id,
      config = {
        allowed_payload_size = 10
      }
    })

    assert(helpers.start_kong())
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("with Content-Length set", function()
    it("allows request of lower size", function()
      local body = "foo=test&bar=foobar"

      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
          ["Content-Length"] = #body
        }
      })
      assert.res_status(200, res)
    end)
    it("blocks request exceeding size limit", function()
      local body = string.rep("a", 11 * 2^20)

      local res = assert(client:send {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Content-Type"] = "application/x-www-form-urlencoded",
          ["Content-Length"] = #body
        }
      })
      local response_body = assert.res_status(413, res)
      assert.equal([[{"message":"Request size limit exceeded"}]], response_body)
    end)
  end)

  describe("without Content-Length", function()
    it("allows request of lower size", function()
      local body = "foo=test&bar=foobar"

      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      assert.res_status(200, res)
    end)
    it("blocks request exceeding size limit", function()
      local body = string.rep("a", 11 * 2^20)

      local res = assert(client:send {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local response_body = assert.res_status(413, res)
      assert.equal([[{"message":"Request size limit exceeded"}]], response_body)
    end)
  end)
end)
