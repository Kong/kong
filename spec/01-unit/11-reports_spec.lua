local meta = require "kong.meta"
local helpers = require "spec.helpers"
local reports = require "kong.reports"
local cjson = require "cjson"


describe("reports", function()
  describe("send()", function()
    lazy_setup(function()
      reports.toggle(true)
    end)

    lazy_teardown(function()
      package.loaded["kong.reports"] = nil
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
      assert.matches("baz=bat", res, nil, true)
      assert.not_matches("nilval", res, nil, true)
      assert.matches("foobar=" .. cjson.encode({ foo = "bar" }), res, nil, true)
      assert.matches("bazbat=" .. cjson.encode({ baz = "bat" }), res, nil, true)
    end)

    it("doesn't send if not enabled", function()
      reports.toggle(false)

      local thread = helpers.udp_server(8189, 1, 0.1)

      reports.send({
        foo = "bar"
      }, "127.0.0.1", 8189)

      local ok, res, err = thread:join()
      assert.True(ok)
      assert.is_nil(res)
      assert.equal("timeout", err)
    end)

    it("accepts custom immutable items", function()
      reports.toggle(true)

      local thread = helpers.udp_server(8189)

      reports.add_immutable_value("imm1", "fooval")
      reports.add_immutable_value("imm2", "barval")

      reports.send("stub", {k1 = "bazval"}, "127.0.0.1", 8189)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("imm1=fooval", res)
      assert.matches("imm2=barval", res)
      assert.matches("k1=bazval", res)
    end)
  end)

  describe("configure_ping()", function()
    local conf_loader = require "kong.conf_loader"

    before_each(function()
      package.loaded["kong.reports"] = nil
      reports = require "kong.reports"
      reports.toggle(true)
    end)

    describe("sends 'database'", function()
      it("postgres", function()
        local conf = assert(conf_loader(nil, {
          database = "postgres",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert._matches("database=postgres", res, nil, true)
      end)

      it("cassandra", function()
        local conf = assert(conf_loader(nil, {
          database = "cassandra",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("database=cassandra", res, nil, true)
      end)

      pending("off", function() -- XXX EE: enable when dbless is on
        local conf = assert(conf_loader(nil, {
          database = "off",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("database=off", res, nil, true)
      end)
    end)

    describe("sends '_admin' for 'admin_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          admin_listen = "off",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_admin=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          admin_listen = "127.0.0.1:8001",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_admin=1", res, nil, true)
      end)
    end)

    describe("sends '_proxy' for 'proxy_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "off",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_proxy=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "127.0.0.1:8000",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_proxy=1", res, nil, true)
      end)
    end)

    describe("sends '_stream' for 'stream_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "off",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_stream=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "127.0.0.1:8000",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_stream=1", res, nil, true)
      end)
    end)

    describe("sends '_orig' for 'origins'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          origins = ""
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_orig=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          origins = "http://localhost:8000=http://localhost:9000",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_orig=1", res, nil, true)
      end)
    end)

    describe("sends '_tip' for 'transparent'", function()
      it("not specified", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "127.0.0.1:9000",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_tip=0", res, nil, true)
      end)

      it("specified in 'stream_listen'", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "127.0.0.1:8000 transparent",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_tip=1", res, nil, true)
      end)

      it("specified in 'proxy_listen'", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "127.0.0.1:8000 transparent",
        }))
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_tip=1", res, nil, true)
      end)
    end)

    it("default configuration ping contents", function()
        local conf = assert(conf_loader())
        reports.configure_ping(conf)

        local thread = helpers.udp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("database=postgres", res, nil, true)
        assert.matches("_admin=1", res, nil, true)
        assert.matches("_proxy=1", res, nil, true)
        assert.matches("_stream=0", res, nil, true)
        assert.matches("_orig=0", res, nil, true)
        assert.matches("_tip=0", res, nil, true)
    end)
  end)

  describe("retrieve_redis_version()", function()
    lazy_setup(function()
      stub(ngx, "log")
    end)

    lazy_teardown(function()
      ngx.log:revert()
    end)

    before_each(function()
      package.loaded["kong.reports"] = nil
      reports = require "kong.reports"
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
