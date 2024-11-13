local helpers = require "spec.helpers"
local stream_api = require "kong.tools.stream_api"
local encode = require("cjson").encode
local constants = require "kong.constants"


describe("Stream module API endpoint", function()

  local socket_path

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      stream_listen = "127.0.0.1:8008",
      plugins = "stream-api-echo",
    })

    socket_path = "unix:" .. helpers.get_running_conf().socket_path .. "/" .. constants.SOCKETS.STREAM_RPC
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  describe("creates listener", function()
    it("error response for unknown path", function()
      local res, err = stream_api.request("not-this", "nope", socket_path)
      assert.is.falsy(res)
      assert.equal("stream-api err: no handler", err)
    end)

    it("calls an echo handler", function()
      local msg = encode { payload = "ping!" }
      local res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(err)
      assert.equal("ping!", res)
    end)

    it("allows handlers to return tables and concatenates them", function()
      local msg = encode { payload = { "a", "b", "c" } }
      local res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(err)
      assert.equal("abc", res)
    end)

    it("can send/receive reasonably large payloads", function ()
      local payload = string.rep("a", 1024 * 1024 * 2)
      local msg = encode { payload = payload }
      local res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(err)
      assert.equals(payload, res)

      msg = encode { action = "rep", rep = stream_api.MAX_PAYLOAD_SIZE }
      res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(err)
      assert.equals(string.rep("1", stream_api.MAX_PAYLOAD_SIZE), res)
    end)
  end)

  describe("validation", function()
    it("limits payload sizes", function()
      local payload = string.rep("a", stream_api.MAX_PAYLOAD_SIZE + 1)
      local res, err = stream_api.request("stream-api-echo", payload, socket_path)
      assert.is_nil(res)
      assert.not_nil(err)
      assert.matches("max data size exceeded", err)
    end)

    it("limits request key sizes", function()
      local key = string.rep("k", 2^8)
      local res, err = stream_api.request(key, "test", socket_path)
      assert.is_nil(res)
      assert.not_nil(err)
      assert.matches("max key/status size exceeded", err)
    end)

    it("only allows strings for request keys/data", function()
      for _, typ in ipairs({ true, {}, 123, ngx.null }) do
        local ok, err = stream_api.request("test", typ, socket_path)
        assert.is_nil(ok)
        assert.matches("key and data must be strings", err)

        ok, err = stream_api.request(typ, "test", socket_path)
        assert.is_nil(ok)
        assert.matches("key and data must be strings", err)
      end
    end)
  end)

  describe("response error-handling", function()
    it("returns nil, string when the handler returns an error", function()
      local msg = encode { payload = nil, err = "test" }
      local res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(res)
      assert.matches("handler error: test", err)
    end)

    it("returns nil, string when the handler throws an exception", function()
      local msg = encode { action = "throw", err = "error!" }
      local res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(res)
      assert.matches("error!", err)
    end)

    it("returns nil, string when the handler returns too much data", function()
      local msg = encode { action = "rep", rep = stream_api.MAX_PAYLOAD_SIZE + 1 }
      local res, err = stream_api.request("stream-api-echo", msg, socket_path)
      assert.is_nil(res)
      assert.matches("handler response size", err)
    end)

    it("returns nil, string when the handler returns a non-string or non-table", function()
      for _, typ in ipairs({ true, 123, ngx.null }) do
        local msg = encode { payload = typ }
        local ok, err = stream_api.request("stream-api-echo", msg, socket_path)
        assert.is_nil(ok)
        assert.matches("invalid handler response type", err)
      end
    end)
  end)
end)
