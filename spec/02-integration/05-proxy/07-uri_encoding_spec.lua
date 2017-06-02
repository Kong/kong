local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("URI encoding", function()
  local client

  setup(function()
    assert(helpers.dao.apis:insert {
      name = "api-1",
      hosts = { "httpbin.com" },
      upstream_url = "http://httpbin.org",
    })

    assert(helpers.dao.apis:insert {
      name = "api-2",
      hosts = { "mockbin.com" },
      upstream_url = "http://mockbin.com",
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("issue #1975 does not double percent-encode proxied args", function()
    -- https://github.com/Mashape/kong/pull/1975

    local res = assert(client:send {
      method = "GET",
      path = "/get?limit=25&where=%7B%22or%22:%5B%7B%22name%22:%7B%22like%22:%22%25bac%25%22%7D%7D%5D%7D",
      headers = {
        ["Host"] = "httpbin.com"
      }
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal("25", json.args.limit)
    assert.equal([[{"or":[{"name":{"like":"%bac%"}}]}]], json.args.where)
  end)

  it("issue #1480 does not percent-encode args unecessarily", function()
    -- behavior might not be correct, but we assert it anyways until
    -- a change is planned and documented.
    -- https://github.com/Mashape/kong/issues/1480

    -- we use mockbin because httpbin.org/get performs URL decode
    -- on `url` and `args` fields.
    local res = assert(client:send {
      method = "GET",
      path = "/request?param=1.2.3",
      headers = {
        ["Host"] = "mockbin.com"
      }
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal("http://mockbin.com/request?param=1.2.3", json.url)
  end)

  it("issue #749 does not decode percent-encoded args", function()
    -- https://github.com/Mashape/kong/issues/749

    -- we use mockbin because httpbin.org/get performs URL decode
    -- on `url` and `args` fields.
    local res = assert(client:send {
      method = "GET",
      path = "/request?param=abc%7Cdef",
      headers = {
        ["Host"] = "mockbin.com"
      }
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal("http://mockbin.com/request?param=abc%7Cdef", json.url)
  end)

  it("issue #688 does not percent-decode proxied URLs", function()
    -- https://github.com/Mashape/kong/issues/688

    -- we use mockbin because httpbin.org/get performs URL decode
    -- on `url` and `args` fields.
    local res = assert(client:send {
      method = "GET",
      path = "/request/foo%2Fbar",
      headers = {
        ["Host"] = "mockbin.com",
      }
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal("http://mockbin.com/request/foo%2Fbar", json.url)
  end)
end)
