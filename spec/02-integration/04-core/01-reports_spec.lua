local meta = require "kong.meta"
local helpers = require "spec.helpers"
local reports = require "kong.core.reports"

describe("reports", function()
  describe("send()", function()
    setup(function()
      reports.toggle(true)
    end)
    it("sends report over UDP", function()
      local thread = helpers.udp_server(8189)

      reports.send("stub", {
        hello = "world",
        foo = "bar"
      }, "127.0.0.1", 8189)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("^<14>", res)
      res = res:sub(5)
      assert.matches("cores=%d+", res)
      assert.matches("uname=[%w]+", res)
      assert.matches("version=" .. meta._VERSION, res, nil, true)
      assert.matches("hostname=[%w]+", res)
      assert.matches("foo=bar", res, nil, true)
      assert.matches("hello=world", res, nil, true)
      assert.matches("signal=stub", res, nil, true)
    end)
    it("doesn't send if not enabled", function()
      reports.toggle(false)

      local thread = helpers.udp_server(8189)

      reports.send({
        foo = "bar"
      }, "127.0.0.1", 8189)

      local ok, res, err = thread:join()
      assert.True(ok)
      assert.is_nil(res)
      assert.equal("timeout", err)
    end)
  end)
end)
