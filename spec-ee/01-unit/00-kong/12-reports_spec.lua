local helpers = require "spec.helpers"
local reports = require "kong.reports"


describe("reports", function()
  describe("send()", function()
    setup(function()
      reports.toggle(true)
    end)
    it("sends report over UDP", function()
      local thread = helpers.udp_server(8189)

      reports.send("stub", {
        hello = "world",
        foo = "bar",
        baz = function() return "bat" end,
        foobar = function() return { foo = "bar" } end,
        bazbat = { baz = "bat" },
        nilval = function() return nil end,
        a = function() return 1 end,
        c = function() return 2 end,
        r = function() return 3 end,
        s = function() return 4 end,
      }, "127.0.0.1", 8189)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("^<14>", res)
      res = res:sub(5)

      assert.matches("a=%d+", res)
      assert.matches("c=%d+", res)
      assert.matches("r=%d+", res)
      assert.matches("s=%d+", res)
    end)
  end)
end)
