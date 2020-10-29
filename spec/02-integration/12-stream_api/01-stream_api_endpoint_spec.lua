local helpers = require "spec.helpers"

describe("Stream module API endpoint", function()

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      stream_listen = "127.0.0.1:8008",
      stream_api = "8086",
      plugins = "stream-api-echo",
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("creates listener", function()
    it("response 404 for unknown path", function()
      local client = helpers.http_client("127.0.0.1", 8086, 0.1)
      local res = assert(client:send({
        method = "GET",
        path = "/empty",
      }))
      assert.response(res).has.status(404)
    end)

    it("calls an api handler", function()
      local client = helpers.http_client("127.0.0.1", 8086, 0.1)
      local res = assert(client:post("/echo", {
        body = "some thing",
      }))
      local res_body = assert.response(res).has.status(200)
      assert.equal("some thing", res_body)
    end)
  end)
end)
