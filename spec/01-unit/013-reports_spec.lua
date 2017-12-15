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

  describe("retrieve_redis_version()", function()
    before_each(function()
      package.loaded["kong.core.reports"] = nil
      reports = require "kong.core.reports"
      reports.toggle(true)
    end)

    it("does not query Redis if not enabled", function()
      reports.toggle(false)

      local red_mock = {
        info = function() end,
      }

      local s = spy.on(red_mock, "info")

      reports.retrieve_redis_version(red_mock)
      assert.spy(s).was_not_called()
    end)

    it("queries Redis if enabled", function()
      local red_mock = {
        info = function()
          return "redis_version:2.4.5\r\nredis_git_sha1:e09e31b1"
        end,
      }

      local s = spy.on(red_mock, "info")

      reports.retrieve_redis_version(red_mock)
      assert.spy(s).was_called_with(red_mock, "server")
    end)

    it("queries Redis only once", function()
      local red_mock = {
        info = function()
          return "redis_version:2.4.5\r\nredis_git_sha1:e09e31b1"
        end,
      }

      local s = spy.on(red_mock, "info")

      reports.retrieve_redis_version(red_mock)
      reports.retrieve_redis_version(red_mock)
      reports.retrieve_redis_version(red_mock)
      assert.spy(s).was_called(1)
    end)

    it("retrieves major.minor version", function()
      local red_mock = {
        info = function()
          return "redis_version:2.4.5\r\nredis_git_sha1:e09e31b1"
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("2.4", reports.get_ping_value("redis_version"))
    end)

    it("retrieves 'unknown' when the version could not be retrieved (1/3)", function()
      local red_mock = {
        info = function()
          return nil
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("unknown", reports.get_ping_value("redis_version"))
    end)

    it("retrieves 'unknown' when the version could not be retrieved (2/3)", function()
      local red_mock = {
        info = function()
          return ngx.null
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("unknown", reports.get_ping_value("redis_version"))
    end)

    it("retrieves 'unknown' when the version could not be retrieved (3/3)", function()
      local red_mock = {
        info = function()
          return "hello world"
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("unknown", reports.get_ping_value("redis_version"))
    end)
  end)
end)
