local helpers = require "spec.helpers"

local TEST_SIZE = 2
local MB = 2^20

describe("Plugin: request-size-limiting (access)", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    local api = assert(helpers.dao.apis:insert {
      request_host = "limit.com",
      upstream_url = "http://mockbin.com/"
    })
    assert(helpers.dao.plugins:insert {
      name = "request-size-limiting",
      api_id = api.id,
      config = {
        allowed_payload_size = TEST_SIZE
      }
    })
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("with Content-Length", function()
    it("works if size is lower than limit", function()
      local body = string.rep("a", (TEST_SIZE * MB))
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Content-Length"] = string.len(body)
        }
      })
      assert.res_status(200, res)
    end)
    it("works if size is lower than limit and Expect header", function()
      local body = string.rep("a", (TEST_SIZE * MB))
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Expect"] = "100-continue",
          ["Content-Length"] = string.len(body)
        }
      })
      assert.res_status(200, res)
    end)
    it("blocks if size is greater than limit", function()
      local body = string.rep("a", (TEST_SIZE * MB) + 1)
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Content-Length"] = string.len(body)
        }
      })
      local body = assert.res_status(413, res)
      assert.matches([[{"message":"Request size limit exceeded"}]], body)
    end)
    it("blocks if size is greater than limit and Expect header", function()
      local body = string.rep("a", (TEST_SIZE * MB) + 1)
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Expect"] = "100-continue",
          ["Content-Length"] = string.len(body)
        }
      })
      local body = assert.res_status(417, res)
      assert.matches([[{"message":"Request size limit exceeded"}]], body)
    end)
  end)

  describe("without Content-Length", function()
    it("works if size is lower than limit", function()
      local body = string.rep("a", (TEST_SIZE * MB))
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com"
        }
      })
      assert.res_status(200, res)
    end)
    it("works if size is lower than limit and Expect header", function()
      local body = string.rep("a", (TEST_SIZE * MB))
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Expect"] = "100-continue"
        }
      })
      assert.res_status(200, res)
    end)
    it("blocks if size is greater than limit", function()
      local body = string.rep("a", (TEST_SIZE * MB) + 1)
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com"
        }
      })
      local body = assert.res_status(413, res)
      assert.matches([[{"message":"Request size limit exceeded"}]], body)
    end)
    it("blocks if size is greater than limit and Expect header", function()
      local body = string.rep("a", (TEST_SIZE * MB) + 1)
      local res = assert(client:request {
        method = "POST",
        path = "/request",
        body = body,
        headers = {
          ["Host"] = "limit.com",
          ["Expect"] = "100-continue"
        }
      })
      local body = assert.res_status(417, res)
      assert.matches([[{"message":"Request size limit exceeded"}]], body)
    end)
  end)
end)
