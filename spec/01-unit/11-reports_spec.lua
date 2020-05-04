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

    it("sends report over TCP", function()
      local thread = helpers.tcp_server(8189)

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

      local thread = helpers.tcp_server(8189, { requests = 1, timeout = 0.1 })

      reports.send({
        foo = "bar"
      }, "127.0.0.1", 8189)

      local ok, res = thread:join()
      assert.True(ok)
      assert.equal("timeout", res)
    end)

    it("accepts custom immutable items", function()
      reports.toggle(true)

      local thread = helpers.tcp_server(8189)

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
      reports._create_counter()
    end)

    describe("sends 'database'", function()
      it("postgres", function()
        local conf = assert(conf_loader(nil, {
          database = "postgres",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert._matches("database=postgres", res, nil, true)
      end)

      it("cassandra", function()
        local conf = assert(conf_loader(nil, {
          database = "cassandra",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("database=cassandra", res, nil, true)
      end)

      it("off", function()
        local conf = assert(conf_loader(nil, {
          database = "off",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("database=off", res, nil, true)
      end)
    end)

    describe("sends 'role'", function()
      it("traditional", function()
        local conf = assert(conf_loader(nil))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert._matches("role=traditional", res, nil, true)
      end)

      it("control_plane", function()
        local conf = assert(conf_loader(nil, {
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_spec.crt",
          cluster_cert_key = "spec/fixtures/kong_spec.key",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("role=control_plane", res, nil, true)
      end)

      it("data_plane", function()
        local conf = assert(conf_loader(nil, {
          role = "data_plane",
          database = "off",
          cluster_cert = "spec/fixtures/kong_spec.crt",
          cluster_cert_key = "spec/fixtures/kong_spec.key",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("role=data_plane", res, nil, true)
      end)
    end)

    describe("sends 'kic'", function()
      it("default (off)", function()
        local conf = assert(conf_loader(nil))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert._matches("kic=false", res, nil, true)
      end)

      it("enabled", function()
        local conf = assert(conf_loader(nil, {
          kic = "on",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("kic=true", res, nil, true)
      end)
    end)

    describe("sends '_admin' for 'admin_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          admin_listen = "off",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_admin=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          admin_listen = "127.0.0.1:8001",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
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

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_proxy=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "127.0.0.1:8000",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
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

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_stream=0", res, nil, true)
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "127.0.0.1:8000",
        }))
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("_stream=1", res, nil, true)
      end)
    end)

    it("default configuration ping contents", function()
        local conf = assert(conf_loader())
        reports.configure_ping(conf)

        local thread = helpers.tcp_server(8189)
        reports.send_ping("127.0.0.1", 8189)

        local _, res = assert(thread:join())
        assert.matches("database=" .. helpers.test_conf.database, res, nil, true)
        assert.matches("_admin=1", res, nil, true)
        assert.matches("_proxy=1", res, nil, true)
        assert.matches("_stream=0", res, nil, true)
    end)
  end)

  describe("retrieve_redis_version()", function()
    lazy_setup(function()
      stub(ngx, "log")
    end)

    lazy_teardown(function()
      ngx.log:revert() -- luacheck: ignore
    end)

    before_each(function()
      package.loaded["kong.reports"] = nil
      reports = require "kong.reports"
      reports.toggle(true)
      reports._create_counter()
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
